# -*- coding: utf-8 -*-
"""
mkf.py -- 《仙剑奇侠传98柔情版》(WIN95 build) 资源容器与解压参考实现.

证据来源: 对本机 DATA 目录内 *.mkf 的实际字节解析 (见 docs/rea/evidence/assets/MKF-FORMAT.md)
参考: sdlpal palcommon.c / yj1.c / map.c / palcommon.c(RLE) [inference only]

容器 (已由 13 个 MKF 交叉验证):
  文件头 = uint32 head_words
  head_words = 4 * (nchunks + 1)  (即 offset 表字节数, 同时 == chunk0 起始偏移)
  offset 表 = (nchunks+1) 个 uint32, 位于文件起点(含 dword0)
  nchunks = (dword0 - 4) // 4
  chunk i = bytes[ off[i], off[i+1] ), i in [0, nchunks)
  off[nchunks] == 文件长度

压缩:
  本数据集合 (98柔情版/WIN95) 没有逐块压缩类型字段.
  对通过 Decompress() 读取的块 (MAP/MGO/FBP/ABC/FIRE ...):
     chunk 前 4 字节 = uint32 解压后长度, 其后为 YJ2 自适应 Huffman+LZ 流.
  对直接读取的块 (SSS/PAT/GOP/BALL/RNG/SOUNDS/MUS/...) : chunk 内容原样.
"""

import struct
import sys
import os

# ---------------------------------------------------------------- container

class MKF:
    def __init__(self, path):
        self.path = path
        with open(path, 'rb') as f:
            self.data = f.read()
        self.head_words = struct.unpack_from('<I', self.data, 0)[0]
        if self.head_words < 4 or self.head_words % 4:
            raise ValueError('bad MKF header %r' % self.head_words)
        self.nchunks = (self.head_words - 4) // 4
        self.offsets = list(struct.unpack_from('<%dI' % (self.nchunks + 1),
                                               self.data, 0))
        assert self.offsets[0] == self.head_words
        assert self.offsets[-1] == len(self.data), (path, self.offsets[-1], len(self.data))

    def size(self, i):
        return self.offsets[i + 1] - self.offsets[i]

    def raw(self, i):
        return self.data[self.offsets[i]:self.offsets[i + 1]]

    def chunk(self, i):
        """读取块; 若首 4 字节==解压长度且 YJ2 校验通过则解压, 否则原样返回."""
        raw = self.raw(i)
        out = try_decompress(raw)
        return raw if out is None else out

    def dtype(self, i):
        raw = self.raw(i)
        return 'raw' if try_decompress(raw) is None else 'yj2'

    def info(self):
        return dict(path=self.path, size=len(self.data), nchunks=self.nchunks,
                    head_words=self.head_words,
                    sizes=[self.size(i) for i in range(self.nchunks)])


# ---------------------------------------------------------------- YJ2 (WIN95)

_YJ2_DATA1 = bytes.fromhex(
    '3f0b17032f0a16002e0915022d0108003e0714032c0613002b0512022a010400'
    '3d0b1103290a100028090f02270108003c070e0326060d0025050c0224010400'
    '3b0b1703230a160022091502210108003a071403200613001f0512021e010400'
    '390b11031d0a10001c090f021b01080038070e031a060d0019050c0218010400'
    '370b17032f0a16002e0915022d010800360714032c0613002b0512022a010400'
    '350b1103290a100028090f022701080034070e0326060d0025050c0224010400'
    '330b1703230a1600220915022101080032071403200613001f0512021e010400'
    '310b11031d0a10001c090f021b01080030070e031a060d0019050c0218010400')
_YJ2_DATA2 = bytes.fromhex('08050604070506030705060407040503')


class _YJ2Tree:
    __slots__ = ('w', 'v', 'p', 'l', 'r', 'list')

    def __init__(self):
        # nodes 0..0x280, arrays indexed by node index
        self.w = [0] * 0x281
        self.v = [0] * 0x281
        self.p = [0] * 0x281
        self.l = [0] * 0x281
        self.r = [0] * 0x281
        self.list = [0] * 0x141
        for i in range(0x141):
            self.list[i] = i
        for i in range(0x281):
            self.v[i] = i
            self.w[i] = 1
        self.p[0x280] = 0x280
        i = 0
        for ptr in range(0x141, 0x281):
            self.l[ptr] = i
            self.r[ptr] = i + 1
            self.p[i] = ptr
            self.p[i + 1] = ptr
            self.w[ptr] = self.w[i] + self.w[i + 1]
            i += 2

    def adjust(self, value):
        w, v, p, l, r = self.w, self.v, self.p, self.l, self.r
        lst = self.list
        n = lst[value]
        while v[n] != 0x280:
            t = n + 1
            while w[t] == w[n]:
                t += 1
            t -= 1
            if t != n:
                # swap parents first (verbatim order from sdlpal yj1.c)
                p[n], p[t] = p[t], p[n]
                vn, vt = v[n], v[t]
                if vn > 0x140:
                    p[l[n]] = t
                    p[r[n]] = t
                else:
                    lst[vn] = t
                if vt > 0x140:
                    p[l[t]] = n
                    p[r[t]] = n
                else:
                    lst[vt] = n
                # swap whole node records
                for arr in (w, v, p, l, r):
                    arr[n], arr[t] = arr[t], arr[n]
                n = t
            w[n] += 1
            n = p[n]
        w[n] += 1


def _bt(src, pos):
    return (src[pos >> 3] >> (pos & 7)) & 1


def yj2_decompress(src, dest_size=None):
    """YJ2: src 前 4B = 解压长度, 其余为自适应 Huffman + LZ 位流."""
    if len(src) < 8:
        return None
    length = struct.unpack_from('<I', src, 0)[0]
    if dest_size is not None and length != dest_size:
        return None
    if length == 0 or length > 8 << 20:
        return None
    body = src[4:]
    tree = _YJ2Tree()
    w, v, p, l, r = tree.w, tree.v, tree.p, tree.l, tree.r
    dest = bytearray()
    ptr = 0
    nbits = len(body) * 8
    while True:
        node = 0x280
        while v[node] > 0x140:
            if ptr >= nbits:
                return None
            if _bt(body, ptr):
                node = r[node]
            else:
                node = l[node]
            ptr += 1
            if node > 0x280:
                return None
        val = v[node]
        if w[0x280] == 0x8000:
            for i in range(0x141):
                if w[tree.list[i]] & 1:
                    tree.adjust(i)
            for i in range(0x281):
                w[i] >>= 1
        tree.adjust(val)
        if val > 0xff:
            temp = 0
            for i in range(8):
                if ptr >= nbits:
                    return None
                temp |= _bt(body, ptr) << i
                ptr += 1
            tmp = temp & 0xff
            i = 8
            extra = _YJ2_DATA2[tmp & 0xf] + 6
            while i < extra:
                if ptr >= nbits:
                    return None
                temp |= _bt(body, ptr) << i
                ptr += 1
                i += 1
            temp >>= _YJ2_DATA2[tmp & 0xf]
            pos = (temp & 0x3f) | (_YJ2_DATA1[tmp] << 6)
            if pos == 0xfff:
                break
            if pos + 1 > len(dest):
                return None
            for _ in range(val - 0xfd):
                dest.append(dest[-pos - 1])
        else:
            dest.append(val)
        if len(dest) > length:
            return None
    if len(dest) != length:
        return None
    return bytes(dest)


# ---------------------------------------------------------------- YJ1 (DOS, reference only)

def yj1_decompress(src, dest_size=None):
    """DOS 版 'YJ_1' 流. 本机 98 柔情版数据未使用, 仅作算法对照."""
    if len(src) < 16 or src[:4] != b'YJ_1':
        return None
    unc_len, cmp_len, block_count, unknown, tree_len = struct.unpack_from('<IIIBB', src, 4)
    if dest_size is not None and unc_len != dest_size:
        return None
    tree_len = tree_len * 2
    dest = bytearray()
    # huffman tree
    def get_bits(base, bitptr, count):
        boff = (bitptr[0] >> 4) << 1
        bptr = bitptr[0] & 0xf
        bitptr[0] += count
        lo = src[base + boff] | (src[base + boff + 1] << 8)
        hi = src[base + boff + 2] | (src[base + boff + 3] << 8)
        if count > 16 - bptr:
            cnt = count + bptr - 16
            mask = 0xffff >> bptr
            return (((lo & mask) << cnt) | (hi >> (16 - cnt))) & 0xffff
        return ((lo << bptr) >> (16 - count)) & 0xffff

    flag = src[16:16 + tree_len]
    bitptr = [0]
    left = [0] * (tree_len + 1)
    right = [0] * (tree_len + 1)
    leaf = [0] * (tree_len + 1)
    value = [0] * (tree_len + 1)
    left[0], right[0] = 1, 2
    for i in range(1, tree_len + 1):
        leaf[i] = 0 if get_bits(16, bitptr, 1) else 1
        value[i] = src[15 + i]
        if not leaf[i]:
            left[i] = (value[i] << 1) + 1
            right[i] = left[i] + 1
    body = 16 + tree_len + (((tree_len + 15) >> 4) << 1)
    srcp = body
    for _blk in range(block_count):
        ulen, clen = struct.unpack_from('<HH', src, srcp)
        hdr = src[srcp:srcp + 24]
        repeat = list(struct.unpack_from('<4H', hdr, 4))
        offcl = list(struct.unpack_from('<4B', hdr, 12))
        repcl = list(struct.unpack_from('<3B', hdr, 16))
        cntcl = list(struct.unpack_from('<3B', hdr, 19))
        cntt = list(struct.unpack_from('<2B', hdr, 22))
        srcp += 4
        if clen == 0:
            dest += src[srcp:srcp + ulen]
            srcp += ulen
            continue
        srcp += 20
        bitptr = [0]
        stream = src[srcp - 24:]  # header start; bit offsets are relative to body
        # bit reading base: stream body starts at srcp
        def gb(count, base=srcp):
            return get_bits(base, bitptr, count)

        def get_loop():
            if gb(1):
                return cntt[0]
            t = gb(2)
            if t:
                return gb(cntcl[t - 1])
            return cntt[1]

        while True:
            loop = get_loop()
            if loop == 0:
                break
            for _ in range(loop):
                node = 0
                while not leaf[node]:
                    node = right[node] if gb(1) else left[node]
                dest.append(value[node])
            loop = get_loop()
            if loop == 0:
                break
            for _ in range(loop):
                t = gb(2)
                if t:
                    if gb(1):
                        count = gb(repcl[t - 1])
                    else:
                        count = repeat[t]
                else:
                    count = repeat[0]
                pos = gb(2)
                pos = gb(offcl[pos])
                for _ in range(count):
                    if pos == 0 or pos > len(dest):
                        return None
                    dest.append(dest[-pos])
        srcp = srcp - 24 + clen
    if len(dest) != unc_len:
        return None
    return bytes(dest)


# ---------------------------------------------------------------- auto detect

def try_decompress(raw, dest_size=None):
    """尝试把块解释为 YJ2; 失败返回 None."""
    if len(raw) < 12:
        return None
    if raw[:4] == b'YJ_1':
        return yj1_decompress(raw, dest_size)
    return yj2_decompress(raw, dest_size)


# ---------------------------------------------------------------- sprite / RLE

def sprite_frames(chunk):
    """PAL sprite (MGO/ABC/FIRE/GOP/BALL):
       WORD n; 之后紧跟 n 个 WORD.
       word[0] == n 同时充当 (a) 偏移表长度 n 个字 (b) 帧 0 的起始字偏移.
       => 帧 0 起始字节 = n*2; 帧 k (k=0..n-2) 起始字节 = word[k]*2.
       word[n-1] == 0 为表尾哨兵, 不是帧.
       真实帧数 = n-1 (与 sdlpal PAL_SpriteGetNumFrames 一致).
    """
    n = struct.unpack_from('<H', chunk, 0)[0]
    if n < 2 or 2 * n > len(chunk):
        return []
    offs = list(struct.unpack_from('<%dH' % n, chunk, 0))
    frames = []
    for k in range(n - 1):
        start = offs[k] * 2
        end = offs[k + 1] * 2 if k + 1 < n - 1 else len(chunk)
        if start < 2 * n or start > len(chunk) or end < start:
            return []
        frames.append(chunk[start:end])
    return frames


def rle_bitmap(bm):
    """PAL BITMAPRLE -> (w,h,bytes of palette indices, length w*h)."""
    if len(bm) >= 4 and bm[0] == 2 and bm[1] == 0 and bm[2] == 0 and bm[3] == 0:
        bm = bm[4:]
    if len(bm) < 4:
        return None
    w, h = struct.unpack_from('<HH', bm, 0)
    if w == 0 or h == 0 or w > 2048 or h > 2048:
        return None
    total = w * h
    px = bytearray()
    i = 4
    while len(px) < total:
        if i >= len(bm):
            return None
        t = bm[i]
        i += 1
        if (t & 0x80) and t <= 0x80 + w:
            px += b'\x00' * (t - 0x80)
        else:
            if i + t > len(bm):
                return None
            px += bm[i:i + t]
            i += t
    return w, h, bytes(px[:total])


def palette_from_pat(pat, index, night=False):
    """pat.mkf 块: 1536B(day+night) 或 768B(day only); 6bit VGA -> 8bit."""
    raw = pat.raw(index)
    off = 768 if night and len(raw) >= 1536 else 0
    pal = []
    for i in range(256):
        r, g, b = raw[off + i * 3:off + i * 3 + 3]
        pal.append((r << 2, g << 2, b << 2))
    return pal


def save_indexed_png(path, w, h, indices, palette, transparent0=True):
    """把 8bpp 索引图 + 256 色调色板写成 RGBA PNG (Pillow)."""
    from PIL import Image
    img = Image.new('RGBA', (w, h), (0, 0, 0, 255))
    pix = img.load()
    for y in range(h):
        row = indices[y * w:(y + 1) * w]
        for x, ci in enumerate(row):
            if transparent0 and ci == 0:
                continue
            pix[x, y] = palette[ci] + (255,)
    img.save(path)
    return path


def compose_rle_frames(path, frames, palette, cols=None, scale=1,
                       bg=(16, 16, 16)):
    """把若干 RLE 帧拼成雪碧图 PNG (每帧左上角对齐, 便于人眼查验)."""
    from PIL import Image
    bms = []
    for f in frames:
        r = rle_bitmap(f)
        if r:
            bms.append(r)
    if not bms:
        return None
    cols = cols or min(len(bms), 8)
    cw = max(b[0] for b in bms)
    ch = max(b[1] for b in bms)
    rows = (len(bms) + cols - 1) // cols
    img = Image.new('RGBA', (cols * cw, rows * ch), bg + (255,))
    for k, (w, h, px) in enumerate(bms):
        cx = (k % cols) * cw
        cy = (k // cols) * ch
        for y in range(h):
            for x in range(w):
                ci = px[y * w + x]
                if ci == 0:
                    continue
                img.putpixel((cx + x, cy + y), palette[ci] + (255,))
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(path)
    return path


# ---------------------------------------------------------------- CLI

def main(argv):
    if len(argv) < 2:
        print('usage: mkf.py <file.mkf> [dumpdir]')
        return 1
    mkf = MKF(argv[1])
    print('%s size=%d nchunks=%d head_words=%d' %
          (mkf.path, len(mkf.data), mkf.nchunks, mkf.head_words))
    for i in range(mkf.nchunks):
        raw = mkf.raw(i)
        t = 'raw'
        dec = None
        if len(raw) >= 12:
            dec = try_decompress(raw)
            if dec is not None:
                t = 'yj2->%d' % len(dec)
        print('  chunk %4d off=%8d size=%7d %-12s first=%s' %
              (i, mkf.offsets[i], len(raw), t, raw[:8].hex()))
        if len(argv) > 2 and dec is not None:
            os.makedirs(argv[2], exist_ok=True)
            open(os.path.join(argv[2], '%04d.bin' % i), 'wb').write(dec)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

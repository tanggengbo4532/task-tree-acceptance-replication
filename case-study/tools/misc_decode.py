# -*- coding: utf-8 -*-
"""
misc_decode.py -- 其余资源格式的解析/渲染 (任务第 6 项):
  Fbp.mkf  战斗背景 (YJ2 -> 64000B = 320x200 8bpp 全屏索引图)
  Abc.mkf  战斗角色帧 (YJ2 -> sprite, RLE 帧)
  Fire.mkf 战斗法术效果帧 (YJ2 -> sprite)
  Ball.mkf 物品图标 (raw sprite)
  Pat.mkf  调色板 (9 块, 6bit VGA; 块 0/5 = day+night 768*2 B)
  Rng.mkf  战斗动画: 块 = 嵌套 MKF(帧), 每帧 = YJ2 压缩的 0x00-0x13 命令流,
           命令流写入 320x200 8bpp 画面 (逐帧增量, 需累积)  [inference: sdlpal rngplay.c]
  Sounds.mkf 363 个 RIFF/WAVE
  MUS.MKF  RIX 音乐 (未解码, [unknown])
  Word.dat 565 x 10B GBK 名称表
  0.rpg    [unknown] 存档/记录数据
  Data.mkf 全局数据索引 (15 块)
"""
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

import mkf

DATA_DIR = r'<LOCAL_PATH>'
OUT_DIR = r'<LOCAL_PATH>'


def save_screen(path, buf, palette, w=320, h=200):
    idx = np.frombuffer(buf[:w * h], dtype=np.uint8).reshape(h, w)
    lut = np.zeros((256, 4), dtype=np.uint8)
    lut[:, 0] = [c[0] for c in palette]
    lut[:, 1] = [c[1] for c in palette]
    lut[:, 2] = [c[2] for c in palette]
    lut[:, 3] = 255
    Image.fromarray(lut[idx], 'RGBA').save(path)
    return path


def render_sprite_sheet(path, sprite_chunk, palette, cols=8, scale=2):
    return mkf.compose_rle_frames(path, mkf.sprite_frames(sprite_chunk),
                                  palette, cols=cols, scale=scale)


# ---------------------------------------------------------------- RNG decoding

def _rng_pair(img, dst, a, b):
    if 0 <= dst < 64000:
        img[dst] = a
    if 0 <= dst + 1 < 64000:
        img[dst + 1] = b


def rng_apply_frame(img, s):
    """把一帧解压后的命令流累积到 img(bytearray 64000). 返回是否正常结束."""
    ptr = 0
    dst = 0
    n = len(s)
    while ptr < n:
        cmd = s[ptr]
        ptr += 1
        if cmd in (0x00, 0x13):
            return True
        elif cmd == 0x02:
            dst += 2
        elif cmd == 0x03:
            if ptr >= n:
                return False
            d = s[ptr]
            ptr += 1
            dst += (d + 1) * 2
        elif cmd == 0x04:
            if ptr + 1 >= n:
                return False
            d = s[ptr] | (s[ptr + 1] << 8)
            ptr += 2
            dst += (d + 1) * 2
        elif 0x06 <= cmd <= 0x0a:
            for _ in range(cmd - 0x05):
                if ptr + 1 >= n:
                    return False
                _rng_pair(img, dst, s[ptr], s[ptr + 1])
                ptr += 2
                dst += 2
        elif cmd == 0x0b:
            if ptr >= n:
                return False
            d = s[ptr]
            ptr += 1
            for _ in range(d + 1):
                if ptr + 1 >= n:
                    return False
                _rng_pair(img, dst, s[ptr], s[ptr + 1])
                ptr += 2
                dst += 2
        elif cmd == 0x0c:
            if ptr + 1 >= n:
                return False
            d = s[ptr] | (s[ptr + 1] << 8)
            ptr += 2
            for _ in range(d + 1):
                if ptr + 1 >= n:
                    return False
                _rng_pair(img, dst, s[ptr], s[ptr + 1])
                ptr += 2
                dst += 2
        elif 0x0d <= cmd <= 0x10:
            cnt = cmd - 11
            for _ in range(cnt):
                if ptr + 1 >= n:
                    return False
                _rng_pair(img, dst, s[ptr], s[ptr + 1])
                dst += 2
            ptr += 2
        elif cmd == 0x11:
            if ptr >= n:
                return False
            d = s[ptr]
            ptr += 1
            for _ in range(d + 1):
                if ptr + 1 >= n:
                    return False
                _rng_pair(img, dst, s[ptr], s[ptr + 1])
                ptr += 2
                dst += 2
        elif cmd == 0x12:
            if ptr + 1 >= n:
                return False
            d = (s[ptr] | (s[ptr + 1] << 8)) + 1
            ptr += 2
            for _ in range(d):
                if ptr + 1 >= n:
                    return False
                _rng_pair(img, dst, s[ptr], s[ptr + 1])
                ptr += 2
                dst += 2
        # 其它命令: 忽略
    return False


def rng_decode_animation(chunk):
    """返回 (frames_streams, cumulative_images, all_ok).
    嵌套 MKF: dword0=头部字节=4*(n+1), 帧 i=[off[i],off[i+1]);
    实测最后一个"帧"长度为 0, 所以有效帧数 = n-1."""
    n = (struct.unpack_from('<I', chunk, 0)[0] - 4) // 4
    offs = struct.unpack_from('<%dI' % (n + 1), chunk, 0)
    img = bytearray(64000)
    streams = []
    images = []
    ok = True
    for i in range(n):
        raw = chunk[offs[i]:offs[i + 1]]
        if not raw:
            continue  # 末尾空帧
        dec = mkf.yj2_decompress(raw)
        if dec is None:
            ok = False
            streams.append(None)
        else:
            streams.append(dec)
            rng_apply_frame(img, dec)
        images.append(bytes(img))
    return streams, images, ok


# ---------------------------------------------------------------- main

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    pat = mkf.MKF(os.path.join(DATA_DIR, 'Pat.mkf'))
    pal0 = mkf.palette_from_pat(pat, 0)
    result = {}

    # FBP 战斗背景
    fbp = mkf.MKF(os.path.join(DATA_DIR, 'Fbp.mkf'))
    for i in (0, 1):
        dec = fbp.chunk(i)
        assert len(dec) == 64000
        p = os.path.join(OUT_DIR, 'fbp_bg%d.png' % i)
        save_screen(p, dec, pal0)
        result['fbp_%d' % i] = p
    # 前 12 个非空 FBP 块拼图 (自检观看)
    lut = np.zeros((256, 4), dtype=np.uint8)
    lut[:, 0] = [c[0] for c in pal0]
    lut[:, 1] = [c[1] for c in pal0]
    lut[:, 2] = [c[2] for c in pal0]
    lut[:, 3] = 255
    sel = [i for i in range(fbp.nchunks) if fbp.raw(i)][:12]
    montage = Image.new('RGB', (320 * 3, 200 * 4), (0, 0, 0))
    for k, i in enumerate(sel):
        idx = np.frombuffer(fbp.chunk(i), dtype=np.uint8).reshape(200, 320)
        montage.paste(Image.fromarray(lut[idx], 'RGBA').convert('RGB'),
                      ((k % 3) * 320, (k // 3) * 200))
    montage.save(os.path.join(OUT_DIR, 'fbp_montage.png'))
    result['fbp_montage'] = os.path.join(OUT_DIR, 'fbp_montage.png')
    print('fbp -> 2 png + montage')

    # ABC 战斗角色
    abc = mkf.MKF(os.path.join(DATA_DIR, 'Abc.mkf'))
    for i in (1, 2, 3):
        p = render_sprite_sheet(os.path.join(OUT_DIR, 'abc_enemy%d.png' % i),
                                abc.chunk(i), pal0, cols=8, scale=2)
        result['abc_%d' % i] = p
        print('abc', i, '->', p)

    # FIRE 法术效果
    fire = mkf.MKF(os.path.join(DATA_DIR, 'Fire.mkf'))
    for i in (0, 1):
        p = render_sprite_sheet(os.path.join(OUT_DIR, 'fire_effect%d.png' % i),
                                fire.chunk(i), pal0, cols=8, scale=2)
        result['fire_%d' % i] = p
        print('fire', i, '->', p)

    # BALL 物品图标
    ball = mkf.MKF(os.path.join(DATA_DIR, 'Ball.mkf'))
    p = render_sprite_sheet(os.path.join(OUT_DIR, 'ball_items.png'),
                            ball.raw(1), pal0, cols=8, scale=3)
    result['ball_1'] = p
    print('ball ->', p)

    # PAT 调色板条: 9 条色带, 每条 8px 高, 每色占 3px (768 宽)
    img = Image.new('RGB', (768, 9 * 8), (0, 0, 0))
    for i in range(pat.nchunks):
        pal = mkf.palette_from_pat(pat, i)
        for x in range(768):
            for k in range(8):
                img.putpixel((x, i * 8 + k), pal[x // 3])
    img.save(os.path.join(OUT_DIR, 'pat_palettes.png'))
    result['pat_palettes'] = os.path.join(OUT_DIR, 'pat_palettes.png')

    # RNG
    rng = mkf.MKF(os.path.join(DATA_DIR, 'Rng.mkf'))
    rng_info = {}
    for i in range(rng.nchunks):
        chunk = rng.raw(i)
        streams, images, ok = rng_decode_animation(chunk)
        last = images[-1] if images else None
        rng_info[i] = dict(size=len(chunk), frames=len(streams), ok=ok,
                           dec_lengths=[len(s) for s in streams if s][:5])
        if i == 0 and last:
            for f in (0, len(images) // 2, len(images) - 1):
                p = os.path.join(OUT_DIR, 'rng0_frame%03d.png' % f)
                save_screen(p, images[f], pal0)
                result['rng0_%d' % f] = p
        if i == 1 and last:
            p = os.path.join(OUT_DIR, 'rng1_last.png')
            save_screen(p, last, pal0)
            result['rng1_last'] = p
    print('rng', rng_info)
    with open(os.path.join(OUT_DIR, 'rng_index.json'), 'w', encoding='utf-8') as f:
        json.dump(rng_info, f, ensure_ascii=False, indent=0)

    # Sounds / MUS / Word / Data / 0.rpg 索引
    sounds = mkf.MKF(os.path.join(DATA_DIR, 'Sounds.mkf'))
    snd = {}
    for i in range(sounds.nchunks):
        r = sounds.raw(i)
        if len(r) >= 44 and r[:4] == b'RIFF':
            fmt = r[20:22]
            snd[i] = dict(size=len(r), riff_len=struct.unpack_from('<I', r, 4)[0],
                          wave_bytes=len(r) - 44)
    sound_index = dict(chunks=sounds.nchunks, riffs=len(snd),
                       empty=sum(1 for i in range(sounds.nchunks)
                                 if not sounds.raw(i)),
                       sample=list(snd.items())[:16])

    mus = mkf.MKF(os.path.join(DATA_DIR, 'MUS.MKF'))
    mus_index = dict(chunks=mus.nchunks,
                     heads=[mus.raw(i)[:16].hex() for i in range(1, 10)])

    wd = open(os.path.join(DATA_DIR, 'Word.dat'), 'rb').read()
    words = []
    for i in range(len(wd) // 10):
        s = wd[i * 10:(i + 1) * 10].decode('gbk', errors='replace').rstrip(' \x00')
        words.append(s)
    word_index = dict(word_len=10, count=len(words), words=words)

    dm = mkf.MKF(os.path.join(DATA_DIR, 'Data.mkf'))
    data_index = dict(chunks=dm.nchunks,
                      sizes=[dm.size(i) for i in range(dm.nchunks)],
                      kinds=[dm.dtype(i) for i in range(dm.nchunks)])

    rpg = open(os.path.join(DATA_DIR, '0.rpg'), 'rb').read()
    rpg_index = dict(size=len(rpg), head=rpg[:64].hex(),
                     ascii_runs=[])
    cur = b''
    for c in rpg[:4096]:
        if 32 <= c < 127:
            cur += bytes([c])
        else:
            if len(cur) >= 5:
                rpg_index['ascii_runs'].append(cur.decode())
            cur = b''

    misc = dict(fbp=result, rng=rng_info, sounds=sound_index, mus=mus_index,
                word=word_index, data=data_index, rpg=rpg_index)
    with open(os.path.join(OUT_DIR, 'misc_index.json'), 'w', encoding='utf-8') as f:
        json.dump(misc, f, ensure_ascii=False, indent=0)
    print('wrote misc_index.json')
    print('sounds riffs', len(snd), 'word count', len(words))
    print('0.rpg ascii runs', rpg_index['ascii_runs'][:10])
    print('data kinds', data_index['kinds'])


if __name__ == '__main__':
    main()

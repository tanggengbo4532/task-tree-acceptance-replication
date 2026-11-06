# -*- coding: utf-8 -*-
"""
mgo_decode.py -- MGO.MKF 精灵解码 + 玩家/NPC 精灵表 PNG.

MGO 块 (全部 636/637 块为 YJ2 压缩):
  YJ2 解压后 = PAL SPRITE:
    WORD n          帧数+1 (word[0] 同时是偏移表长度和帧 0 的字偏移)
    WORD offs[n]    帧 k 起始字节 = offs[k]*2;  offs[0]==n
    帧数据 = BITMAPRLE: WORD w, WORD h, 然后 RLE 流
      T = 下一字节
      if (T & 0x80) and T <= 0x80+w : 跳过 (T-0x80) 个透明像素
      else: 紧跟 T 个调色板索引字节 (逐行连续)
  实际帧数 = n-1.

玩家 6 角色 MGO 块号来自 DATA.MKF 块 3 (PLAYERROLES) 的 rgwSpriteNum[6]
= (2,3,7,525,5,26), 每块 12 帧 = 4 方向 x 3 行走帧; 帧号 = 方向*3 + 步帧,
方向 0=南 1=西 2=北 3=东 (sdlpal palcommon.h kDir*).
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
DIR_NAMES = ['S', 'W', 'N', 'E']


def load_player_sprite_ids():
    dm = mkf.MKF(os.path.join(DATA_DIR, 'Data.mkf'))
    pr = dm.raw(3)
    w = struct.unpack('<%dH' % (len(pr) // 2), pr)
    return list(w[12:18]), list(w[0:6]), list(w[18:24])


def sprite_info(chunk):
    frames = mkf.sprite_frames(chunk)
    out = []
    for f in frames:
        r = mkf.rle_bitmap(f)
        out.append(None if r is None else (r[0], r[1]))
    return frames, out


def render_sheet(frames, palette, out_png, cols=None, rows=None, bg=(24, 24, 24),
                 scale=3, labels=None):
    bms = [mkf.rle_bitmap(f) for f in frames]
    good = [b for b in bms if b]
    if not good:
        return None
    cw = max(b[0] for b in good)
    ch = max(b[1] for b in good)
    if rows is None:
        cols = cols or len(good)
        rows = (len(good) + cols - 1) // cols
    img = Image.new('RGBA', (cols * (cw + 2), rows * (ch + 2)), bg + (255,))
    for k, b in enumerate(bms):
        if not b:
            continue
        w, h, px = b
        cx = (k % cols) * (cw + 2) + 1
        cy = (k // cols) * (ch + 2) + 1
        arr = np.frombuffer(px, dtype=np.uint8).reshape(h, w)
        for y in range(h):
            for x in range(w):
                ci = int(arr[y, x])
                if ci:
                    img.putpixel((cx + x, cy + y), palette[ci] + (255,))
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(out_png)
    return img.size


def main():
    mg = mkf.MKF(os.path.join(DATA_DIR, 'Mgo.mkf'))
    pat = mkf.MKF(os.path.join(DATA_DIR, 'Pat.mkf'))
    pal = mkf.palette_from_pat(pat, 0)
    sprite_ids, avatars, names = load_player_sprite_ids()
    print('PLAYERROLES mgo sprite ids', sprite_ids)

    index = {}
    for i in range(1, mg.nchunks):
        raw = mg.raw(i)
        if not raw:
            continue
        dec = mg.chunk(i)
        frames, dims = sprite_info(dec)
        index[i] = dict(chunk=i, comp=len(raw), dec=len(dec),
                        frames=len(frames),
                        dims=sorted(set(d for d in dims if d)))

    # 6 个玩家角色: 4 行(方向) x 3 列(步帧)
    for role, sid in enumerate(sprite_ids):
        dec = mg.chunk(sid)
        frames = mkf.sprite_frames(dec)
        out = os.path.join(OUT_DIR, 'mgo_player%d_role%d.png' % (role, sid))
        size = render_sheet(frames, pal, out, cols=3, rows=4, scale=3)
        print('player role', role, 'mgo', sid, 'frames', len(frames), '->', out, size)

    # NPC 示例: 取 Sss 场景 2 的事件对象精灵号
    sss = mkf.MKF(os.path.join(DATA_DIR, 'Sss.mkf'))
    ev = sss.raw(0)
    scene = struct.unpack_from('<4H', sss.raw(1), 8)  # scene idx 1 = 场景2
    first = scene[3] + 1
    npc_ids = []
    for i in range(first, min(first + 12, len(ev) // 32)):
        w = struct.unpack_from('<16H', ev, i * 32)
        s = w[8]
        if s and s not in npc_ids:
            npc_ids.append(s)
    print('scene2 npc mgo ids', npc_ids)
    for sid in npc_ids[:6]:
        if sid >= mg.nchunks:
            continue
        dec = mg.chunk(sid)
        frames = mkf.sprite_frames(dec)
        out = os.path.join(OUT_DIR, 'mgo_npc_scene2_%d.png' % sid)
        size = render_sheet(frames, pal, out, cols=3, scale=3)
        print('npc mgo', sid, 'frames', len(frames), '->', out, size)

    with open(os.path.join(OUT_DIR, 'mgo_index.json'), 'w', encoding='utf-8') as f:
        json.dump(dict(nchunks=mg.nchunks, player_sprites=sprite_ids,
                       player_avatars=avatars, player_names=names,
                       sprites=index), f, ensure_ascii=False, indent=0)
    print('wrote mgo_index.json', len(index), 'sprites')


if __name__ == '__main__':
    main()

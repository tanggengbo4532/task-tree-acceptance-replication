# -*- coding: utf-8 -*-
"""
map_render.py -- 把 MAP.MKF 的 16K 图块数据 + GOP.MKF 的图块位图渲染成整张地图 PNG.

证据:
  MAP 块经 YJ2 解压后恒为 65536 字节 = 64(x) * 128(y) * 2(h) * 4(DWORD).
  DWORD 位域 (sdlpal map.h/map.c 交叉验证, 已用实际 tile 索引 <= GOP 帧数验证):
    bit  0..7   : 底层图块号低 8 位
    bit  8..11  : 高度/遮挡值 (0..15)
    bit 12..13  : 0x2000 阻挡位 (bit13)
    bit 16..23  : 顶层图块号低 8 位
    底层索引 = (d & 0xFF) | ((d >> 4) & 0x100)
    顶层索引 = ((d>>16 & 0xFF) | ((d>>20) & 0x100)) - 1   (0 => 空)
  GOP 块 = sprite: WORD n; n 个 WORD 偏移; 帧 0 起于 n*2 字节; 图块位图 = RLE 32x15.
  绘制: 先整张底层再整张顶层;
        tile(y,h,x) 像素位置 = (x*32 + h*16, y*16 + h*8)   (全图坐标, 已含 -16/-8 基准)
        全图尺寸 = 64*32+16 = 2064 x 128*16+8 = 2056.
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

PALETTE_INDEX = 0          # 游戏启动默认 wNumPalette = 0


def load_tiles(map_id):
    m = mkf.MKF(os.path.join(DATA_DIR, 'Map.mkf'))
    raw = m.chunk(map_id)
    assert len(raw) == 65536, (map_id, len(raw))
    return struct.unpack('<16384I', raw)


def load_tile_bitmaps(map_id):
    g = mkf.MKF(os.path.join(DATA_DIR, 'Gop.mkf'))
    frames = mkf.sprite_frames(g.raw(map_id))
    bms = []
    for f in frames:
        r = mkf.rle_bitmap(f)
        bms.append(r)
    return bms


def palette(pat, index=PALETTE_INDEX, night=False):
    p = mkf.palette_from_pat(pat, index, night)
    lut = np.zeros((256, 4), dtype=np.uint8)
    lut[:, 0] = [c[0] for c in p]
    lut[:, 1] = [c[1] for c in p]
    lut[:, 2] = [c[2] for c in p]
    lut[:, 3] = 255
    return lut


def render_map(map_id, out_png, pat_index=PALETTE_INDEX, night=False,
               crop=True, scale=1):
    tiles = load_tiles(map_id)
    bms = load_tile_bitmaps(map_id)
    pat = mkf.MKF(os.path.join(DATA_DIR, 'Pat.mkf'))
    lut = palette(pat, pat_index, night)

    W, H = 64 * 32 + 16, 128 * 16 + 8
    canvas = np.zeros((H, W), dtype=np.uint8)

    used = []
    for layer in (0, 1):
        for y in range(128):
            for h in (0, 1):
                y0 = y * 16 + h * 8
                for x in range(64):
                    d = tiles[(y * 64 + x) * 2 + h]
                    if layer == 0:
                        idx = (d & 0xFF) | ((d >> 4) & 0x100)
                        if d:
                            used.append((x, y, h))
                    else:
                        dd = d >> 16
                        idx = ((dd & 0xFF) | ((dd >> 4) & 0x100)) - 1
                        if idx < 0:
                            continue
                    if idx >= len(bms) or bms[idx] is None:
                        continue
                    w, hh, px = bms[idx]
                    arr = np.frombuffer(px, dtype=np.uint8).reshape(hh, w)
                    x0 = x * 32 + h * 16
                    sub = canvas[y0:y0 + hh, x0:x0 + w]
                    m = arr != 0
                    sub[m] = arr[m]

    img = Image.fromarray(lut[canvas], 'RGBA')
    if crop and used:
        xs = [u[0] for u in used]
        ys = [u[1] for u in used]
        x0 = max(0, min(xs) * 32 - 16)
        y0 = max(0, min(ys) * 16 - 8)
        x1 = min(W, (max(xs) + 1) * 32 + 32)
        y1 = min(H, (max(ys) + 2) * 16 + 8)
        img = img.crop((x0, y0, x1, y1))
    if scale != 1:
        img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
    img.save(out_png)
    return out_png, img.size


def main(argv):
    os.makedirs(OUT_DIR, exist_ok=True)
    sss = mkf.MKF(os.path.join(DATA_DIR, 'Sss.mkf'))
    sc = sss.raw(1)
    scene_map = {}
    for i in range(len(sc) // 8):
        scene_map[i + 1] = struct.unpack_from('<4H', sc, i * 8)[0]

    jobs = []
    if '--map' in argv:
        jobs = [('map%s' % a, int(a)) for a in argv[argv.index('--map') + 1:]]
    else:
        # 任务要求: scene 1 / scene 2 (Sss 表映射)
        for sid in (1, 2, 3, 4):
            jobs.append(('scene%d' % sid, scene_map[sid]))

    result = {}
    for name, mid in jobs:
        out = os.path.join(OUT_DIR, 'map_%s.png' % name)
        p, size = render_map(mid, out)
        result[name] = dict(map_id=mid, file=p, size=size)
        print(name, 'map', mid, '->', p, size, 'palette', PALETTE_INDEX)
    with open(os.path.join(OUT_DIR, 'map_render.json'), 'w', encoding='utf-8') as f:
        json.dump(dict(scene_to_map=scene_map, renders=result), f,
                  ensure_ascii=False, indent=1)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))

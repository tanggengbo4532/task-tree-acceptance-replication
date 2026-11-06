# -*- coding: utf-8 -*-
"""
validate_all.py -- 对全部数据文件做容器/解压/内容自洽校验, 输出 JSON+文本证据.
产出: _rea_runtime/out/assets/assets_validate.json
"""
import hashlib
import json
import os
import struct
import sys

import mkf

DATA_DIR = r'<LOCAL_PATH>'
OUT_DIR = r'<LOCAL_PATH>'

FILES = ['Sss.mkf', 'Map.mkf', 'Mgo.mkf', 'Fbp.mkf', 'Rng.mkf', 'Abc.mkf',
         'Ball.mkf', 'Fire.mkf', 'Gop.mkf', 'Pat.mkf', 'Sounds.mkf',
         'MUS.MKF', 'Data.mkf', 'M.msg', 'Word.dat', '0.rpg']


def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


def validate_mkf(path):
    m = mkf.MKF(path)
    n = m.nchunks
    comp = raw = empty = 0
    yj2_ok = 0
    dec_total = 0
    bad = []
    for i in range(n):
        r = m.raw(i)
        if not r:
            empty += 1
            continue
        dec = mkf.try_decompress(r)
        if dec is not None:
            comp += 1
            dec_total += len(dec)
            yj2_ok += 1
        else:
            raw += 1
    sizes = [m.size(i) for i in range(n)]
    return dict(nchunks=n, head_words=m.head_words,
                hdr_bytes=m.head_words, offsets0=m.offsets[0],
                last_offset=m.offsets[-1], file_size=len(m.data),
                offsets_ok=(m.offsets[0] == m.head_words == 4 * (n + 1) and
                            m.offsets[-1] == len(m.data)),
                sizes_sum=sum(sizes),
                sizes_sum_plus_hdr=sum(sizes) + m.head_words,
                empty=empty, yj2=comp, raw=raw,
                yj2_dec_total=dec_total,
                min_chunk=min(sizes), max_chunk=max(sizes),
                sizes_head=sizes[:8])


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    report = {'files': {}, 'checks': {}}
    for fn in FILES:
        p = os.path.join(DATA_DIR, fn)
        r = dict(size=os.path.getsize(p), sha256=sha256(p))
        if fn.lower().endswith('.mkf') or fn.upper() == 'MUS.MKF':
            try:
                r.update(validate_mkf(p))
            except Exception as e:
                r['mkf_error'] = repr(e)
        report['files'][fn] = r

    # --- 内容级校验 ---
    checks = report['checks']
    # SSS
    s = mkf.MKF(os.path.join(DATA_DIR, 'Sss.mkf'))
    ev, sc, ob, mo, se = (s.raw(0), s.raw(1), s.raw(2), s.raw(3), s.raw(4))
    checks['sss'] = dict(
        eventobject=dict(bytes=len(ev), count=len(ev) // 32, expect=5077 * 32,
                         ok=len(ev) == 5077 * 32),
        scene=dict(bytes=len(sc), count=len(sc) // 8, expect=295 * 8,
                   ok=len(sc) == 295 * 8),
        object=dict(bytes=len(ob), count=len(ob) // 14, ok=len(ob) == 565 * 14),
        msg_offset=dict(bytes=len(mo), count=len(mo) // 4, ok=len(mo) % 4 == 0),
        scriptentry=dict(bytes=len(se), count=len(se) // 8, ok=len(se) % 8 == 0),
    )
    offsets = struct.unpack('<%dI' % (len(mo) // 4), mo)
    mmsg = open(os.path.join(DATA_DIR, 'M.msg'), 'rb').read()
    checks['sss']['msg_offset'].update(
        first=offsets[0], last=offsets[-1], m_msg_size=len(mmsg),
        last_equals_m_msg=(offsets[-1] == len(mmsg)),
        monotonic=all(offsets[i] <= offsets[i + 1] for i in range(len(offsets) - 1)))
    checks['sss']['scenes'] = [dict(id=i + 1,
                                    **dict(zip(['map', 'on_enter', 'on_teleport',
                                                'evt_idx'],
                                               struct.unpack_from('<4H', sc, i * 8))))
                               for i in range(10)]

    # MAP: 所有块解压后必须恰为 65536
    mm = mkf.MKF(os.path.join(DATA_DIR, 'Map.mkf'))
    gm = mkf.MKF(os.path.join(DATA_DIR, 'Gop.mkf'))
    map_ok = 0
    map_bad = []
    map_idx_max = 0
    gop_frame_counts = set()
    gop_dims = set()
    for i in range(1, mm.nchunks):
        try:
            dec = mm.chunk(i)
        except Exception as e:
            map_bad.append((i, 'err', repr(e)))
            continue
        if len(dec) != 65536:
            map_bad.append((i, len(dec)))
            continue
        map_ok += 1
        dw = struct.unpack('<16384I', dec)
        mx = 0
        for d in dw:
            v = (d & 0xFF) | ((d >> 4) & 0x100)
            mx = max(mx, v)
            h = d >> 16
            v2 = ((h & 0xFF) | ((h >> 4) & 0x100)) - 1
            if v2 > mx:
                mx = v2
        map_idx_max = max(map_idx_max, mx)
        fr = mkf.sprite_frames(gm.raw(i))
        gop_frame_counts.add(len(fr))
        for f in fr[:4]:
            b = mkf.rle_bitmap(f)
            if b:
                gop_dims.add((b[0], b[1]))
    checks['map'] = dict(chunks=mm.nchunks, decompressed_ok=map_ok,
                         decompressed_size=65536, tile_index_max=map_idx_max,
                         gop_frame_counts=sorted(gop_frame_counts),
                         gop_dims=sorted(gop_dims), bad=map_bad)

    # MGO: 全部解压 + sprite 自洽 (帧偏移单调, RLE 可解)
    mg = mkf.MKF(os.path.join(DATA_DIR, 'Mgo.mkf'))
    frames_total = 0
    sprite_ok = 0
    sprite_bad = []
    for i in range(1, mg.nchunks):
        if not mg.raw(i):
            continue
        dec = mg.chunk(i)
        fr = mkf.sprite_frames(dec)
        if not fr:
            sprite_bad.append((i, len(dec)))
            continue
        ok = all(mkf.rle_bitmap(f) is not None for f in fr)
        if ok:
            sprite_ok += 1
            frames_total += len(fr)
        else:
            sprite_bad.append((i, 'rle'))
    checks['mgo'] = dict(chunks=mg.nchunks, sprites_ok=sprite_ok,
                         frames_total=frames_total, bad=sprite_bad)

    # PAT
    pm = mkf.MKF(os.path.join(DATA_DIR, 'Pat.mkf'))
    pat_sizes = [pm.size(i) for i in range(pm.nchunks)]
    mx = 0
    for i in range(pm.nchunks):
        mx = max(mx, max(pm.raw(i)))
    checks['pat'] = dict(chunks=pm.nchunks, sizes=pat_sizes,
                         max_component=mx,
                         six_bit=(mx <= 63),
                         palettes=[(i, 'day+night' if pm.size(i) == 1536 else 'day')
                                   for i in range(pm.nchunks)])
    # Word.dat
    wd = open(os.path.join(DATA_DIR, 'Word.dat'), 'rb').read()
    checks['word'] = dict(size=len(wd), word_len=10,
                          count=len(wd) // 10, ok=(len(wd) % 10 == 0))
    # 其它 MKF 首块头部样本 (判定 raw/压缩)
    misc = {}
    for fn, idx in [('Fbp.mkf', 0), ('Abc.mkf', 1), ('Fire.mkf', 0),
                    ('Ball.mkf', 1), ('Rng.mkf', 0), ('Sounds.mkf', 1),
                    ('MUS.MKF', 1), ('Gop.mkf', 1), ('Data.mkf', 0)]:
        d = mkf.MKF(os.path.join(DATA_DIR, fn))
        if idx < d.nchunks:
            misc[fn] = dict(chunk=idx, size=d.size(idx),
                            first8=d.raw(idx)[:8].hex(),
                            decoded_len=len(d.chunk(idx)))
    checks['misc'] = misc

    out = os.path.join(OUT_DIR, 'assets_validate.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print('wrote', out, os.path.getsize(out))
    for fn, r in report['files'].items():
        if 'nchunks' in r:
            print('%-11s size=%8d sha=%s n=%3d hdr=%4d empty=%3d yj2=%3d raw=%3d '
                  'offok=%s' % (fn, r['size'], r['sha256'][:16], r['nchunks'],
                                r['hdr_bytes'], r['empty'], r['yj2'], r['raw'],
                                r['offsets_ok']))
        else:
            print('%-11s size=%8d sha=%s' % (fn, r['size'], r['sha256'][:16]))
    print('SSS', checks['sss'])
    print('MAP', {k: v for k, v in checks['map'].items() if k != 'bad'})
    print('MGO', {k: v for k, v in checks['mgo'].items() if k != 'bad'})
    print('PAT', checks['pat'])
    return 0


if __name__ == '__main__':
    sys.exit(main())

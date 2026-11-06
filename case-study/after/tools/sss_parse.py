# -*- coding: utf-8 -*-
"""
sss_parse.py -- 解析 SSS.MKF 五个块并导出 JSON.

容器 (实际字节观察, 见 MKF-FORMAT.md):
  dword0 = 头部长度 = 4*(nchunks+1), nchunks=(dword0-4)//4
  Sss.mkf: dword0=0x18=24 -> nchunks=5, 块边界
    [24, 162488) 162464 = 5077*32   EVENTOBJECT
    [162488,164848)  2360 = 295*8   SCENE
    [164848,172758)  7910 = 565*14  OBJECT (WIN95: 7 WORD)
    [172758,226814) 54056 = 13514*4 消息偏移表 (DWORD)
    [226814,575270) 348456 = 43557*8 SCRIPTENTRY
"""
import json
import os
import struct
import sys

import mkf

DATA_DIR = r'<LOCAL_PATH>'
OUT_DIR = r'<LOCAL_PATH>'

EVENTOBJECT_FIELDS = [
    ('sVanishTime', 'i16', '帧/消失计时'),
    ('x', 'u16', '地图像素 X'),
    ('y', 'u16', '地图像素 Y'),
    ('sLayer', 'i16', '层级'),
    ('wTriggerScript', 'u16', '触发脚本入口 (SCRIPTENTRY 下标)'),
    ('wAutoScript', 'u16', '自动脚本入口'),
    ('sState', 'i16', '0隐藏/1普通/2阻挡'),
    ('wTriggerMode', 'u16', '触发方式 0..8'),
    ('wSpriteNum', 'u16', 'MGO 精灵块号 (0=玩家)'),
    ('nSpriteFrames', 'u16', '每方向帧数 (3=行走角色)'),
    ('wDirection', 'u16', '方向 0南/1西/2北/3东'),
    ('wCurrentFrameNum', 'u16', '当前帧'),
    ('nScriptIdleFrame', 'u16', '触发脚本 idle 帧计数'),
    ('wSpritePtrOffset', 'u16', '未知(运行期)'),
    ('nSpriteFramesAuto', 'u16', '自动脚本用总帧数'),
    ('wScriptIdleFrameCountAuto', 'u16', '自动脚本 idle 帧计数'),
]

SCENE_FIELDS = ['wMapNum', 'wScriptOnEnter', 'wScriptOnTeleport', 'wEventObjectIndex']
OBJECT_FIELDS = ['w0', 'w1', 'w2', 'w3', 'w4', 'w5', 'w6']


def parse_sss(sss_path):
    s = mkf.MKF(sss_path)
    ev = s.raw(0)
    sc = s.raw(1)
    ob = s.raw(2)
    mo = s.raw(3)
    se = s.raw(4)

    assert len(ev) == 32 * 5077, len(ev)
    assert len(sc) == 8 * 295, len(sc)
    assert len(ob) == 14 * 565, len(ob)
    assert len(mo) == 4 * 13514, len(mo)
    assert len(se) == 8 * 43557, len(se)

    event_objects = []
    for i in range(len(ev) // 32):
        w = struct.unpack_from('<16H', ev, i * 32)
        obj = {'id': i}
        for (name, _t, _d), v in zip(EVENTOBJECT_FIELDS, w):
            obj[name] = v
        event_objects.append(obj)

    scenes = []
    for i in range(len(sc) // 8):
        w = struct.unpack_from('<4H', sc, i * 8)
        scenes.append(dict(id=i + 1, **dict(zip(SCENE_FIELDS, w))))

    objects = []
    for i in range(len(ob) // 14):
        objects.append({'id': i, 'w': list(struct.unpack_from('<7H', ob, i * 14))})

    msg_offsets = list(struct.unpack('<%dI' % (len(mo) // 4), mo))
    script_entries = [list(struct.unpack_from('<4H', se, i * 8))
                      for i in range(len(se) // 8)]

    return dict(
        container=dict(nchunks=s.nchunks, head_words=s.head_words,
                       sizes=[s.size(i) for i in range(s.nchunks)],
                       offsets=s.offsets),
        counts=dict(event_objects=len(event_objects), scenes=len(scenes),
                    objects=len(objects), msg_offsets=len(msg_offsets),
                    script_entries=len(script_entries)),
        bytes=dict(event_objects=len(ev), scenes=len(sc), objects=len(ob),
                   msg_offsets=len(mo), script_entries=len(se)),
        struct_sizes=dict(EVENTOBJECT=32, SCENE=8, OBJECT=14, MSG_OFFSET=4,
                          SCRIPTENTRY=8),
        event_objects=event_objects,
        scenes=scenes,
        objects=objects,
        msg_offsets=msg_offsets,
        script_entries=script_entries,
    )


def main():
    sss = os.path.join(DATA_DIR, 'Sss.mkf')
    msg_path = os.path.join(DATA_DIR, 'M.msg')
    data = parse_sss(sss)
    msg_size = os.path.getsize(msg_path)
    data['m_msg_size'] = msg_size
    data['msg_offsets_last_equals_m_msg_size'] = (
        data['msg_offsets'][-1] == msg_size)
    data['n_messages'] = len(data['msg_offsets']) - 1

    # 场景 -> 地图 示例
    scene_map = {}
    for sc in data['scenes'][:10]:
        nm = sc['wEventObjectIndex']
        nextnm = (data['scenes'][sc['id']]['wEventObjectIndex']
                  if sc['id'] < len(data['scenes']) else len(data['event_objects']))
        scene_map[sc['id']] = dict(map=sc['wMapNum'],
                                   script_on_enter=sc['wScriptOnEnter'],
                                   evt_first=nm + 1,
                                   evt_count=max(0, nextnm - nm))
    data['scene_map_sample'] = scene_map

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, 'sss_tables.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    print('wrote', out, os.path.getsize(out), 'bytes')
    print('counts', data['counts'], 'n_messages', data['n_messages'])
    print('last msg offset', data['msg_offsets'][-1], 'M.msg size', msg_size)
    for k, v in scene_map.items():
        print('scene', k, '->', v)


if __name__ == '__main__':
    main()

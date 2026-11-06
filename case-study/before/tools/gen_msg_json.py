# -*- coding: utf-8 -*-
"""
gen_msg_json.py -- M.msg (GBK 文本) + SSS.MKF 块3 (13514 个 uint32 偏移) -> UTF-8 JSON.

结构 (实际字节观察):
  M.msg 224455 字节; SSS 块3 = 13514 个 uint32 偏移, offsets[0]=0,
  offsets[13513]=224455=M.msg 长度. 消息条数 = 13514-1 = 13513.
  第 i 条消息 = M.msg[offsets[i] : offsets[i+1]]  (GBK 双字节, 无 \0 结尾)

内嵌控制码 (sdlpal text.c PAL_DrawTextUnescape 交叉验证):
  '$' + 2 位十进制 : 设置文字显示延时 (wcstol(text+1)*10/7), 消耗 3 字节
  '~' + 数字       : 延时并暂停/结束本行, 消耗至多 3 字节
  '@' 切换红色, '"' 切换黄色, ')' / '(' 等待图标, '\\' 转义
Godot 侧应保留原文, 再按上述规则解释; 本 JSON 同时输出 text(原文) 与
plain(去掉控制码的纯文本), 以及 codes(控制码出现位置) 便于对照.
"""
import json
import os
import re
import struct
import sys

import mkf

DATA_DIR = r'<LOCAL_PATH>'
OUT_DIR = r'<LOCAL_PATH>'


def decode_msg(bs):
    # 98柔情版为简体中文 Windows 版 -> GBK(cp936).
    # 少数条目含 PUA 自定义符号 (GBK 严格模式报错), gb18030 是 GBK 的超集,
    # 可把它们解成 U+E0xx 私用区字符而不丢失文本.
    try:
        return bs.decode('gbk')
    except UnicodeDecodeError:
        return bs.decode('gb18030', errors='replace')


def strip_controls(s):
    out = []
    i = 0
    codes = []
    while i < len(s):
        c = s[i]
        if c == '$' and i + 2 < len(s) and s[i + 1:i + 3].isdigit():
            codes.append({'pos': i, 'code': '$', 'arg': s[i + 1:i + 3]})
            i += 3
            continue
        if c == '~' and i + 1 < len(s) and s[i + 1].isdigit():
            codes.append({'pos': i, 'code': '~', 'arg': s[i + 1]})
            i += 2
            continue
        if c in '@"()':
            codes.append({'pos': i, 'code': c, 'arg': ''})
            i += 1
            continue
        out.append(c)
        i += 1
    return ''.join(out), codes


def main():
    sss = mkf.MKF(os.path.join(DATA_DIR, 'Sss.mkf'))
    mo = sss.raw(3)
    offsets = struct.unpack('<%dI' % (len(mo) // 4), mo)
    raw = open(os.path.join(DATA_DIR, 'M.msg'), 'rb').read()
    assert offsets[-1] == len(raw), (offsets[-1], len(raw))

    msgs = []
    for i in range(len(offsets) - 1):
        a, b = offsets[i], offsets[i + 1]
        text = decode_msg(raw[a:b])
        plain, codes = strip_controls(text)
        msgs.append(dict(i=i, off=a, n=b - a, text=text,
                         plain=plain, codes=codes if codes else []))

    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, 'msg_zh.json')
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(dict(encoding='gbk', source='M.msg + Sss.mkf#3',
                       count=len(msgs), offsets_count=len(offsets),
                       messages=msgs), f, ensure_ascii=False,
                  separators=(',', ':'))
    print('wrote', out, os.path.getsize(out), 'bytes; messages', len(msgs))

    # 人眼校验样例
    with open(os.path.join(OUT_DIR, 'msg_sample.txt'), 'w', encoding='utf-8') as f:
        for m in msgs[:40]:
            f.write('%5d off=%6d len=%3d | %s\n' %
                    (m['i'], m['off'], m['n'], m['text']))
    for m in msgs[:12]:
        print('%5d off=%6d len=%3d | %s' % (m['i'], m['off'], m['n'], m['text']))
    # 控制码统计
    from collections import Counter
    c = Counter()
    for m in msgs:
        for x in m['codes']:
            c[x['code']] += 1
    print('control code counts', dict(c))
    print('messages with $', sum(1 for m in msgs if '$' in m['text']),
          'with ~', sum(1 for m in msgs if '~' in m['text']))


if __name__ == '__main__':
    main()

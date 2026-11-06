"""Extract PAL98 dialogue text from M.msg + Sss.mkf chunk 3 offset table.

Evidence: Sss.mkf chunk 3 is a DWORD offset table (54,056 bytes / 4 = 13,514
entries) into M.msg (GBK).  Text n spans [offsets[n], offsets[n+1]).

Output: UTF-8 JSON array of strings (Godot cannot decode GBK at runtime).
"""
import json
import struct
import sys

DATA_DIR = r"<LOCAL_PATH>"
OUT = sys.argv[1] if len(sys.argv) > 1 else "msg_zh.json"


def mkf_chunk(path, index):
    b = open(path, 'rb').read()
    data_start = struct.unpack_from('<I', b, 0)[0]
    count = (data_start - 4) >> 2
    assert 0 <= index < count, (index, count)
    off = struct.unpack_from('<I', b, 4 * index)[0]
    nxt = struct.unpack_from('<I', b, 4 * (index + 1))[0]
    return b[off:nxt]


def main():
    raw = open(DATA_DIR + r"\M.msg", 'rb').read()
    table = mkf_chunk(DATA_DIR + r"\Sss.mkf", 3)
    n = len(table) // 4
    offsets = list(struct.unpack('<%dI' % n, table[:n * 4]))
    offsets.append(len(raw))
    entries = []
    for i in range(n - 1):
        a, b = offsets[i], offsets[i + 1]
        if a <= b <= len(raw):
            s = raw[a:b].decode('gbk', errors='replace')
            s = s.replace('\r', '').replace('\n', ' ')
            entries.append(s)
        else:
            entries.append('')
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(entries, f, ensure_ascii=False, indent=0)
    print("entries:", len(entries), "first5:", entries[:5], "max_off:", max(offsets[:-1]))


if __name__ == '__main__':
    main()

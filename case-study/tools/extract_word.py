"""Extract Word.dat (565 entries x 10 bytes GBK) to UTF-8 JSON.

Word.dat: fixed 10-byte GBK strings, NUL padded.  Output: data/word_zh.json
"""
import json
import sys

DATA_DIR = r"<LOCAL_PATH>"
OUT = sys.argv[1] if len(sys.argv) > 1 else "word_zh.json"


def main():
    raw = open(DATA_DIR + r"\Word.dat", "rb").read()
    n = len(raw) // 10
    out = []
    for i in range(n):
        chunk = raw[i * 10:i * 10 + 10]
        z = chunk.find(b"\x00")
        if z < 0:
            z = len(chunk)
        try:
            s = chunk[:z].decode("gbk", errors="replace")
        except Exception:
            s = ""
        out.append(s)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=0)
    print("words:", len(out), "sample:", out[:8], out[100:104])


if __name__ == "__main__":
    main()

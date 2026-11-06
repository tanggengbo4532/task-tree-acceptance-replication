"""把《仙剑98柔情版》Musics/NNN.mid 离线渲染成 WAV，供 Godot 侧 PALAudio.play_music() 播放。

背景（证据见 docs/rea/evidence/assets/MISC-FORMAT.md）：
  * MUS.MKF 是 0x55AA 头的私有格式，[unk] 未解码，Godot 无 MIDI 合成器；
  * 但游戏目录 `Musics/001.mid .. 087.mid`（缺 029）与脚本 0x0043 音乐号一一对应：
    脚本操作数实测 0..87，MUS.MKF 非空块号也恰为 1..87 缺 29；
  * 因此本工具把 MIDI 用简易加法合成器渲染成 16bit PCM WAV，
    PALAudio 约定从 `res://data/bgm/NNN.wav` 读取。

用法：
  python tools/audio_midi_render.py --list              # 列出全部曲目时长
  python tools/audio_midi_render.py 1 26                # 渲染指定音乐号
  python tools/audio_midi_render.py --all               # 全部渲染（约 200MB+，默认不建议）
  python tools/audio_midi_render.py 26 --sr 22050 --out data/bgm

注意：这是**离线近似合成**（正弦/锯齿/三角 + ADSR），不是原版 OPL/RIX 音源，
音色与音量平衡与原版不同，仅用于让移植版有真实可听的 BGM；在文档中标注为偏差。
"""
import argparse
import math
import os
import struct
import sys
import wave

try:
    import numpy as np
except ImportError:
    print("需要 numpy（Godot 工程 Python 运行时自带）：%s" % sys.executable)
    raise

DATA_CANDIDATES = [
    r"<LOCAL_PATH>",
    r"<LOCAL_PATH>",
]
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(PROJECT_ROOT, "data", "bgm")

# 简易音色：按 GM program 分组
PROGRAM_WAVE = [
    "sine", "sine", "sine", "sine", "sine", "sine", "sine", "sine",      # 0-7 钢琴
    "sine", "sine", "sine", "sine", "sine", "sine", "sine", "sine",      # 8-15 色彩打击
    "tri", "tri", "tri", "tri", "tri", "tri", "tri", "tri",              # 16-23 风琴
    "saw", "saw", "saw", "saw", "saw", "saw", "saw", "saw",              # 24-31 吉他
    "sine", "sine", "sine", "sine", "sine", "sine", "sine", "sine",      # 32-39 贝斯
    "saw", "saw", "saw", "saw", "saw", "saw", "saw", "saw",              # 40-47 弦乐
    "tri", "tri", "tri", "tri", "tri", "tri", "tri", "tri",              # 48-55 合奏
    "saw", "saw", "saw", "saw", "saw", "saw", "saw", "saw",              # 56-63 铜管
    "tri", "tri", "tri", "tri", "tri", "tri", "tri", "tri",              # 64-71 簧管
    "sine", "sine", "sine", "sine", "sine", "sine", "sine", "sine",      # 72-79 管乐
    "saw", "saw", "saw", "saw", "saw", "saw", "saw", "saw",              # 80-87 合成主音
]


def find_data_dir(explicit=None):
    if explicit:
        return explicit
    for d in DATA_CANDIDATES:
        if os.path.isfile(os.path.join(d, "Sss.mkf")):
            return d
    return ""


def read_vlq(buf, pos):
    value = 0
    while True:
        b = buf[pos]
        pos += 1
        value = (value << 7) | (b & 0x7F)
        if not (b & 0x80):
            return value, pos


def parse_midi(path):
    """解析 SMF，返回 (division, events)；events = [(tick, kind, ch, a, b)]。
    kind: 'on' / 'off' / 'tempo' / 'program' / 'volume' / 'control'
    绝对 tick 已合并（format 1 多轨）。
    """
    data = open(path, "rb").read()
    if data[:4] != b"MThd":
        raise ValueError("not MIDI: %s" % path)
    hlen = struct.unpack(">I", data[4:8])[0]
    fmt, ntrks, division = struct.unpack(">HHH", data[8:14])
    pos = 8 + hlen
    events = []
    for _ in range(ntrks):
        while pos + 8 <= len(data) and data[pos:pos + 4] != b"MTrk":
            pos += 1
        if pos + 8 > len(data):
            break
        tlen = struct.unpack(">I", data[pos + 4:pos + 8])[0]
        tstart = pos + 8
        tend = tstart + tlen
        p = tstart
        tick = 0
        running = 0
        while p < tend:
            delta, p = read_vlq(data, p)
            tick += delta
            if p >= tend:
                break
            status = data[p]
            if status < 0x80:
                status = running  # running status
            else:
                p += 1
                if status < 0xF0:
                    running = status
            if status == 0xFF:
                mtype = data[p]
                p += 1
                mlen, p = read_vlq(data, p)
                payload = data[p:p + mlen]
                p += mlen
                if mtype == 0x51 and mlen >= 3:
                    tempo = (payload[0] << 16) | (payload[1] << 8) | payload[2]
                    events.append((tick, "tempo", 0, tempo, 0))
                elif mtype == 0x2F:
                    pass
                continue
            if status in (0xF0, 0xF7):
                slen, p = read_vlq(data, p)
                p += slen
                continue
            kind = status & 0xF0
            ch = status & 0x0F
            if kind in (0x80, 0x90):
                note = data[p]
                vel = data[p + 1]
                p += 2
                if kind == 0x90 and vel > 0:
                    events.append((tick, "on", ch, note, vel))
                else:
                    events.append((tick, "off", ch, note, 0))
            elif kind == 0xC0:
                prog = data[p]
                p += 1
                events.append((tick, "program", ch, prog, 0))
            elif kind in (0xB0,):
                cc = data[p]
                val = data[p + 1]
                p += 2
                if cc == 7:
                    events.append((tick, "volume", ch, val, 0))
                elif cc in (10, 11, 64, 91, 93, 121, 123):
                    events.append((tick, "control", ch, cc, val))
            elif kind in (0xA0, 0xE0):
                p += 2
            elif kind == 0xD0:
                p += 1
            else:
                p += 2
        pos = tend
    events.sort(key=lambda e: e[0])
    return division, events


class TempoMap:
    def __init__(self, division, events):
        self.division = max(1, division)
        self.changes = [(0, 500000)]
        for tick, kind, _ch, a, _b in events:
            if kind == "tempo":
                self.changes.append((tick, a))
        self.changes.sort()
        self._cache = {}

    def tick_to_seconds(self, tick):
        secs = 0.0
        last_tick, last_tempo = 0, 500000
        for t, tempo in self.changes:
            if t >= tick:
                break
            secs += (t - last_tick) / self.division * (last_tempo / 1e6)
            last_tick, last_tempo = t, tempo
        secs += (tick - last_tick) / self.division * (last_tempo / 1e6)
        return secs


def build_notes(events, temapo):
    """事件流 → 音符列表 [(start_s, dur_s, ch, note, vel, program)]，并统计通道音量。"""
    notes = []
    active = {}
    programs = {}
    volumes = {}
    for tick, kind, ch, a, b in events:
        if kind == "program":
            programs[ch] = a
        elif kind == "volume":
            volumes[ch] = a
        elif kind == "on":
            active[(ch, a)] = (tick, b)
        elif kind == "off":
            key = (ch, a)
            if key in active:
                start_tick, vel = active.pop(key)
                t0 = temapo.tick_to_seconds(start_tick)
                t1 = temapo.tick_to_seconds(tick)
                if t1 > t0:
                    notes.append((t0, t1 - t0, ch, a, vel, programs.get(ch, 0)))
    # 未关闭的音符按最后事件时间收尾
    end_tick = max([e[0] for e in events], default=0)
    for (ch, note), (start_tick, vel) in active.items():
        t0 = temapo.tick_to_seconds(start_tick)
        t1 = temapo.tick_to_seconds(end_tick)
        if t1 > t0:
            notes.append((t0, t1 - t0, ch, note, vel, programs.get(ch, 0)))
    return notes, volumes


def synth(notes, volumes, sr, max_seconds=None):
    if not notes:
        return np.zeros(1, dtype=np.float32)
    end = max(t0 + d for t0, d, *_ in notes) + 1.5
    if max_seconds:
        end = min(end, max_seconds)
    n = int(end * sr) + 1
    out = np.zeros(n, dtype=np.float32)
    for t0, dur, ch, note, vel, prog in notes:
        if ch == 9:
            # GM 打击乐通道：本简易合成器不做噪声鼓，跳过（不影响旋律）
            continue
        start = int(t0 * sr)
        if start >= n:
            continue
        ndur = int(min(dur + 0.6, end - t0) * sr)
        if ndur <= 2:
            continue
        t = np.arange(ndur, dtype=np.float32) / sr
        freq = 440.0 * (2.0 ** ((note - 69) / 12.0))
        wave_kind = PROGRAM_WAVE[min(prog, 127) % len(PROGRAM_WAVE)]
        ph = 2.0 * math.pi * freq * t
        if wave_kind == "sine":
            wv = np.sin(ph) + 0.28 * np.sin(2 * ph) + 0.14 * np.sin(3 * ph)
        elif wave_kind == "tri":
            wv = 2.0 / math.pi * np.arcsin(np.sin(ph))
        else:  # saw
            wv = 2.0 * ((freq * t) % 1.0) - 1.0
            wv = 0.7 * wv + 0.3 * np.sin(ph)
        # ADSR（简化）：5ms attack / 60ms decay 到 0.8 / 音符结束后 80ms release
        attack = max(1, int(0.005 * sr))
        env = np.full(ndur, 0.62, dtype=np.float32)
        env[:attack] = np.linspace(0.0, 1.0, attack, dtype=np.float32)
        dec = min(ndur, max(1, int(0.06 * sr)))
        if dec > attack:
            env[attack:dec] = np.linspace(1.0, 0.8, dec - attack, dtype=np.float32)
        hold = max(0, int(dur * sr))
        if hold < ndur:
            env[hold:] *= np.linspace(1.0, 0.0, ndur - hold, dtype=np.float32)
        gain = (vel / 127.0) * (volumes.get(ch, 100) / 127.0) * 0.16
        seg = wv * env * gain
        out[start:start + ndur] += seg.astype(np.float32)
    # 归一化 + 软限幅
    peak = float(np.max(np.abs(out))) if out.size else 0.0
    if peak > 0.85:
        out *= (0.85 / peak)
    return out


def write_wav(path, samples, sr):
    pcm = np.clip(samples * 32767.0, -32768, 32767).astype(np.int16)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(pcm.tobytes())
    return len(pcm) / float(sr), os.path.getsize(path)


def render_one(data_dir, num, sr, out_dir, max_seconds=None):
    mid = os.path.join(data_dir, "Musics", "%03d.mid" % num)
    if not os.path.isfile(mid):
        print("  [skip] %03d.mid 不存在" % num)
        return None
    division, events = parse_midi(mid)
    temapo = TempoMap(division, events)
    notes, volumes = build_notes(events, temapo)
    samples = synth(notes, volumes, sr, max_seconds)
    out = os.path.join(out_dir, "%03d.wav" % num)
    dur, size = write_wav(out, samples, sr)
    print("  %03d.mid → %s  音符=%d 时长=%.1fs 大小=%.2fMB  (division=%d)" % (
        num, out, len(notes), dur, size / 1048576.0, division))
    return {"num": num, "path": out, "duration": dur, "size": size, "notes": len(notes)}


def main():
    ap = argparse.ArgumentParser(description="PAL98 MIDI → WAV 离线渲染（简易合成器）")
    ap.add_argument("nums", nargs="*", type=int, help="要渲染的音乐号（对应 Musics/NNN.mid）")
    ap.add_argument("--all", action="store_true", help="渲染全部曲目（体积大，慎用）")
    ap.add_argument("--list", action="store_true", help="仅列出曲目时长")
    ap.add_argument("--data", default="", help="游戏数据目录")
    ap.add_argument("--out", default=DEFAULT_OUT, help="输出目录（默认 data/bgm）")
    ap.add_argument("--sr", type=int, default=22050, help="采样率（默认 22050，与 Sounds.mkf 一致）")
    ap.add_argument("--max-seconds", type=float, default=0, help="截断长度（0=不截断）")
    args = ap.parse_args()

    data_dir = find_data_dir(args.data)
    if not data_dir:
        print("未找到游戏数据目录，请用 --data 指定")
        return 1
    music_dir = os.path.join(data_dir, "Musics")
    nums = sorted(int(f[:3]) for f in os.listdir(music_dir) if f.endswith(".mid"))
    if args.list:
        total = 0.0
        print("数据目录: %s" % data_dir)
        print("共 %d 首 MIDI（缺 %s）" % (len(nums), [x for x in range(1, max(nums) + 1) if x not in nums]))
        for num in nums:
            division, events = parse_midi(os.path.join(music_dir, "%03d.mid" % num))
            temapo = TempoMap(division, events)
            notes, _ = build_notes(events, temapo)
            dur = max([t0 + d for t0, d, *_ in notes] + [0])
            total += dur
            print("  %03d: 音符=%5d 时长=%6.1fs" % (num, len(notes), dur))
        print("合计 %.1f 分钟；全部渲染约 %.0f MB（22050Hz 16bit 单声道）" % (total / 60.0, total * 22050 * 2 / 1048576))
        return 0

    if args.all:
        targets = nums
    elif args.nums:
        targets = args.nums
    else:
        print("请指定音乐号，或 --all / --list。例如: python tools/audio_midi_render.py 26")
        return 1

    max_seconds = args.max_seconds if args.max_seconds > 0 else None
    results = []
    for num in targets:
        r = render_one(data_dir, num, args.sr, args.out, max_seconds)
        if r:
            results.append(r)
    if results:
        total = sum(r["size"] for r in results)
        print("完成 %d 首，共 %.2f MB → %s" % (len(results), total / 1048576.0, args.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())

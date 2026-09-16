#!/usr/bin/env python3
"""analyze_thread_saturation.py —— 汇总「线程数饱和点」实测（方案 §3.3 / §3.4 / §4.5）

用法：python3 analyze_thread_saturation.py [结果目录]   默认 ~/bench-results
读取 run_thread_saturation.sh 产出的 *.log 与 *.samples，输出：
  · 每配置 fps 的 均值 ± 标准差 / min / max（5 轮）
  · 每配置窗口内 NPU 逐核占用率（判定是否饱和的决定性证据）
  · 温度、各域频率（排除降频）、宿主 CPU 占用（排除宿主瓶颈误判）
  · 校验和一致性（正确性回归，方案 §六.C）
  · 按方案 §3.5 的规则给出自动判读
"""
import os, re, sys, glob, statistics as st
from collections import defaultdict

RESDIR      = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/bench-results")
SKIP_EXTRA  = 2.0          # 采样器比 bench 早启 1s；再留 1s 余量，确保窗口落在计时段内
LABEL       = {3: "A 1线程/核", 6: "B 2线程/核", 9: "C 3线程/核", 12: "D 4线程/核", 8: "E 复刻上游(2.67/核)"}

def parse_log(path):
    r = {}
    for line in open(path, errors="ignore"):
        if line.startswith("RESULT"):
            for kv in line.split()[1:]:
                if "=" in kv:
                    k, v = kv.split("=", 1); r[k] = v
        elif line.startswith("CHECKSUM"):
            r["checksum"] = line.strip()
    return r

def parse_samples(path, skip_s, duration):
    """解析采样文件，返回计时窗口内的样本"""
    rows = []
    for line in open(path, errors="ignore"):
        p = line.rstrip("\n").split("|")
        if len(p) < 6: continue
        try: ts = float(p[0])
        except ValueError: continue
        load = [int(v) for _, v in sorted(re.findall(r"Core(\d):\s*(\d+)%", p[1]))]
        temp = int(p[2]) / 1000.0 if p[2].strip().isdigit() else None
        cpu  = [int(x) for x in p[5].split()[1:]] if p[5].startswith("cpu ") else None
        rows.append({"ts": ts, "load": load, "temp": temp, "cpu": cpu})
    if len(rows) < 3: return []
    t_start = rows[0]["ts"] + skip_s
    win = [r for r in rows if r["ts"] >= t_start]
    return win if len(win) >= 3 else rows

def cpu_busy(win):
    """由相邻 /proc/stat 样本算宿主 CPU 繁忙率（排除 idle+iowait）"""
    out = []
    for a, b in zip(win, win[1:]):
        if not a["cpu"] or not b["cpu"]: continue
        d = [y - x for x, y in zip(a["cpu"], b["cpu"])]
        tot = sum(d)
        if tot <= 0: continue
        idle = d[3] + (d[4] if len(d) > 4 else 0)
        out.append(100.0 * (tot - idle) / tot)
    return out

def mean(xs): return st.mean(xs) if xs else float("nan")
def sd(xs):   return st.pstdev(xs) if len(xs) > 1 else 0.0

if not os.path.isdir(RESDIR):
    sys.exit("找不到结果目录：%s" % RESDIR)

logs = sorted(glob.glob(os.path.join(RESDIR, "r*-n*.log")))
if not logs:
    sys.exit("目录里没有 r*-n*.log：%s" % RESDIR)

by_threads = defaultdict(list)
all_checksums = set()

for lg in logs:
    m = re.search(r"-n(\d+)\.log$", lg)
    if not m: continue
    n = int(m.group(1))
    d = parse_log(lg)
    if "fps" not in d: continue
    fps = float(d["fps"]); frames = int(d["frames"]); el = float(d["elapsed"])
    warmup = int(d.get("warmup", 5))
    all_checksums.add(d.get("checksum", "?"))

    smp = lg[:-4] + ".samples"
    load = [float("nan")] * 3; temp = float("nan"); cb = float("nan")
    if os.path.exists(smp):
        win = parse_samples(smp, 1.0 + warmup + SKIP_EXTRA, el)
        if win:
            ncore = min(len(w["load"]) for w in win)
            load = [mean([w["load"][i] for w in win if len(w["load"]) > i]) for i in range(ncore)]
            temp = mean([w["temp"] for w in win if w["temp"] is not None])
            cb   = mean(cpu_busy(win))
    by_threads[n].append({"fps": fps, "frames": frames, "load": load, "temp": temp, "cpu": cb})

print("=" * 92)
print(" 线程数饱和点实测汇总   " + RESDIR)
print("=" * 92)
print("%-22s %-7s %-24s %-22s %-9s %-8s" % ("配置", "轮数", "fps 均值 ± 标准差", "NPU 逐核占用", "温度℃", "宿主CPU"))
print("-" * 92)

summary = {}
for n in sorted(by_threads, key=lambda x: (x != 3, x)):
    runs = by_threads[n]
    fps  = [r["fps"] for r in runs]
    load = [mean([r["load"][i] for r in runs if len(r["load"]) > i]) for i in range(3)]
    temp = mean([r["temp"] for r in runs if r["temp"] == r["temp"]])
    cpu  = mean([r["cpu"] for r in runs if r["cpu"] == r["cpu"]])
    summary[n] = {"fps": mean(fps), "sd": sd(fps), "min": min(fps), "max": max(fps),
                  "load": load, "temp": temp, "cpu": cpu, "n": len(fps)}
    print("%-22s %-7d %-24s %-22s %-9.1f %-8.1f" % (
        "%d 线程  %s" % (n, LABEL.get(n, "")), len(fps),
        "%.1f ± %.1f" % (mean(fps), sd(fps)),
        " ".join("%.0f%%" % v for v in load), temp, cpu))

print("-" * 92)
for n in sorted(summary):
    s = summary[n]
    print("  n=%-3d min=%.1f  max=%.1f  极差=%.1f" % (n, s["min"], s["max"], s["max"] - s["min"]))

print("\n === 校验和一致性（正确性回归，方案 §六.C）===")
if len(all_checksums) == 1:
    print("  ✅ 全部 %d 组输出校验和完全一致" % len(logs))
else:
    print("  ❌ 出现 %d 种不同校验和：" % len(all_checksums))
    for c in all_checksums: print("     " + c[:110])

print("\n === 自动判读（方案 §3.5 事先定好的规则）===")
if 3 in summary and 8 in summary:
    a, e = summary[3], summary[8]
    gain = 100.0 * (e["fps"] - a["fps"]) / a["fps"]
    pool_sd = sd([r["fps"] for r in by_threads[3] + by_threads[8]])
    sat = mean(a["load"]); 
    print("  1线程/核 %.1f fps  →  8线程 %.1f fps   增益 %.1f%%" % (a["fps"], e["fps"], gain))
    print("  1线程/核 NPU 逐核占用：%s" % " ".join("%.0f%%" % v for v in a["load"]))
    print("  合并标准差 %.2f fps（增益为 %.2f 倍标准差）" % (pool_sd, (e["fps"] - a["fps"]) / pool_sd if pool_sd else 0))
    if gain < 5 and sat > 90:
        print("  → ✅ 判读：fps 不涨 且 NPU 占用高 → **NPU 已饱和**，线程数不是性能杠杆")
    elif gain < 5 and sat <= 90:
        print("  → ❌ 判读：fps 不涨 但 NPU 占用不高 → 宿主瓶颈，命题不成立")
    elif gain >= 5:
        print("  → ⚠️ 判读：fps 随线程数上升 → 还没喂饱，需要更多线程（命题方向相反）")
print()

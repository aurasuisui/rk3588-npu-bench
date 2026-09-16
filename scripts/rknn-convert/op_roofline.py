#!/usr/bin/env python3
"""op_roofline.py — 算子级 roofline 分析：找出哪些层是算力受限、哪些是带宽受限
用法：python op_roofline.py model.onnx [实测fps] [实测带宽GB/s]
"""
import sys, collections
import onnx
from onnx import shape_inference

path = sys.argv[1]
FPS  = float(sys.argv[2]) if len(sys.argv) > 2 else 177.6
BW   = float(sys.argv[3]) if len(sys.argv) > 3 else 10.8   # 实测 DDR 有效带宽 GB/s
PEAK = 6000.0   # RK3588 NPU INT8 GOPS

m = onnx.load(path)
m = shape_inference.infer_shapes(m)

shape = {}
def rec(vis):
    for vi in vis:
        d = [x.dim_value if x.HasField("dim_value") else 0 for x in vi.type.tensor_type.shape.dim]
        if d: shape[vi.name] = d
rec(m.graph.input); rec(m.graph.output); rec(m.graph.value_info)
# ⚠️ 权重/常量是 initializer，不进 value_info，必须单独登记，否则查不到 Conv 的 weight 形状
for ini in m.graph.initializer:
    if list(ini.dims): shape[ini.name] = list(ini.dims)

inits = {i.name: i for i in m.graph.initializer}
def nbytes(name):
    t = inits.get(name)
    if t is None: return 0
    import numpy as np
    from onnx import numpy_helper
    return int(numpy_helper.to_array(t).nbytes) if t.data_type != 0 else 0

def numel(name):
    d = shape.get(name)
    if not d or 0 in d: return 0
    n = 1
    for x in d: n *= x
    return n

rows = []
tot_flops = 0
for n in m.graph.node:
    if n.op_type not in ("Conv", "ConvTranspose", "Gemm", "MatMul"): continue
    if not n.input: continue
    xs, ws = n.input[0], n.input[1]
    xd, wd = shape.get(xs), shape.get(ws)
    od = shape.get(n.output[0])
    if not xd or not wd or not od or 0 in od: continue
    N, Cin, H, W = xd[0], xd[1], xd[2], xd[3]
    Cout, Cg, K1, K2 = wd[0], wd[1], wd[2], wd[3]
    Oh, Ow = od[2], od[3]
    g = 1
    for a in n.attribute:
        if a.name == "group": g = a.i
    flops = 2.0 * Cout * Cg * K1 * K2 * Oh * Ow
    # DRAM 流量：读输入 + 读权重 + 写输出（按 INT8 1 字节/元素）
    b_in  = Cin * H * W
    b_w   = nbytes(ws)
    b_out = Cout * Oh * Ow
    tot = b_in + b_w + b_out
    ai = flops / tot if tot else 0
    tot_flops += flops
    rows.append((n.name, g, Cin, Cout, K1, Oh, Ow, flops, b_w, b_in + b_out, ai))

print("=" * 100)
print("算子级 roofline 分析  (NPU 峰值 %.0f GOPS INT8 / 实测 DDR %.1f GB/s → 机器平衡点 %.0f ops/byte)" % (PEAK, BW, PEAK / BW))
print("=" * 100)
print("总计算量      : %.2f GFLOPs/帧" % (tot_flops / 1e9))
print("理论峰值帧率  : %.1f fps  (6 TOPS ÷ 计算量)" % (PEAK * 1e9 / tot_flops))
print("实测帧率      : %.1f fps  → 达到理论峰值的 %.1f%%" % (FPS, 100 * FPS / (PEAK * 1e9 / tot_flops)))
print()

tot_bytes = sum(r[8] + r[9] for r in rows)
print("每帧 DRAM 流量（只算 Conv 层，读入+权重+写出）: %.1f MB" % (tot_bytes / 1e6))
print("实测帧率下的隐含带宽 : %.2f GB/s  → 占实测带宽上限 %.1f GB/s 的 %.0f%%"
      % (tot_bytes * FPS / 1e9, BW, 100 * tot_bytes * FPS / 1e9 / BW))
print()

rows.sort(key=lambda r: -r[7])
print("--- 计算量 TOP 10（算力大户）---")
print("%-26s %-5s %-14s %-10s %-9s %s" % ("层名(截断)", "group", "Cin→Cout", "K", "GFLOPs", "占比"))
for r in rows[:10]:
    print("%-26s %-5d %-14s %-10s %-9.3f %.1f%%"
          % (r[0][:26], r[1], "%d→%d" % (r[2], r[3]), "%dx%d" % (r[4], r[5] and r[4]), r[7] / 1e9, 100 * r[7] / tot_flops))

print()
print("--- 算术强度最差 TOP 12（带宽受限，NPU 会饿死）---")
print("%-26s %-5s %-14s %-9s %-10s %s" % ("层名(截断)", "group", "Cin→Cout", "K", "ops/byte", "有效上限fps"))
bwbound = [r for r in rows if r[10] < PEAK / BW]
for r in sorted(rows, key=lambda r: r[10])[:12]:
    eff = min(PEAK * 1e9 / r[7], r[10] * BW * 1e9 / r[7]) if r[7] else 0
    print("%-26s %-5d %-14s %-9s %-10.1f %.1f"
          % (r[0][:26], r[1], "%d→%d" % (r[2], r[3]), "%dx%d" % (r[4], r[4]), r[10], eff))
print()
print("带宽受限层数 : %d / %d（算术强度 < %.0f ops/byte）" % (len(bwbound), len(rows), PEAK / BW))
print("这些层合计占总计算量 : %.1f%%" % (100 * sum(r[7] for r in bwbound) / tot_flops if tot_flops else 0))
depthwise = [r for r in rows if r[1] > 1 and r[1] == r[2]]
print("含 depthwise(group==Cin) 层数 : %d，合计占计算量 %.1f%%"
      % (len(depthwise), 100 * sum(r[7] for r in depthwise) / tot_flops if tot_flops else 0))

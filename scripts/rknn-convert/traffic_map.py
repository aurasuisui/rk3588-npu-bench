import onnx
from onnx import shape_inference, numpy_helper
p = "/mnt/c/Users/aurasui/Desktop/Anything/ZYSJ-2288A/Transmission/rknn-toolkit2/yolov5s_relu.onnx"
m = shape_inference.infer_shapes(onnx.load(p))
shape = {}
for vi in list(m.graph.input)+list(m.graph.output)+list(m.graph.value_info):
    d = [x.dim_value if x.HasField("dim_value") else 0 for x in vi.type.tensor_type.shape.dim]
    if d: shape[vi.name] = d
for i in m.graph.initializer:
    if list(i.dims): shape[i.name] = list(i.dims)
inits = {i.name: i for i in m.graph.initializer}
def nbytes(nm):
    t = inits.get(nm)
    return int(numpy_helper.to_array(t).nbytes) if t is not None else 0
def vol(nm):
    d = shape.get(nm)
    if not d or 0 in d: return 0
    n = 1
    for x in d: n *= x
    return n

consumed = {}   # 张量被读取的总字节
produced = {}   # 张量被写出的字节
for n in m.graph.node:
    for o in n.output:
        v = vol(o)
        if v: produced[o] = v
    for i in n.input:
        v = vol(i)
        if v and i not in inits: consumed[i] = consumed.get(i, 0) + v

# 每帧 DRAM 流量模型：每个张量 写出一次 + 被读一次
wt = sum(nbytes(i.name) for i in m.graph.initializer)
w_read = wt                      # 权重每帧读一遍
graph_in  = vol("images")
graph_out = sum(vol(o.name) for o in m.graph.output)

# 张量级流量（不含 graph 输入输出）
inter = {}
for name in produced:
    if name in ("images",) or name in [o.name for o in m.graph.output]:
        continue
    inter[name] = produced[name] + consumed.get(name, 0)

tot_inter = sum(inter.values())
tot = tot_inter + w_read + graph_in + graph_out

print("=" * 78)
print("每帧 DRAM 流量拆解")
print("=" * 78)
print("  模型权重(每帧读一遍)      : %8.2f MB  (%.1f%%)" % (w_read/1e6, 100*w_read/tot))
print("  网络输入 images           : %8.2f MB  (%.1f%%)" % (graph_in/1e6, 100*graph_in/tot))
print("  网络输出 3 个检测头        : %8.2f MB  (%.1f%%)" % (graph_out/1e6, 100*graph_out/tot))
print("  中间特征图(层间往返)      : %8.2f MB  (%.1f%%)  <-- 大头" % (tot_inter/1e6, 100*tot_inter/tot))
print("  " + "-"*54)
print("  合计                      : %8.2f MB" % (tot/1e6))
print()
print("  不可省的下限(输入+输出+权重): %8.2f MB" % ((graph_in+graph_out+w_read)/1e6))
print("  → 理想算子融合理论上限     : %.1f 倍流量削减" % (tot/(graph_in+graph_out+w_read)))
print()
print("--- 中间张量流量 TOP 15（融合/削减的首要目标）---")
print("%-40s %-18s %10s" % ("张量名", "形状", "MB"))
for nm, b in sorted(inter.items(), key=lambda kv: -kv[1])[:15]:
    d = shape.get(nm, [])
    print("%-40s %-18s %10.2f" % (nm[:40], "x".join(str(x) for x in d[:4]), b/1e6))

# 按阶段聚合
import collections
agg = collections.Counter(); cnt = collections.Counter()
for nm, b in inter.items():
    stage = nm.split("/")[1] if "/" in nm else "?"
    agg[stage] += b; cnt[stage] += 1
print()
print("--- 按网络阶段聚合（model.N）---")
for s, b in agg.most_common(14):
    print("  %-12s %3d 个张量   %8.2f MB  (%.1f%%)" % (s, cnt[s], b/1e6, 100*b/tot))

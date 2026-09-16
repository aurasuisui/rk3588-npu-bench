import onnx, collections
from onnx import shape_inference, numpy_helper
p = "/mnt/c/Users/aurasui/Desktop/Anything/ZYSJ-2288A/Transmission/rknn-toolkit2/yolov5s_relu.onnx"
m = shape_inference.infer_shapes(onnx.load(p))
shape = {}
for vi in list(m.graph.input)+list(m.graph.output)+list(m.graph.value_info):
    d = [x.dim_value if x.HasField("dim_value") else 0 for x in vi.type.tensor_type.shape.dim]
    if d: shape[vi.name] = d
inits = {i.name: i for i in m.graph.initializer}
def vol(nm):
    d = shape.get(nm)
    if not d or 0 in d: return 0
    n = 1
    for x in d: n *= x
    return n
def wbytes(nm):
    t = inits.get(nm)
    return int(numpy_helper.to_array(t).nbytes) if t is not None else 0

out_bytes = collections.Counter()
out_cnt   = collections.Counter()
w_bytes   = collections.Counter()
for n in m.graph.node:
    for o in n.output:
        v = vol(o)
        if v: out_bytes[n.op_type] += v; out_cnt[n.op_type] += 1
    for i in n.input:
        if i in inits: w_bytes[n.op_type] += wbytes(i)

TOT_W_FP32 = sum(w_bytes.values())
SCALE = 7303040.0 / TOT_W_FP32      # 权重从 FP32 量化到 INT8 的比例（实测 RKNN 报 7303040 字节）
NODES = sum(out_cnt.values())
tot_out = sum(out_bytes.values())

print("=" * 84)
print("按算子类型的「写出流量」归因（激活值，INT8 1 字节/元素）")
print("=" * 84)
print("%-14s %6s %14s %8s   %s" % ("算子", "个数", "写出流量MB", "占比", "每次平均MB"))
for op, b in out_bytes.most_common():
    print("%-14s %6d %14.2f %7.1f%%   %8.3f" % (op, out_cnt[op], b/1e6, 100*b/tot_out, b/out_cnt[op]/1e6))

# 读+写：每个激活张量被下游读一次
read_bytes = collections.Counter()
for n in m.graph.node:
    for i in n.input:
        if i not in inits:
            v = vol(i)
            if v:
                owner = None
                for nn in m.graph.node:
                    if i in nn.output: owner = nn.op_type; break
                read_bytes[owner or "graph_input"] += v

print()
print("=" * 84)
print("零计算量算子的纯搬运代价（不做任何乘加，只有读+写往返）")
print("=" * 84)
ZERO = {"Concat", "Add", "Resize", "MaxPool", "Transpose", "Reshape", "Slice", "Split", "Pad"}
zw = sum(out_bytes[o] + read_bytes[o] for o in ZERO)
print("  零/低计算量算子合计流量 : %.2f MB  (%.1f%% of 激活流量)" % (zw/1e6, 100*zw/tot_out))
for o in sorted(ZERO, key=lambda o: -(out_bytes[o]+read_bytes[o])):
    if out_cnt[o]:
        t = out_bytes[o] + read_bytes[o]
        print("    %-12s %2d 个   %7.2f MB  (%.1f%%)" % (o, out_cnt[o], t/1e6, 100*t/tot_out))

print()
print("=" * 84)
print("每帧 DRAM 流量总账（按 RKNN 融合 Conv+BN+ReLU 后的现实模型）")
print("=" * 84)
conv_act = sum(out_bytes[o] + read_bytes[o] for o in ("Conv",))
w_int8 = TOT_W_FP32 * SCALE
gin, gout = vol("images"), sum(vol(o.name) for o in m.graph.output)
print("  权重 (INT8, 每帧读一遍)   : %7.2f MB  (%.1f%%)" % (w_int8/1e6, 100*w_int8/(conv_act+w_int8+gin+gout)))
print("  网络输入 + 输出           : %7.2f MB  (%.1f%%)" % ((gin+gout)/1e6, 100*(gin+gout)/(conv_act+w_int8+gin+gout)))
print("  层间激活往返              : %7.2f MB  (%.1f%%)" % (conv_act/1e6, 100*conv_act/(conv_act+w_int8+gin+gout)))
TOT = conv_act + w_int8 + gin + gout
print("  " + "-"*60)
print("  合计                      : %7.2f MB/帧" % (TOT/1e6))
print("  177.6 fps 对应带宽        : %.1f GB/s" % (TOT*177.6/1e9))
print()
print("  理想融合下限(仅输入+输出+权重): %.2f MB  →  %.1f 倍削减空间" % ((gin+gout+w_int8)/1e6, TOT/(gin+gout+w_int8)))

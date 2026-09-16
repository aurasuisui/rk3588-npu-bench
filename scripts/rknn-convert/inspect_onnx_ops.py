#!/usr/bin/env python3
"""inspect_onnx_ops.py — 统计 ONNX 算子分布，看激活函数用了什么
用法：python inspect_onnx_ops.py model.onnx
"""
import sys, collections
import onnx

p = sys.argv[1]
m = onnx.load(p)
c = collections.Counter(n.op_type for n in m.graph.node)

print("总节点数:", len(m.graph.node))
print("IR version:", m.ir_version, "| producer:", m.producer_name, m.producer_version)
print("opset:", [(o.domain or "ai.onnx", o.version) for o in m.opset_import])
print()
print("=== 全部算子分布 ===")
for op, n in c.most_common():
    print("%-26s %d" % (op, n))

print()
print("=== 激活函数体检 ===")
groups = {
    "SiLU/Swish 特征 (Sigmoid+Mul / Exp)": ["Sigmoid", "Exp", "Erf", "Tanh"],
    "量化友好激活": ["Relu", "LeakyRelu", "Clip", "HardSigmoid", "HardSwish"],
    "其他": ["Softmax"],
}
for name, ops in groups.items():
    tot = sum(c.get(o, 0) for o in ops)
    detail = ", ".join("%s=%d" % (o, c.get(o, 0)) for o in ops if c.get(o, 0))
    print("%-38s 合计 %-5d  %s" % (name, tot, detail or "-"))

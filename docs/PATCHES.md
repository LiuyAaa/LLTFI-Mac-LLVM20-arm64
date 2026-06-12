# Patch 说明

本仓库对**官方 LLTFI onnx-mlir fork**（`DependableSystemsLab/onnx-mlir-lltfi @
b6996967d4`）和**上游 LLVM 20.1.0** 打了 4 个小 patch，**全部都是 LLVM 20 API
兼容性的最小必要改动**。

> 上游 LLTFI 分支最后提交是 2026-05-10（"Upgrade modified ONNX-MLIR files for
> LLVM19"），至今**没有 LLVM 20 适配的官方更新**。LLTFI 主项目 `migration.md` H-3
> 项（onnx-mlir 环境）也显示 **Pending**。

---

## Patch 总览

| Patch | 文件数 | 类别 | 是否可还原 |
|-------|--------|------|-----------|
| `patches/llvm-float8-builder.patch` | 2 | 新增 4 个 getter | ✅ |
| `patches/onnx-mlir-llvm20-compat.patch` (sed 部分) | 11 | API 替换 | ✅ |
| `patches/onnx-mlir-llvm20-compat.patch` (方法调用) | 2 | 方法调用形式 | ✅ |
| `patches/onnx-mlir-llvm20-compat.patch` (TOSA) | 1 | 关闭子构建 | ✅ |

合计 16 个源文件变更，**+18 行 / -2 行**。

---

## Patch 1：MLIR Float8 Builder 补全

### 症状

```
fatal error: no member named 'getFloat8E4M3FNType' in 'mlir::Builder'
```

`onnx-mlir/src/Dialect/ONNX/ElementsAttr/BType.cpp` 和
`onnx-mlir/src/Dialect/ONNX/ONNXOps/OpHelper.cpp` 调 `builder.getFloat8*Type()`，
但 MLIR 20.1.0 没有为 Float8 类型提供 `Builder` 的便利方法。

### 上游为何没补

LLVM 20 引入了 Float8 类型（E4M3FN, E4M3FNUZ, E5M2, E5M2FNUZ, E4M3B11FNUZ, E8M0FNU），
但 `Builder` 类只补了 `Float{16,32,64,80,128}` 的 getter，Float8 系列是**已知遗漏**。

### 修复

仿照 `getF{16,32,64,80,128}Type` 的写法加 4 个 getter：

```cpp
FloatType Builder::getFloat8E4M3FNType()   { return Float8E4M3FNType::get(context); }
FloatType Builder::getFloat8E4M3FNUZType() { return Float8E4M3FNUZType::get(context); }
FloatType Builder::getFloat8E5M2Type()      { return Float8E5M2Type::get(context); }
FloatType Builder::getFloat8E5M2FNUZType() { return Float8E5M2FNUZType::get(context); }
```

### 未来修复方向

向 `llvm/llvm-project` 上游提一个 patch：把 4 个 Float8 getter 加到 `Builder` 类。
这是显然的遗漏（type kind 存在，getter 缺失），merge 应该会很快。

---

## Patch 2：`FloatType::getF*` API 替换

### 症状

```
error: no member named 'getF16' in 'mlir::FloatType'
```

### 上游为何这样

MLIR 19 之前，`FloatType` 是个 union type，提供 `FloatType::getF16(ctx)` 等静态方法
返回对应子类型。MLIR 19 开始，类型系统重构成更细粒度的类层级，删除了这些便利方法。

### 修复

`FloatType::getF{16,32,64,BF16}(ctx)` → `Float{16,32,64,BF16}Type::get(ctx)`

涉及 11 个 onnx-mlir 源文件（见 `patches/onnx-mlir-llvm20-compat.patch` 顶部列表）。
用 `sed -i ''` 一次性批量替换。

### 未来修复方向

LLTFI 官方 fork 上游跟进 LLVM 20 时同步修改即可。

---

## Patch 3：`getStridesAndOffset` 自由函数变方法

### 症状

```
error: use of undeclared identifier 'getStridesAndOffset'
```

### 上游为何这样

MLIR 20 把 `getStridesAndOffset` 从 `mlir::` 命名空间的自由函数挪到了
`ShapedType` / `MemRefType` 的成员函数（与 `getShape`、`getRank` 等保持一致风格）。

### 修复

`getStridesAndOffset(t, s, o)` → `t.getStridesAndOffset(s, o)`

涉及 2 个文件：
- `src/Conversion/ONNXToKrnl/ML/CategoryMapper.cpp:284`
- `src/Conversion/KrnlToLLVM/KrnlVectorTypeCast.cpp:81`

### 未来修复方向

LLTFI 上游 fork 跟进 LLVM 20 时同步修改。

---

## Patch 4：TOSA dialect 关闭

### 症状

```
error: no matching function for call to 'mul'
  candidate function not viable: no known conversion from 'IntegerAttr' to
  '::mlir::Value' for 3rd argument
```

### 上游为何这样

MLIR 20 的 TOSA dialect 重构了 `MulOp`：`shift` 操作数从 `IntegerAttr` 改成了
`Value`（统一类型化）。LLTFI 的 `ONNXToTOSA` 转换还在用旧 API。

### 修复

注释掉 `src/Conversion/CMakeLists.txt` 中的 `add_subdirectory(ONNXToTOSA)`。
StableHLO 转换路径（`ONNX_MLIR_ENABLE_STABLEHLO=ON`）仍可用。

### 临时性

这个 patch 是**临时**的 —— 它禁用了 TOSA 后端。我们的 LLTFI 端到端用的是
**Krnl → LLVM** 路径（默认），所以 TOSA 不影响主功能。

### 未来修复方向

等 LLTFI 官方分支跟 LLVM 20 时同步修复 TOSA，或者把 TOSA 路径从 LLTFI 分支
backport 上来。

---

## Patch 应用方式

脚本 `scripts/build-llvm.sh` 和 `scripts/build-onnx-mlir.sh` 会**自动**应用上述
patch。无需手动运行 `git apply` 或 `patch -p1`。

| Patch | 触发脚本 | 触发条件 |
|-------|---------|---------|
| Patch 1 | `apply-llvm-float8-patch.sh` | grep 不到 `getFloat8E4M3FNType` 时 |
| Patch 2 | `build-onnx-mlir.sh` | 每次（幂等） |
| Patch 3 | `build-onnx-mlir.sh` | 每次（幂等） |
| Patch 4 | `build-onnx-mlir.sh` | 每次（幂等） |

---

## 验证 patch 已被应用

```bash
# Patch 1
grep "getFloat8E4M3FNType" LLTFI/llvm-project/mlir/include/mlir/IR/Builders.h

# Patch 2 (应找不到 FloatType::getF* 的旧调用)
grep -r "FloatType::getF16" onnx-mlir/src/   # 无输出 = 成功
grep -r "FloatType::getF32" onnx-mlir/src/   # 无输出 = 成功

# Patch 3 (应找不到自由函数调用)
grep -r "getStridesAndOffset(memRefType" onnx-mlir/src/   # 无输出 = 成功
grep -r "getStridesAndOffset(targetType" onnx-mlir/src/   # 无输出 = 成功

# Patch 4 (TOSA 应被注释掉)
grep "ONNXToTOSA" onnx-mlir/src/Conversion/CMakeLists.txt  # 显示 # add_subdirectory(...)
```

---

## 为什么不直接 fork 维护 onnx-mlir？

考虑过。但：

1. **patch 太小**（+18/-2 行）—— 不值得单独 fork + 长期维护
2. **官方可能随时跟** —— 一旦 `DependableSystemsLab/onnx-mlir-lltfi` 升级到 LLVM 20，
   这 4 个 patch 全部消失
3. **patch 形式透明** —— 用户一眼就能看到改了什么，比黑盒 fork 更容易审计

如果未来发现 patch 规模扩大（比如 LLVM 21 又来一轮），届时再单独 fork。

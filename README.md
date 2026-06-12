# LLTFI-Mac-LLVM20-arm64

> **LLTFI 在 macOS Apple Silicon + LLVM 20.1.0 上的端到端可运行版本**

本仓库把 LLTFI（Low-Level Tensor Fault Injector）与其 ML 编译依赖（onnx-mlir fork）
打包成可在 **macOS Apple Silicon (arm64)** 上从零构建、并完整跑通 **C/C++ 端到端 +
MNIST 端到端故障注入** 的最小集合。所有针对 LLVM 20 / Apple Clang 兼容性的 patch、
构建脚本、文档都在此仓库内。

---

## 上游项目

本仓库的所有源码均来自下列上游项目，本仓库**只**做平台适配与构建脚本打包，**不修改算法与论文结论**：

- **LLTFI** (主项目)：<https://github.com/DependableSystemsLab/LLTFI>
  - 上游最后更新：commit `b6996967d4` (2026-05-10, "Upgrade modified ONNX-MLIR files for LLVM19")
  - 原作者论文：见 [`LLTFI/PaperLLFI.bib`](LLTFI/PaperLLFI.bib)
- **onnx-mlir LLTFI fork**：<https://github.com/DependableSystemsLab/onnx-mlir-lltfi/tree/LLTFI>
  - 上游 onnx-mlir：<https://github.com/onnx/onnx-mlir>
- **LLVM / MLIR 20.1.0**：<https://github.com/llvm/llvm-project> (tag `llvmorg-20.1.0`)

如要引用本工作，请优先引用上游 LLTFI 论文；本仓库的 patch 与构建脚本以 `docs/PATCHES.md` 描述的范围为限。

---

## 包含什么

| 目录 | 内容 | 体积 |
|------|------|------|
| `LLTFI/` | LLTFI 上游源码（llvm-project 留空） | ~280 MB（含 sample_programs） |
| `onnx-mlir/` | DependableSystemsLab 的 onnx-mlir LLTFI fork | ~127 MB |
| `patches/` | LLVM Float8 Builder patch、onnx-mlir LLVM20 compat patch | < 10 KB |
| `scripts/` | 一键安装 + 单独步骤 + MNIST 端到端 demo | — |
| `docs/` | 详细安装指南、patch 说明、故障排查 | — |

> 仓库**不**包含 LLVM 20.1.0 源码（6.3 GB），请按 `docs/INSTALL.md` 指引单独克隆。

---

## 验证过的功能

| 功能 | 状态 | 触发方式 |
|------|------|---------|
| C/C++ 硬件故障注入（bitflip、funcname 等 8 种） | ✅ 21/21 测试通过 | `LLTFI/build/test_suite/SCRIPTS/llfi_test --all` |
| C/C++ 软件故障注入（41 个 FIDL selector） | ✅ 可用 | FIDL-Algorithm.py + `injectfault` |
| ONNX → MLIR → LLVM IR | ✅ 验证 | `onnx-mlir --EmitLLVMIR` + `mlir-translate` |
| LLTFI ML 端到端（MNIST bitflip） | ✅ 端到端验证 | `./scripts/run-mnist-demo.sh` |
| TensorFlow SavedModel → ONNX | ✅ 已验证 | 见下方"Python ML 依赖版本" |

### MNIST 验证结果（bitflip 注入到 `alloca` 指令 #6066）

| bit 位置 | 程序退出码 | 含义 |
|----------|-----------|------|
| 4 | **-11** | **CRASH (SIGSEGV)** |
| 57 | 0 | 静默错误（无害） |
| 63 | 0 | 静默错误（无害） |

未故障运行：`eight.png → 0.998805 概率 = 8 ✓`

### Python ML 依赖版本（仅 TF 路径需要）

默认 `run-mnist-demo.sh` 直接使用仓库内预编译的 `model.onnx`，**不需要任何
Python ML 框架**。如果要从 SavedModel 重新生成 ONNX，**必须**用以下版本组合
（在 macOS 上经过验证；详见 [TROUBLESHOOTING.md §D10](docs/TROUBLESHOOTING.md#d10-tf2onnxconvert-macos-mutex-死锁必看)）：

```bash
pip install "tensorflow==2.15.0" "tf2onnx==1.16.1" "onnx==1.15.0" "protobuf==3.20.3"
```

为什么不是最新版：
- TF 2.16+ / protobuf 5.x 触发 macOS Mach-O 弱符号合并 mutex 死锁
- tf2onnx 1.15.1 在 Conv2D `explicit_paddings=[]` 上崩
- tf2onnx 1.17+ 要求更新的 protobuf
- protobuf 4.25.x 与 TF 2.15 不兼容

---

## 快速开始

### 1. 克隆仓库 + LLVM 源码

```bash
git clone https://github.com/LiuyAaa/LLTFI-Mac-LLVM20-arm64.git
cd LLTFI-Mac-LLVM20-arm64

# LLVM 20.1.0（必须 — 仓库不包含）
git clone https://github.com/llvm/llvm-project.git LLTFI/llvm-project
(cd LLTFI/llvm-project && git checkout llvmorg-20.1.0)
```

### 2. 一键构建

```bash
./scripts/install.sh
```

约 30–60 分钟（取决于机器），构建产物：

- `LLTFI/llvm-project/build/` — clang, mlir-translate, opt
- `onnx-mlir/build/Release/bin/onnx-mlir`
- `LLTFI/build/bin/{instrument,profile,injectfault}` + `llfi-passes.dylib`
- `~/local/lib/libjson-c.a`（供 ML demo 用）

### 3. 跑测试

```bash
# C/C++ 端到端 (21/21)
cd LLTFI/build/test_suite
python3 SCRIPTS/llfi_test --all

# ML 端到端 (MNIST bitflip)
./scripts/run-mnist-demo.sh
```

---

## 关键 patch 概览

为了让 LLVM 19 时代的 onnx-mlir fork 跑在 LLVM 20.1.0 上，必须打 4 个 patch：

1. **MLIR Builder 缺 Float8 getter** — 在 `mlir/IR/Builders.{h,cpp}` 添加 4 个 `getFloat8*Type()` 方法
2. **`FloatType::getF*(ctx)` 改 `Float*Type::get(ctx)`** — 11 个 onnx-mlir 文件
3. **`getStridesAndOffset(t,s,o)` 自由函数变 `t.getStridesAndOffset(s,o)`** — 2 个文件
4. **TOSA dialect 关闭** — MLIR 20 的 TOSA `MulOp` 把 `shift` 改成了 `Value`，与 LLTFI 分支不兼容

完整说明见 [`docs/PATCHES.md`](docs/PATCHES.md)。

---

## 与上游的差异

| 维度 | [上游 LLTFI](https://github.com/DependableSystemsLab/LLTFI) | 本仓库 |
|------|---------------------------|--------|
| LLVM 版本 | 19 | **20.1.0** |
| 平台 | Linux (x86_64) | **macOS Apple Silicon (arm64)** |
| 编译器 | gcc/clang (apt) | **Apple Clang + SDK C++ stdlib** |
| ML 端到端 | pending (H-3) | **端到端验证** |
| C/C++ 测试 | 21/21 | **21/21** |

---

## 文档导航

- [`docs/INSTALL.md`](docs/INSTALL.md) — 详细安装步骤（每一步的失败恢复）
- [`docs/PATCHES.md`](docs/PATCHES.md) — patch 的来龙去脉、为何需要、未来修复方向
- [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md) — 常见问题与解法

---

## License

- LLTFI 本身：参见 `LLTFI/LICENSE.TXT`
- onnx-mlir fork：Apache 2.0
- 本仓库脚本和文档：MIT

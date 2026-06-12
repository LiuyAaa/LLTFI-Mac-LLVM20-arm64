# 安装指南

> macOS Apple Silicon (M1/M2/M3/M4) + LLVM 20.1.0 + LLTFI 端到端
>
> 预计耗时：**30–60 分钟**（冷构建） / **5–10 分钟**（增量构建）

---

## 0. 前置条件

| 工具 | 最低版本 | 检查命令 |
|------|----------|---------|
| macOS | 12.0 (Monterey) | `sw_vers` |
| Xcode CLT | 14+ | `xcode-select -p` |
| Homebrew | 任意 | `brew --version` |
| Python | 3.9+ | `python3 --version` |
| CMake | 3.20+ | `cmake --version` |
| Ninja | 任意 | `ninja --version` |
| Git | 任意 | `git --version` |
| json-c | Homebrew 默认 | `brew install json-c` |

```bash
xcode-select --install              # 若提示
brew install cmake ninja python@3.11 json-c
```

> **磁盘空间**：至少 **15 GB**（LLVM 源码 + 构建 + onnx-mlir + LLTFI + 测试数据）

### Python ML 依赖（可选）

`run-mnist-demo.sh` **不需要**任何 Python ML 框架——它使用仓库内预编译的
`model.onnx`。只有当你想**从 SavedModel 重新训练并生成 ONNX** 时才需要：

```bash
pip install "tensorflow==2.15.0" "tf2onnx==1.16.1" "onnx==1.15.0" "protobuf==3.20.3"
```

> **不要用最新版本**：TF 2.16+ / protobuf 5.x 会在 macOS 上触发 Mach-O 弱符号
> 合并 mutex 死锁（详见 [TROUBLESHOOTING.md §D10](TROUBLESHOOTING.md#d10-tf2onnxconvert-macos-mutex-死锁必看)）。

---

## 1. 克隆本仓库

```bash
git clone https://github.com/LiuyAaa/LLTFI-Mac-LLVM20-arm64.git
cd LLTFI-Mac-LLVM20-arm64
```

---

## 2. 克隆 LLVM 20.1.0 源码

本仓库**不**包含 LLVM 源码（6.3 GB）。你需要单独克隆并 checkout tag：

```bash
git clone https://github.com/llvm/llvm-project.git LLTFI/llvm-project
cd LLTFI/llvm-project
git checkout llvmorg-20.1.0
cd ../..
```

> **不要**编译 `LLTFI/llvm-project` 内的所有 targets —— 至少需要 1 小时且要 50 GB。
> 我们只构建 clang + mlir 两个 project。

---

## 3. 初始化 onnx-mlir 第三方子模块

onnx-mlir 依赖若干 submodule。如果它们已是空目录：

```bash
cd onnx-mlir
git submodule update --init --recursive
cd ..
```

如果 `third_party/onnx/onnx/onnx.pb.h` 缺失（submodule 拉了但没数据），手动补：

```bash
# 任意 1.16.x 版本都可以
curl -sL https://github.com/onnx/onnx/archive/refs/tags/v1.16.1.tar.gz | tar xz -C /tmp
cp -r /tmp/onnx-1.16.1/onnx/* onnx-mlir/third_party/onnx/onnx/
```

---

## 4. 一键安装

```bash
./scripts/install.sh
```

脚本依次执行：

1. `build-llvm.sh`（~30 分钟）—— clang + mlir
2. `install-json-c.sh`（~2 分钟）—— 静态库到 `~/local/`
3. `build-onnx-mlir.sh`（~10 分钟）—— 应用 LLVM 20 patch + 编译
4. `build-lltfi.sh`（~3 分钟）—— LLTFI 主体 + FIDL 生成

如果中间任何一步失败，可单独重跑（脚本会跳过已完成部分）：

```bash
./scripts/build-llvm.sh
# ...
./scripts/build-lltfi.sh
```

如果想跳过大步骤：

```bash
SKIP_LLVM=1 ./scripts/install.sh     # 复用已有 LLVM
SKIP_OM=1   ./scripts/install.sh     # 跳过 onnx-mlir
SKIP_LLTFI=1 ./scripts/install.sh    # 跳过 LLTFI
```

---

## 5. 验证

### 5.1 C/C++ 端到端

```bash
cd LLTFI/build/test_suite
python3 SCRIPTS/llfi_test --all
```

**预期：21/21 PASS**。错误日志中出现 fault-injection 引起的崩溃是**正常**的。

### 5.2 ML 端到端（MNIST）

```bash
./scripts/run-mnist-demo.sh
```

**预期输出**：
- 未故障运行：`eight.png → 0.998805`（8）
- bit 4 注入：程序 exit code = -11 (SIGSEGV)
- bit 57 / 63 注入：exit code = 0（静默错误）

---

## 6. 常见安装路径自定义

```bash
# 把 LLVM 装到外置 SSD
LLVM_BUILD_ROOT=/Volumes/SSD/llvm-build ./scripts/build-llvm.sh

# 编译时启用更多 MLIR 转换
CUSTOM_MLIR_PASSES="MLIRTensorToLinalg MLIRLinalgToAffine" \
  ./scripts/build-onnx-mlir.sh

# 用更多核并发（注意内存）
JOBS=12 ./scripts/install.sh
```

---

## 7. 重建指南

| 场景 | 命令 |
|------|------|
| 改了 LLTFI 源码 | `cd LLTFI/build && make -j6` |
| 改了 FIDL 配置 | `python3 LLTFI/tools/FIDL/FIDL-Algorithm.py -a default && cd LLTFI/build && make -j6` |
| 改了 onnx-mlir 源码 | `cd onnx-mlir/build && ninja -j6 onnx-mlir` |
| 改了 LLVM/MLIR 源码 | `cd LLTFI/llvm-project/build && ninja -j6 MLIRIR` |
| 完整重建 | `./scripts/install.sh`（每个脚本幂等） |
| 从零重建 | `rm -rf LLTFI/build LLTFI/llvm-project/build onnx-mlir/build ~/local && ./scripts/install.sh` |

---

## 8. 下一步

- 跑完整测试套件：`./LLTFI/build/test_suite/SCRIPTS/llfi_test --all_ml`
- 自定义故障 selector：编辑 `LLTFI/tools/FIDL/config/default_failures.yaml`
- 写自己的 fault-injection 报告：参考 `LLTFI/docs/`
- 把结果发到论文/课程报告：参考 `LLTFI/PaperLLFI.bib`

# 故障排查

> 记录了从零构建 LLTFI-on-macOS 过程中实际遇到的所有坑。按出现频率排序。

---

## A. LLVM / MLIR 构建期

### A1. `xcrun` 找不到

```
xcrun: error: invalid DEVELOPER_DIR path
```

**原因**：Xcode CLT 没装。
**解决**：
```bash
xcode-select --install
sudo xcode-select -s /Library/Developer/CommandLineTools
```

### A2. `c++ v1` 头文件找不到

```
fatal error: 'vector' file not found
```

**原因**：cmake 用系统默认 C++ 标准库路径，Apple Clang 需要 SDK 里的 libc++。
**解决**：`build-llvm.sh` 已加 `-nostdinc++ -isystem $SDK/usr/include/c++/v1`。
如果用自定义脚本，把这两行复制过去。

### A3. `is_unsigned_v` 未定义

```
error: no member named 'is_unsigned_v' in namespace 'std'
```

**原因**：C++ 标准低于 17。
**解决**：`-DCMAKE_CXX_STANDARD=17`。

### A4. dylib 链接报 missing vtable

```
Undefined symbols for architecture arm64:
  "vtable for llvm::PassInfoMixin<...>"
```

**原因**：macOS 默认链接器不允许 undefined symbol，但 LLVM 的 pass plugin 用
动态注册。
**解决**：`-undefined dynamic_lookup` 同时加到
`CMAKE_SHARED_LINKER_FLAGS` 和 `CMAKE_MODULE_LINKER_FLAGS`。

### A5. 编译时间过长（> 1 小时）

可能的原因与缓解：

- **`LLVM_PARALLEL_LINK_JOBS`** 默认是 CPU 核数，链接时会爆内存。脚本里设了 2。
- **`LLVM_INCLUDE_TESTS=OFF`** 等三个 OFF 一定要开，否则会多构建 ~30% 体积。
- 如果用 M1/M2（8 核），`JOBS=6` 比较安全；M3 Max（16 核）可以 `JOBS=12`。
- 不要用 `LLVM_ENABLE_PROJECTS="clang;mlir;lldb;lld;..."` —— 我们只需要这两个。

---

## B. onnx-mlir 构建期

### B1. `FloatType::getF16` 找不到

参见 [`docs/PATCHES.md`](PATCHES.md) Patch 2。`build-onnx-mlir.sh` 已自动处理。

### B2. TOSA MulOp shift 类型不匹配

参见 [`docs/PATCHES.md`](PATCHES.md) Patch 4。`build-onnx-mlir.sh` 已自动关闭 TOSA。

### B3. `getStridesAndOffset` undeclared

参见 [`docs/PATCHES.md`](PATCHES.md) Patch 3。

### B4. onnx submodule 空

```
fatal error: 'onnx/onnx.pb.h' file not found
```

**解决**：

```bash
cd onnx-mlir
git submodule update --init --recursive
# 若仍然空：手动补
curl -sL https://github.com/onnx/onnx/archive/refs/tags/v1.16.1.tar.gz | tar xz -C /tmp
cp -r /tmp/onnx-1.16.1/onnx/* third_party/onnx/onnx/
```

### B5. `ninja: error: 'OMTensorUtils', needed by '...', missing`

**原因**：C++ 包装构建需要 pybind11，不影响主 `onnx-mlir` 可执行。
**解决**：`build-onnx-mlir.sh` 已分两步构建。OMTensorUtils 失败不会中断主流程。
我们的端到端 demo 用的是 **C `cruntime`**，不需要 OMTensorUtils。

---

## C. LLTFI 构建期

### C1. C++ stdlib 路径错误

同 A2，但 LLTFI 的 cmake 不会自动加 Apple Clang 的 `-nostdinc++` 标志。
`build-lltfi.sh` 已处理。

### C2. FIDL 未生成

```
make: *** No rule to make target '...Selector.cpp'
```

**原因**：FIDL-Algorithm.py 未跑。
**解决**：`build-lltfi.sh` 已自动跑 `python3 tools/FIDL/FIDL-Algorithm.py -a default`。
如果手动 build：

```bash
cd LLTFI && python3 tools/FIDL/FIDL-Algorithm.py -a default
```

### C3. `SoftwareFaults` 目录不存在

```
make[2]: *** No rule to make target '...SoftwareFaults/...'
```

**原因**：上游 LLTFI 假设 `test_suite/SoftwareFaults` 已存在，但 `.gitignore` 排除了空目录。
**解决**：`build-lltfi.sh` 已 `mkdir -p` 该目录。

---

## D. 运行时

### D1. MNIST segfault (exit 139)

**症状**：`./llfi/model-profiling.exe eight.png` 立刻 segfault。
**根因**：`image.c` 用 `stbi_loadf` 读 PNG；如果工作目录没有 PNG 文件，`stbi_loadf`
返回 NULL，后续 `OMTensorCreateWithOwnership` 拿到空 data，访问时崩。
**解决**：确保 `eight.png` / `seven.png` 在运行目录中。`run-mnist-demo.sh` 已自动 `cp`。

### D2. `injectfault`: fi_cycle 错误

```
RuntimeError: fi_cycle start (209927265) > end (1)
```

**原因**：`input.yaml` 里 `fi_cycle` 留空，工具回退到用 profile 的最大 cycle 作 start。
**解决**：在 input.yaml 里显式设 `fi_cycle: 1`（=第 1 个周期开始注入）。

### D3. `instrument` 报 `-lpthread` 失败

**症状**：脚本自动调用 `clang ... -lpthread` 时报 macOS 上 `clang: error: no such file: -lpthread`。
**原因**：macOS 没有 `libpthread.so`，pthread 在 libSystem 里。
**解决**：`run-mnist-demo.sh` 用手动链接绕过了这一步（见脚本 6/7 阶段）。

### D4. `json-c` 编译失败：K&R 函数警告升级为错误

```
error: a function declaration without a prototype is deprecated
```

**原因**：json-c 0.17 用了旧 K&R 风格函数定义。
**解决**：`install-json-c.sh` 已加
`-Wno-error=deprecated-non-prototype -Wno-error=strict-prototypes`。

### D5. `model-profiling.exe` 找不到 llfi-rt

```
dyld: Library not loaded: @rpath/libllfi-rt.dylib
```

**原因**：`llfi-passes.dylib` 和 `libllfi-rt.dylib` 装在 `LLTFI/build/runtime_lib/`，
但运行时不在这条路径上。
**解决**：

```bash
export DYLD_LIBRARY_PATH="${LLTFI}/build/runtime_lib:${OM}/Release/lib:${HOME}/local/lib:${DYLD_LIBRARY_PATH:-}"
```

或者用绝对路径链接（`run-mnist-demo.sh` 采用的方案）：
```bash
clang -L${LLTFI}/runtime_lib -L${OM}/Release/lib -L${HOME}/local/lib \
      -lllfi-rt -lcruntime -ljson-c model.o -o model.exe
```

### D6. `OMTensorCreateWithOwnership` 链接报 duplicate symbol

**症状**：链接时 `OMTensor`/`OMTensorList` 等符号重复定义。
**原因**：`libOMTensorUtils.a`（C++ 包装）和 `libcruntime.a`（C 接口）都导出
相同符号。
**解决**：只链 C 库：
```bash
-lcruntime   # ✅ 用这个
# -lOMTensorUtils   # ❌ 不要用，会和 cruntime 冲突
```

---

## E. 性能 / 资源

### E1. ninja 链接时内存爆

**症状**：系统变卡，ninja 报 `c++: fatal error: killed signal terminated`。
**原因**：LLVM 链接单个 .o 时会占 1–2 GB，M1 8 GB 机型易爆。
**解决**：`LLVM_PARALLEL_LINK_JOBS=2`（脚本里已设）。或关掉其他应用。

### E2. MLIR 全量构建太慢

如果你改了一个 MLIR 头文件，**只**需要重编 `MLIRIR`：

```bash
cd LLTFI/llvm-project/build
ninja MLIRIR MLIROptLib -j6
# 然后回到 onnx-mlir/build 重链
cd ../../../../onnx-mlir/build
ninja onnx-mlir -j6
```

---

## F. 验证

| 检查项 | 命令 | 预期 |
|--------|------|------|
| LLVM 头 | `${LLVM_BUILD_ROOT}/bin/clang --version` | `clang version 20.1.0` |
| MLIR 头 | `${LLVM_BUILD_ROOT}/bin/mlir-translate --version` | 显示版本 |
| onnx-mlir | `${OM}/Release/bin/onnx-mlir --version` | 不报"command not found" |
| LLTFI 头 | `${LLTFI}/bin/instrument --help` | 帮助信息 |
| json-c | `ls ${HOME}/local/lib/libjson-c.a` | 文件存在 |
| C/C++ 套件 | `python3 SCRIPTS/llfi_test --all` | 21/21 |
| ML 套件 | `./scripts/run-mnist-demo.sh` | bit 4 → exit -11 |

---

## G. 仍未解决

| 问题 | 状态 | 影响 |
|------|------|------|
| TensorFlow / PyTorch 转换 | 未测试 | 需 `pip install`，LLTFI 提供的脚本应当能跑通 |
| onnx-mlir StableHLO 路径 | 未启用 | 默认 ONNX_MLIR_ENABLE_STABLEHLO=OFF |
| `-DLLVM_ENABLE_ASSERTIONS=ON` | 未启用 | 调试时建议开，重编 MLIRIR |
| 交叉编译到 x86_64 | 未实现 | 苹果 Rosetta 即可，但 ML 算子会变慢 |

#!/usr/bin/env bash
#
# run-mnist-demo.sh
# -----------------------------------------------------------------------------
# 完整跑通 LLTFI ML 端到端 demo（MNIST bitflip 故障注入）。
#
# 完整流程:
#   1. ExtendONNXModel.py      → extendedmodel.onnx
#   2. onnx-mlir --EmitLLVMIR  → ext-model.onnx.mlir
#   3. mlir-translate          → ext-model.ll
#   4. clang -S -emit-llvm     → main.ll (image.c 驱动)
#   5. llvm-link               → model.ll
#   6. LLTFI instrument        → llfi/model-{profiling,faultinjection}.ll
#   7. clang + 链接 .o         → model-{profiling,faultinjection}.exe
#   8. profile + injectfault   → 输出 + 故障注入
#
# 用法:
#   ./scripts/run-mnist-demo.sh
#
# 环境变量（可选，覆盖默认值）:
#   LLTFI=...                  # LLTFI 构建根
#   OM=...                     # onnx-mlir 构建根
#   LLVM=...                   # LLVM 构建根
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LLTFI="${LLTFI:-${REPO_ROOT}/LLTFI/build}"
OM="${OM:-${REPO_ROOT}/onnx-mlir/build}"
LLVM="${LLVM:-${REPO_ROOT}/LLTFI/llvm-project/build}"
SDK="$(xcrun --show-sdk-path)"

# --- 必要路径检查 --------------------------------------------------------
for tool in \
  "${LLTFI}/bin/instrument" \
  "${LLTFI}/bin/profile" \
  "${LLTFI}/bin/injectfault" \
  "${OM}/Release/bin/onnx-mlir" \
  "${LLVM}/bin/mlir-translate" \
  "${LLVM}/bin/clang" \
  "${LLVM}/bin/llvm-link" \
  "${HOME}/local/lib/libjson-c.a"; do
  if [[ ! -e "${tool}" ]]; then
    echo "[run-mnist-demo] 缺失：${tool}"
    echo "  请确保 LLTFI + onnx-mlir + LLVM + json-c 都已安装"
    exit 1
  fi
done

# --- 工作目录 ------------------------------------------------------------
WORK="${TMPDIR:-/tmp}/lltfi-mnist-demo-$$"
mkdir -p "${WORK}"
cd "${WORK}"
echo "[run-mnist-demo] 工作目录：${WORK}"

# 拷贝 MNIST 样例
MNIST_SRC="${REPO_ROOT}/LLTFI/sample_programs/ml_sample_programs/vision_models/mnist"
cp -f "${MNIST_SRC}/model.onnx" "${WORK}/"
cp -f "${MNIST_SRC}/image.c"    "${WORK}/"
cp -f "${MNIST_SRC}/eight.png"  "${WORK}/"
cp -f "${MNIST_SRC}/seven.png"  "${WORK}/"

# --- 步骤 1-2: 扩展 ONNX 模型 + MLIR 中间表示 ---------------------------
echo "[run-mnist-demo] 1/7 ExtendONNXModel.py ..."
python3 "${REPO_ROOT}/LLTFI/tools/ExtendONNXModel.py" \
  --model_path model.onnx --output_model_path extendedmodel.onnx \
  > expected_op_seq.txt

echo "[run-mnist-demo] 2/7 onnx-mlir --EmitLLVMIR ..."
"${OM}/Release/bin/onnx-mlir" --EmitLLVMIR extendedmodel.onnx -o ext-model

echo "[run-mnist-demo] 3/7 mlir-translate -mlir-to-llvmir ..."
"${LLVM}/bin/mlir-translate" -mlir-to-llvmir ext-model.onnx.mlir -o ext-model.ll

# --- 步骤 3-4: 编译 image.c + 链接 --------------------------------------
echo "[run-mnist-demo] 4/7 clang -emit-llvm image.c ..."
"${LLVM}/bin/clang" -isysroot "${SDK}" -isystem "${SDK}/usr/include" \
  -Wno-error=implicit-int -Wno-error=deprecated-non-prototype \
  -S -emit-llvm -I"${REPO_ROOT}/onnx-mlir/include" -I"${HOME}/local/include" \
  image.c -o main.ll

echo "[run-mnist-demo] 5/7 llvm-link main.ll + ext-model.ll ..."
"${LLVM}/bin/llvm-link" -o model.ll -S main.ll ext-model.ll

# --- 步骤 5: LLTFI instrument ------------------------------------------
echo "[run-mnist-demo] 6/7 LLTFI instrument (profiling + fault injection) ..."
"${LLTFI}/bin/instrument" --readable model.ll

# 手动链接（绕过 LLTFI 工具中硬编码的 -lpthread 问题）
cd llfi
"${LLVM}/bin/clang" -isysroot "${SDK}" -isystem "${SDK}/usr/include" \
  -c model-profiling.ll -o model-profiling.o
"${LLVM}/bin/clang" -isysroot "${SDK}" -isystem "${SDK}/usr/include" \
  -c model-faultinjection.ll -o model-faultinjection.o

"${LLVM}/bin/clang" -isysroot "${SDK}" -isystem "${SDK}/usr/include" \
  -L"${LLTFI}/runtime_lib" -L"${OM}/Release/lib" -L"${HOME}/local/lib" \
  -lllfi-rt -lcruntime -ljson-c -lpthread \
  model-profiling.o -o model-profiling.exe

"${LLVM}/bin/clang" -isysroot "${SDK}" -isystem "${SDK}/usr/include" \
  -L"${LLTFI}/runtime_lib" -L"${OM}/Release/lib" -L"${HOME}/local/lib" \
  -lllfi-rt -lcruntime -ljson-c -lpthread \
  model-faultinjection.o -o model-faultinjection.exe

# --- 步骤 6-7: profile + 故障注入 --------------------------------------
OP_SEQ="$(cat ../expected_op_seq.txt)"

cd "${WORK}"
echo "[run-mnist-demo] 7/7 profile + injectfault ..."
echo ""
echo "=== 未故障运行 ==="
./llfi/model-profiling.exe eight.png "${OP_SEQ}"
echo ""

echo "=== 故障注入（bitflip into alloca 指令 #6066，bit 4） ==="
LLFI_PROFILE_INPUT_INFO_PATH="${WORK}/llfi/stdinputinfo.txt" \
"${LLTFI}/bin/injectfault" \
  -i 6066 -b 4 \
  ./llfi/model-faultinjection.exe eight.png "${OP_SEQ}"

echo ""
echo "=== 完整 ==="
echo "  故障统计：${WORK}/llfi/faultinjectionresult/"
echo "  profile 数据：${WORK}/llfi/profilingresult/"
echo "  输入输出：${WORK}/llfi/stdin.txt / stdout.txt / stderr.txt"
echo ""
echo "[run-mnist-demo] 退出码：成功"

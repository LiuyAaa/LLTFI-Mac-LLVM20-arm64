#!/usr/bin/env bash
#
# build-lltfi.sh
# -----------------------------------------------------------------------------
# 构建 LLTFI 主体（C/C++ 端到端 + LLVM pass 插件 + 运行时库）。
# ML 端到端（ONNX）不在此脚本范围 — 依赖 onnx-mlir + json-c。
#
# 用法:
#   ./scripts/build-lltfi.sh
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LLTFI_SRC="${LLTFI_SRC:-${REPO_ROOT}/LLTFI}"
LLTFI_BUILD="${LLTFI_BUILD:-${LLTFI_SRC}/build}"
JOBS="${JOBS:-6}"

LLVM_BUILD_ROOT="${LLVM_BUILD_ROOT:-${REPO_ROOT}/LLTFI/llvm-project/build}"
SDK="$(xcrun --show-sdk-path)"

if [[ ! -d "${LLVM_BUILD_ROOT}" ]]; then
  echo "[build-lltfi] 错误：未找到 LLVM 构建目录 ${LLVM_BUILD_ROOT}"
  echo "  请先运行 scripts/build-llvm.sh"
  exit 1
fi

# --- 步骤 1: 应用 LLVM Float8 Builder patch（如果需要）--------------------
BUILDERS_H="${LLVM_BUILD_ROOT}/../mlir/include/mlir/IR/Builders.h"
if [[ -f "${BUILDERS_H}" ]] && ! grep -q "getFloat8E4M3FNType" "${BUILDERS_H}"; then
  echo "[build-lltfi] 应用 LLVM Float8 Builder patch..."
  "${REPO_ROOT}/scripts/apply-llvm-float8-patch.sh"
fi

# --- 步骤 2: 配置 LLTFI 构建目录 -----------------------------------------
if [[ ! -d "${LLTFI_BUILD}" ]]; then
  echo "[build-lltfi] 首次配置 (cmake) ..."
  mkdir -p "${LLTFI_BUILD}"
  cd "${LLTFI_BUILD}"

  cmake -G "Unix Makefiles" -DNO_GUI=ON \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_CXX_STANDARD=17 \
    -DCMAKE_OSX_SYSROOT="${SDK}" \
    -DCMAKE_CXX_FLAGS="-nostdinc++ -isystem ${SDK}/usr/include/c++/v1 -isystem ${SDK}/usr/include" \
    -DCMAKE_C_FLAGS="-isystem ${SDK}/usr/include" \
    -DCMAKE_SHARED_LINKER_FLAGS="-undefined dynamic_lookup" \
    -DCMAKE_MODULE_LINKER_FLAGS="-undefined dynamic_lookup" \
    -DLLVM_DST_ROOT="${LLVM_BUILD_ROOT}" \
    -DLLVM_SRC_ROOT="${LLVM_BUILD_ROOT}/.." \
    -DLLVM_GXX_BIN_DIR="${LLVM_BUILD_ROOT}/bin" \
    "${LLTFI_SRC}"
fi

# --- 步骤 3: 生成 FIDL 软件故障选择器 -------------------------------------
echo "[build-lltfi] 生成 FIDL 软件故障选择器..."
python3 "${LLTFI_SRC}/tools/FIDL/FIDL-Algorithm.py" -a default

# --- 步骤 4: 准备测试套件目录（防止 make 失败） ---------------------------
mkdir -p "${LLTFI_SRC}/test_suite/SoftwareFaults"

# --- 步骤 5: make --------------------------------------------------------
cd "${LLTFI_BUILD}"
echo "[build-lltfi] make -j${JOBS} ..."
make -j"${JOBS}"

echo "[build-lltfi] 完成：${LLTFI_BUILD}/bin"
echo "  instrument / profile / injectfault 已就绪"

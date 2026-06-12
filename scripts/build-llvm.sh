#!/usr/bin/env bash
#
# build-llvm.sh
# -----------------------------------------------------------------------------
# 在 macOS Apple Silicon 上从源码构建 LLVM 20.1.0（仅 clang + mlir 两个 project），
# 供 onnx-mlir 和 LLTFI 共用。
#
# 用法:
#   ./scripts/build-llvm.sh                   # 默认路径：与仓库同级
#   LLVM_SRC_ROOT=... LLVM_BUILD_ROOT=... ./scripts/build-llvm.sh
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LLVM_VERSION="${LLVM_VERSION:-20.1.0}"
LLVM_TAG="${LLVM_TAG:-llvmorg-${LLVM_VERSION}}"
LLVM_SRC_ROOT="${LLVM_SRC_ROOT:-${REPO_ROOT}/LLTFI/llvm-project}"
LLVM_BUILD_ROOT="${LLVM_BUILD_ROOT:-${LLVM_SRC_ROOT}/build}"
JOBS="${JOBS:-6}"

SDK="$(xcrun --show-sdk-path)"

if [[ -d "${LLVM_BUILD_ROOT}" ]]; then
  echo "[build-llvm] ${LLVM_BUILD_ROOT} 已存在 — 跳过配置；如需重建请先 rm -rf"
  exit 0
fi

if [[ ! -d "${LLVM_SRC_ROOT}" ]]; then
  echo "[build-llvm] LLVM 源码未找到：${LLVM_SRC_ROOT}"
  echo "  请先克隆并 checkout tag ${LLVM_TAG}："
  echo "    git clone https://github.com/llvm/llvm-project.git ${LLVM_SRC_ROOT}"
  echo "    cd ${LLVM_SRC_ROOT} && git checkout ${LLVM_TAG}"
  exit 1
fi

echo "[build-llvm] 配置 LLVM ${LLVM_VERSION} ..."
mkdir -p "${LLVM_BUILD_ROOT}"
cd "${LLVM_BUILD_ROOT}"

cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_OSX_SYSROOT="${SDK}" \
  -DCMAKE_C_FLAGS="-isystem ${SDK}/usr/include" \
  -DCMAKE_CXX_FLAGS="-nostdinc++ -isystem ${SDK}/usr/include/c++/v1 -isystem ${SDK}/usr/include" \
  -DLLVM_ENABLE_PROJECTS="clang;mlir" \
  -DLLVM_TARGETS_TO_BUILD="host" \
  -DLLVM_EXPERIMENTAL_TARGETS_TO_BUILD="" \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF \
  -DLLVM_INCLUDE_EXAMPLES=OFF \
  -DLLVM_INCLUDE_DOCS=OFF \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_TERMINFO=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=2 \
  "${LLVM_SRC_ROOT}/llvm"

echo "[build-llvm] ninja -j${JOBS} ..."
ninja -j"${JOBS}" \
  llvm-config llvm-as opt llc clang mlir-translate \
  MLIRIR MLIROptLib MLIRSCFToStandard MLIRAffineToStandard \
  MLIRTransformUtils MLIRLLVMToLLVMIR MLIRTargetLLVMIRExport \
  MLIRVectorToLLVM MLIRSCFToControlFlow \
  MLIRLLVMCommonConversion MLIRFuncToLLVM MLIRMemRefToLLVM \
  MLIRAsyncToLLVM MLIRGPUToLLVMConversion MLIRAMXToLLVM \
  MLIRComplexToLLVM MLIRArmNeonToLLVM MLIRArmSVEToLLVM \
  MLIRMathToLLVM MLIRVectorTransforms MLIRLinalgToLoops

echo "[build-llvm] 完成：${LLVM_BUILD_ROOT}/bin"

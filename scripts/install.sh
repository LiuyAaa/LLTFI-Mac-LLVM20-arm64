#!/usr/bin/env bash
#
# install.sh
# -----------------------------------------------------------------------------
# 一键安装：LLVM 20.1.0 + json-c + onnx-mlir + LLTFI 全部构建。
# 假定 LLTFI/llvm-project/ 已被克隆并 checkout llvmorg-20.1.0 tag。
#
# 用法:
#   ./scripts/install.sh
#   SKIP_LLVM=1 ./scripts/install.sh    # 跳过 LLVM（已构建好）
#   SKIP_OM=1  ./scripts/install.sh    # 跳过 onnx-mlir
#   SKIP_LLTFI=1 ./scripts/install.sh  # 跳过 LLTFI
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"

echo "============================================================"
echo " LLTFI-Mac-LLVM20-arm64 一键安装"
echo "============================================================"
echo ""
echo "REPO_ROOT = ${REPO_ROOT}"
echo "LLVM = ${REPO_ROOT}/LLTFI/llvm-project/build"
echo ""

if [[ "${SKIP_LLVM:-0}" != "1" ]]; then
  echo "--- [1/4] LLVM 20.1.0 ---"
  "${SCRIPT_DIR}/build-llvm.sh"
else
  echo "--- [1/4] LLVM 跳过 (SKIP_LLVM=1) ---"
fi

echo ""
if [[ "${SKIP_JSONC:-0}" != "1" ]]; then
  echo "--- [2/4] json-c (供 LLTFI ML demo) ---"
  "${SCRIPT_DIR}/install-json-c.sh"
else
  echo "--- [2/4] json-c 跳过 (SKIP_JSONC=1) ---"
fi

echo ""
if [[ "${SKIP_OM:-0}" != "1" ]]; then
  echo "--- [3/4] onnx-mlir ---"
  "${SCRIPT_DIR}/build-onnx-mlir.sh"
else
  echo "--- [3/4] onnx-mlir 跳过 (SKIP_OM=1) ---"
fi

echo ""
if [[ "${SKIP_LLTFI:-0}" != "1" ]]; then
  echo "--- [4/4] LLTFI ---"
  "${SCRIPT_DIR}/build-lltfi.sh"
else
  echo "--- [4/4] LLTFI 跳过 (SKIP_LLTFI=1) ---"
fi

echo ""
echo "============================================================"
echo " 安装完成"
echo "============================================================"
echo ""
echo "验证 C/C++ 端到端："
echo "  ${REPO_ROOT}/LLTFI/build/test_suite/SCRIPTS/llfi_test --all"
echo ""
echo "运行 ML 端到端 (MNIST bitflip)："
echo "  ${REPO_ROOT}/scripts/run-mnist-demo.sh"
echo ""

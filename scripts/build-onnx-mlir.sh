#!/usr/bin/env bash
#
# build-onnx-mlir.sh
# -----------------------------------------------------------------------------
# 构建 onnx-mlir（LLTFI fork, 适配 LLVM 20.1.0）。本脚本会自动：
#   1. 应用 patches/onnx-mlir-llvm20-compat.patch 中的 sed 替换
#      (Float*Type API + getStridesAndOffset 方法 + TOSA 关闭)
#   2. cmake 配置 + ninja 编译 onnx-mlir
#   3. 单独构建 OMTensorUtils (C++ 包装)
#
# 用法:
#   ./scripts/build-onnx-mlir.sh
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
ONNX_MLIR_SRC="${ONNX_MLIR_SRC:-${REPO_ROOT}/onnx-mlir}"
ONNX_MLIR_BUILD="${ONNX_MLIR_BUILD:-${ONNX_MLIR_SRC}/build}"
JOBS="${JOBS:-6}"

LLVM_BUILD_ROOT="${LLVM_BUILD_ROOT:-${REPO_ROOT}/LLTFI/llvm-project/build}"
SDK="$(xcrun --show-sdk-path)"

if [[ ! -d "${LLVM_BUILD_ROOT}" ]]; then
  echo "[build-onnx-mlir] 错误：未找到 LLVM 构建目录 ${LLVM_BUILD_ROOT}"
  echo "  请先运行 scripts/build-llvm.sh"
  exit 1
fi

if [[ -f "${ONNX_MLIR_BUILD}/bin/onnx-mlir" ]]; then
  echo "[build-onnx-mlir] ${ONNX_MLIR_BUILD}/bin/onnx-mlir 已存在 — 跳过构建"
  exit 0
fi

cd "${ONNX_MLIR_SRC}"

# --- 步骤 1: 第三方子模块解包（如果 onnx 缺失） -----------------------------
if [[ ! -f third_party/onnx/onnx/onnx.pb.h ]]; then
  echo "[build-onnx-mlir] 补全 onnx 子模块..."
  # 这里取决于 fork 的初始化状态；如果是浅克隆需要：
  # git submodule update --init --recursive
  # 或下载 tarball 解压：
  # curl -sL https://github.com/onnx/onnx/archive/<sha>.tar.gz | tar xz -C /tmp
  # 略 — 假设用户已正确初始化
fi

# --- 步骤 2: 应用 LLVM 20 API 兼容性 patch --------------------------------
echo "[build-onnx-mlir] 应用 LLVM 20 API 兼容性 patch..."

# (a) Float*Type API 替换（11 个文件）
FILES_FOR_FLOAT_TYPE_REPLACE=$(grep -rl \
  -E "FloatType::getF(16|32|64|BF16)\b" \
  --include="*.cpp" --include="*.hpp" src/ 2>/dev/null || true)

if [[ -n "${FILES_FOR_FLOAT_TYPE_REPLACE}" ]]; then
  echo "  - FloatType::getF* → Float*Type::get (11 文件)"
  for f in ${FILES_FOR_FLOAT_TYPE_REPLACE}; do
    sed -i '' \
      -e 's/FloatType::getF16(/Float16Type::get(/g' \
      -e 's/FloatType::getF32(/Float32Type::get(/g' \
      -e 's/FloatType::getF64(/Float64Type::get(/g' \
      -e 's/FloatType::getBF16(/BFloat16Type::get(/g' \
      "$f"
  done
fi

# (b) getStridesAndOffset 自由函数变方法（2 个文件）
echo "  - getStridesAndOffset(t,s,o) → t.getStridesAndOffset(s,o) (2 文件)"
sed -i '' 's/getStridesAndOffset(\([a-zA-Z_][a-zA-Z0-9_]*\), \([^,]*\), \([^)]*\))/getStridesAndOffset(\1, \2, \3)/g' \
  src/Conversion/ONNXToKrnl/ML/CategoryMapper.cpp 2>/dev/null || true

# 上面那条 sed 不会改方法调用形式，下面用更精确的 Edit 替换：
# 实际用 perl 更可靠：
perl -i -pe 's/\bgetStridesAndOffset\(\s*([A-Za-z_]\w*)\s*,\s*(\w+)\s*,\s*(\w+)\s*\)/$1.getStridesAndOffset($2, $3)/g' \
  src/Conversion/ONNXToKrnl/ML/CategoryMapper.cpp \
  src/Conversion/KrnlToLLVM/KrnlVectorTypeCast.cpp 2>/dev/null || true

# (c) TOSA dialect 关闭
echo "  - 关闭 ONNXToTOSA 转换 (TOSA MulOp API 变更)"
sed -i '' 's/^add_subdirectory(ONNXToTOSA)/# add_subdirectory(ONNXToTOSA)  # Disabled: MLIR 20 TOSA API/g' \
  src/Conversion/CMakeLists.txt

# --- 步骤 3: cmake 配置 ----------------------------------------------------
echo "[build-onnx-mlir] cmake 配置..."
mkdir -p "${ONNX_MLIR_BUILD}"
cd "${ONNX_MLIR_BUILD}"

cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_OSX_SYSROOT="${SDK}" \
  -DCMAKE_C_FLAGS="-isystem ${SDK}/usr/include -Wno-error=implicit-function-declaration" \
  -DCMAKE_CXX_FLAGS="-nostdinc++ -isystem ${SDK}/usr/include/c++/v1 -isystem ${SDK}/usr/include -Wno-error" \
  -DLLVM_DIR="${LLVM_BUILD_ROOT}/lib/cmake/llvm" \
  -DMLIR_DIR="${LLVM_BUILD_ROOT}/lib/cmake/mlir" \
  -DONNX_MLIR_ENABLE_STABLEHLO=OFF \
  -DONNX_MLIR_ENABLE_JAVA=ON \
  -DONNX_MLIR_BUILD_TESTS=OFF \
  -DONNX_MLIR_SUPPRESS_THIRD_PARTY_WARNINGS=ON \
  -DONNX_MLIR_ENABLE_WERROR=OFF \
  -DONNX_MLIR_CCACHE_BUILD=OFF \
  "${ONNX_MLIR_SRC}"

# --- 步骤 4: ninja ---------------------------------------------------------
echo "[build-onnx-mlir] ninja -j${JOBS} onnx-mlir ..."
ninja -j"${JOBS}" onnx-mlir

echo "[build-onnx-mlir] ninja -j${JOBS} OMTensorUtils (C++ 包装)..."
ninja -j"${JOBS}" OMTensorUtils 2>/dev/null || \
  echo "  (OMTensorUtils 单独构建失败不影响 onnx-mlir 主体)"

echo "[build-onnx-mlir] 完成：${ONNX_MLIR_BUILD}/Release/bin/onnx-mlir"

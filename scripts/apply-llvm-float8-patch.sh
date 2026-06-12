#!/usr/bin/env bash
#
# apply-llvm-float8-patch.sh
# -----------------------------------------------------------------------------
# 把 patches/llvm-float8-builder.patch 应用到已克隆但未编译的
# llvm-project 源码树（Builders.h + Builders.cpp 各加 4 行）。
#
# 设计原则：保持 patch 与构建目录解耦 —— LLVM 编译目录是 build/，源码是 ../。
# 我们直接用 perl 改写源文件，不引入 unified diff 上下文噪音。
# -----------------------------------------------------------------------------
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
LLVM_SRC_ROOT="${LLVM_SRC_ROOT:-${REPO_ROOT}/LLTFI/llvm-project}"
BUILDERS_H="${LLVM_SRC_ROOT}/mlir/include/mlir/IR/Builders.h"
BUILDERS_CPP="${LLVM_SRC_ROOT}/mlir/lib/IR/Builders.cpp"

if [[ ! -f "${BUILDERS_H}" || ! -f "${BUILDERS_CPP}" ]]; then
  echo "[apply-llvm-float8-patch] 错误：未找到 Builders.{h,cpp}，请检查 LLVM_SRC_ROOT"
  exit 1
fi

# 头文件：插入到 getF128Type 之后
if ! grep -q "getFloat8E4M3FNType" "${BUILDERS_H}"; then
  echo "  修补 ${BUILDERS_H} ..."
  perl -i -pe '
    if (/^  FloatType getF128Type\(\);/ && !$done) {
      $_ .= "  FloatType getFloat8E4M3FNType();\n" .
            "  FloatType getFloat8E4M3FNUZType();\n" .
            "  FloatType getFloat8E5M2Type();\n" .
            "  FloatType getFloat8E5M2FNUZType();\n";
      $done = 1;
    }
  ' "${BUILDERS_H}"
fi

# 实现文件：插入到 getF128Type 实现之后
if ! grep -q "Builder::getFloat8E4M3FNType" "${BUILDERS_CPP}"; then
  echo "  修补 ${BUILDERS_CPP} ..."
  perl -i -pe '
    if (/^FloatType Builder::getF128Type\(\) \{ return Float128Type::get\(context\); \}$/ && !$done) {
      $_ .= "\n" .
            "FloatType Builder::getFloat8E4M3FNType() { return Float8E4M3FNType::get(context); }\n\n" .
            "FloatType Builder::getFloat8E4M3FNUZType() { return Float8E4M3FNUZType::get(context); }\n\n" .
            "FloatType Builder::getFloat8E5M2Type() { return Float8E5M2Type::get(context); }\n\n" .
            "FloatType Builder::getFloat8E5M2FNUZType() { return Float8E5M2FNUZType::get(context); }\n";
      $done = 1;
    }
  ' "${BUILDERS_CPP}"
fi

echo "[apply-llvm-float8-patch] 完成"
echo "  验证：grep Float8 ${BUILDERS_H} ${BUILDERS_CPP}"

#!/usr/bin/env bash
#
# install-json-c.sh
# -----------------------------------------------------------------------------
# 从源码安装 json-c（静态库）到 $HOME/local/，供 LLTFI ML 端到端示例使用。
# LLTFI 在运行时通过 OMTensor 的 metadata 写 JSON 文件，需要此依赖。
#
# 用法:
#   ./scripts/install-json-c.sh
# -----------------------------------------------------------------------------
set -euo pipefail

PREFIX="${PREFIX:-$HOME/local}"
JSON_C_VERSION="${JSON_C_VERSION:-0.17}"
TARBALL_SHA="${JSON_C_SHA:-42aa6f7257a42468a432078e05c946dd52274dd3}"
WORK_DIR="${TMPDIR:-/tmp}/json-c-build-$$"

if [[ -f "${PREFIX}/lib/libjson-c.a" ]]; then
  echo "[install-json-c] ${PREFIX}/lib/libjson-c.a 已存在 — 跳过"
  exit 0
fi

SDK="$(xcrun --show-sdk-path)"

mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

echo "[install-json-c] 下载 json-c ${JSON_C_VERSION} (${TARBALL_SHA:0:8}) ..."
curl -sL "https://github.com/json-c/json-c/archive/${TARBALL_SHA}.tar.gz" -o json-c.tar.gz
tar xzf json-c.tar.gz
cd "json-c-${TARBALL_SHA}"

mkdir -p build && cd build

echo "[install-json-c] cmake 配置..."
cmake -G Ninja \
  -DCMAKE_C_COMPILER=/usr/bin/clang \
  -DCMAKE_OSX_SYSROOT="${SDK}" \
  -DCMAKE_C_FLAGS="-isystem ${SDK}/usr/include -Wno-error=implicit-function-declaration -Wno-error=deprecated-non-prototype -Wno-error=strict-prototypes" \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DBUILD_SHARED_LIBS=OFF \
  -DBUILD_TESTING=OFF \
  -DENABLE_THREADING=ON \
  -DCMAKE_POSITION_INDEPENDENT_CODE=OFF \
  ..

echo "[install-json-c] ninja install ..."
ninja json-c install

echo "[install-json-c] 完成：${PREFIX}/lib/libjson-c.a"
echo "  头文件：${PREFIX}/include/json-c/"
echo "  CMake/pkgconfig：${PREFIX}/lib/cmake/json-c/  ${PREFIX}/lib/pkgconfig/json-c.pc"

# SPDX-License-Identifier: Apache-2.0

add_subdirectory(ONNXConversionCommon)
add_subdirectory(ONNXToKrnl)
add_subdirectory(KrnlToLLVM)
add_subdirectory(KrnlToAffine)
add_subdirectory(KrnlSeqToMemref)
# add_subdirectory(ONNXToTOSA)  # Disabled: TOSA API mismatch with MLIR 20.1.0

if (ONNX_MLIR_ENABLE_STABLEHLO)
  add_subdirectory(ONNXToStablehlo)
endif()

cmake_minimum_required(VERSION 3.16)

set(MODULE_ABI_DIR "" CACHE PATH "Directory containing module_abi.h")

if(NOT MODULE_ABI_DIR AND EXISTS "${CMAKE_SOURCE_DIR}/module_abi.h")
    set(MODULE_ABI_DIR "${CMAKE_SOURCE_DIR}")
endif()

if(NOT MODULE_ABI_DIR AND DEFINED ENV{CUBICLUA_ROOT} AND EXISTS "$ENV{CUBICLUA_ROOT}/src/dynmod/module_abi.h")
    set(MODULE_ABI_DIR "$ENV{CUBICLUA_ROOT}/src/dynmod")
endif()

if(NOT MODULE_ABI_DIR AND EXISTS "${CMAKE_SOURCE_DIR}/../../src/dynmod/module_abi.h")
    set(MODULE_ABI_DIR "${CMAKE_SOURCE_DIR}/../../src/dynmod")
endif()

if(NOT EXISTS "${MODULE_ABI_DIR}/module_abi.h")
    message(FATAL_ERROR "module_abi.h not found. Set MODULE_ABI_DIR=/path/to/src/dynmod or CUBICLUA_ROOT.")
endif()

if(CMAKE_MAKE_PROGRAM AND EXISTS "${CMAKE_MAKE_PROGRAM}")
    set(_xz_ninja_cmd "${CMAKE_MAKE_PROGRAM}")
elseif(DEFINED ENV{NINJA} AND EXISTS "$ENV{NINJA}")
    set(_xz_ninja_cmd "$ENV{NINJA}")
elseif(DEFINED ENV{IDF_TOOLS_PATH})
    set(_xz_ninja_candidate "$ENV{IDF_TOOLS_PATH}/tools/ninja/ninja.exe")
    if(EXISTS "${_xz_ninja_candidate}")
        set(_xz_ninja_cmd "${_xz_ninja_candidate}")
    endif()
endif()

if(_xz_ninja_cmd)
    file(TO_CMAKE_PATH "${_xz_ninja_cmd}" _xz_ninja_cmd)
    set(CMAKE_MAKE_PROGRAM "${_xz_ninja_cmd}" CACHE FILEPATH "Path to ninja executable" FORCE)
    set(ENV{CMAKE_MAKE_PROGRAM} "${_xz_ninja_cmd}")
    set(ENV{NINJA} "${_xz_ninja_cmd}")
    get_filename_component(_xz_ninja_dir "${_xz_ninja_cmd}" DIRECTORY)
    if(_xz_ninja_dir)
        set(ENV{PATH} "${_xz_ninja_dir};$ENV{PATH}")
    endif()
    set(_xz_extra_cmake_arg "-DCMAKE_MAKE_PROGRAM=${_xz_ninja_cmd}")
else()
    set(_xz_extra_cmake_arg "")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
if(_xz_extra_cmake_arg)
    idf_build_set_property(EXTRA_CMAKE_ARGS "${_xz_extra_cmake_arg}" APPEND)
endif()

project(xiaozhi)

set(XZ_MODULE_NAME "xiaozhi" CACHE STRING "Native module identity")
idf_build_set_property(COMPILE_DEFINITIONS "XZ_MODULE_ID=${XZ_MODULE_NAME}" APPEND)
idf_build_set_property(COMPILE_INCLUDE_DIRECTORIES "${CMAKE_SOURCE_DIR}/main" APPEND)
idf_build_get_property(xz_build_dir BUILD_DIR)
idf_component_get_property(xz_opus_dir 78__esp-opus COMPONENT_DIR)
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-libgcc-file-name
    OUTPUT_VARIABLE XZ_LIBGCC
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

set(xz_so_include_dirs
    "${MODULE_ABI_DIR}"
    "${xz_opus_dir}/include"
    "${xz_opus_dir}/celt"
    "${xz_opus_dir}/silk"
    "${xz_opus_dir}/silk/fixed"
    "${xz_opus_dir}/src"
    "${xz_opus_dir}"
    "${CMAKE_BINARY_DIR}/config"
    "${IDF_PATH}/components/newlib/platform_include"
    "${IDF_PATH}/components/esp_common/include"
    "${IDF_PATH}/components/esp_system/include"
    "${IDF_PATH}/components/esp_rom/include"
    "${IDF_PATH}/components/esp_rom/${IDF_TARGET}/include"
    "${IDF_PATH}/components/log/include"
    "${IDF_PATH}/components/soc/include"
    "${IDF_PATH}/components/soc/${IDF_TARGET}/include"
    "${IDF_PATH}/components/soc/${IDF_TARGET}/register"
    "${IDF_PATH}/components/hal/include"
    "${IDF_PATH}/components/heap/include"
    "${IDF_PATH}/components/esp_hw_support/include"
    "${IDF_PATH}/components/esp_hw_support/port/${IDF_TARGET}/include"
    "${IDF_PATH}/components/freertos/config/include"
    "${IDF_PATH}/components/freertos/config/include/freertos"
    "${IDF_PATH}/components/freertos/config/xtensa/include"
    "${IDF_PATH}/components/freertos/FreeRTOS-Kernel/include"
    "${IDF_PATH}/components/freertos/FreeRTOS-Kernel/portable/xtensa/include"
    "${IDF_PATH}/components/freertos/FreeRTOS-Kernel/portable/xtensa/include/freertos"
    "${IDF_PATH}/components/freertos/esp_additions/include"
    "${IDF_PATH}/components/xtensa/include"
    "${IDF_PATH}/components/xtensa/${IDF_TARGET}/include"
)
foreach(xz_so_include_dir IN LISTS xz_so_include_dirs)
    idf_build_set_property(COMPILE_INCLUDE_DIRECTORIES "${xz_so_include_dir}" APPEND)
endforeach()

idf_build_set_property(COMPILE_DEFINITIONS "HAVE_LRINT" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS "HAVE_LRINTF" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS "FIXED_POINT=1" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS "DISABLE_FLOAT_API" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS "HAVE_MEMORY_H" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS "HAVE_ALLOCA_H" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS "USE_ALLOCA" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS "OPUS_BUILD" APPEND)
if(IDF_TARGET STREQUAL "esp32s2" OR IDF_TARGET STREQUAL "esp32s3")
    idf_build_set_property(COMPILE_DEFINITIONS "OPUS_XTENSA_LX7" APPEND)
endif()

set(xz_opus_source_rel
    celt/bands.c
    celt/celt.c
    celt/celt_encoder.c
    celt/celt_decoder.c
    celt/cwrs.c
    celt/entcode.c
    celt/entdec.c
    celt/entenc.c
    celt/kiss_fft.c
    celt/laplace.c
    celt/mathops.c
    celt/mdct.c
    celt/modes.c
    celt/pitch.c
    celt/celt_lpc.c
    celt/quant_bands.c
    celt/rate.c
    celt/vq.c
    src/opus.c
    src/opus_decoder.c
    src/opus_encoder.c
    src/extensions.c
    src/repacketizer.c
    silk/CNG.c
    silk/code_signs.c
    silk/init_decoder.c
    silk/decode_core.c
    silk/decode_frame.c
    silk/decode_parameters.c
    silk/decode_indices.c
    silk/decode_pulses.c
    silk/decoder_set_fs.c
    silk/dec_API.c
    silk/enc_API.c
    silk/encode_indices.c
    silk/encode_pulses.c
    silk/gain_quant.c
    silk/interpolate.c
    silk/LP_variable_cutoff.c
    silk/NLSF_decode.c
    silk/NSQ.c
    silk/NSQ_del_dec.c
    silk/PLC.c
    silk/shell_coder.c
    silk/tables_gain.c
    silk/tables_LTP.c
    silk/tables_NLSF_CB_NB_MB.c
    silk/tables_NLSF_CB_WB.c
    silk/tables_other.c
    silk/tables_pitch_lag.c
    silk/tables_pulses_per_block.c
    silk/VAD.c
    silk/control_audio_bandwidth.c
    silk/quant_LTP_gains.c
    silk/VQ_WMat_EC.c
    silk/HP_variable_cutoff.c
    silk/NLSF_encode.c
    silk/NLSF_VQ.c
    silk/NLSF_unpack.c
    silk/NLSF_del_dec_quant.c
    silk/process_NLSFs.c
    silk/stereo_LR_to_MS.c
    silk/stereo_MS_to_LR.c
    silk/check_control_input.c
    silk/control_SNR.c
    silk/init_encoder.c
    silk/control_codec.c
    silk/A2NLSF.c
    silk/ana_filt_bank_1.c
    silk/biquad_alt.c
    silk/bwexpander_32.c
    silk/bwexpander.c
    silk/debug.c
    silk/decode_pitch.c
    silk/inner_prod_aligned.c
    silk/lin2log.c
    silk/log2lin.c
    silk/LPC_analysis_filter.c
    silk/LPC_inv_pred_gain.c
    silk/table_LSF_cos.c
    silk/NLSF2A.c
    silk/NLSF_stabilize.c
    silk/NLSF_VQ_weights_laroia.c
    silk/pitch_est_tables.c
    silk/resampler.c
    silk/resampler_down2_3.c
    silk/resampler_down2.c
    silk/resampler_private_AR2.c
    silk/resampler_private_down_FIR.c
    silk/resampler_private_IIR_FIR.c
    silk/resampler_private_up2_HQ.c
    silk/resampler_rom.c
    silk/sigm_Q15.c
    silk/sort.c
    silk/sum_sqr_shift.c
    silk/stereo_decode_pred.c
    silk/stereo_encode_pred.c
    silk/stereo_find_predictor.c
    silk/stereo_quant_pred.c
    silk/LPC_fit.c
    silk/fixed/LTP_analysis_filter_FIX.c
    silk/fixed/LTP_scale_ctrl_FIX.c
    silk/fixed/corrMatrix_FIX.c
    silk/fixed/encode_frame_FIX.c
    silk/fixed/find_LPC_FIX.c
    silk/fixed/find_LTP_FIX.c
    silk/fixed/find_pitch_lags_FIX.c
    silk/fixed/find_pred_coefs_FIX.c
    silk/fixed/noise_shape_analysis_FIX.c
    silk/fixed/process_gains_FIX.c
    silk/fixed/regularize_correlations_FIX.c
    silk/fixed/residual_energy16_FIX.c
    silk/fixed/residual_energy_FIX.c
    silk/fixed/warped_autocorrelation_FIX.c
    silk/fixed/apply_sine_window_FIX.c
    silk/fixed/autocorr_FIX.c
    silk/fixed/burg_modified_FIX.c
    silk/fixed/k2a_FIX.c
    silk/fixed/k2a_Q16_FIX.c
    silk/fixed/pitch_analysis_core_FIX.c
    silk/fixed/vector_ops_FIX.c
    silk/fixed/schur64_FIX.c
    silk/fixed/schur_FIX.c
    silk/arm/arm_silk_map.c
)

set(xz_opus_sources "")
foreach(xz_opus_rel IN LISTS xz_opus_source_rel)
    list(APPEND xz_opus_sources "${xz_opus_dir}/${xz_opus_rel}")
endforeach()

# Keep Opus inside xiaozhi.so, but list only the official component sources.
# project_so() recursively gathers every .c for ELF_COMPONENTS, which would
# accidentally pull Opus demo/test/DNN sources.
execute_process(COMMAND ${CMAKE_C_COMPILER} -print-file-name=libm.a OUTPUT_VARIABLE XZ_LIBM OUTPUT_STRIP_TRAILING_WHITESPACE)
set(ELF_LIBS ${xz_opus_sources}
    "${XZ_LIBM}" "${XZ_LIBGCC}")
set(ELF_SO_COMPILE_FLAGS -O2)
configure_file("${CMAKE_SOURCE_DIR}/exports.map" "${CMAKE_BINARY_DIR}/exports.map" COPYONLY)
configure_file("${CMAKE_SOURCE_DIR}/xiaozhi_so.ld" "${CMAKE_BINARY_DIR}/xiaozhi_so.ld" COPYONLY)
set(ELF_SO_LINK_FLAGS
    "-Wl,-Bsymbolic"
    "-Wl,--exclude-libs,ALL"
    "-Wl,-z,notext"
    "-Wl,--no-check-sections"
    "-Wl,--version-script=${CMAKE_BINARY_DIR}/exports.map"
    "-Wl,-N"
    "-Wl,-Map,${xz_build_dir}/xiaozhi_so.map"
    "-Wl,-T,${CMAKE_BINARY_DIR}/xiaozhi_so.ld"
)

include(elf_loader)
# elf_loader 1.3.1 does not consume custom link flags. Patch a generated copy,
# not managed_components (dependency resolution replaces that directory).
set(xz_loader_dir "${ELF_LOADER_CMAKE_DIR}")
file(READ "${xz_loader_dir}/elf_loader.cmake" xz_loader)
if(NOT xz_loader MATCHES "if\\(ELF_SO_LINK_FLAGS\\)")
    string(REPLACE "set(so_output" "list(APPEND so_link_flags \${ELF_SO_LINK_FLAGS})\n        set(so_output" xz_loader "${xz_loader}")
    file(WRITE "${CMAKE_BINARY_DIR}/xz_elf_loader.cmake" "${xz_loader}")
    include("${CMAKE_BINARY_DIR}/xz_elf_loader.cmake")
    set(ELF_LOADER_CMAKE_DIR "${xz_loader_dir}")
endif()
project_so(xiaozhi)
add_custom_command(OUTPUT "${xz_build_dir}/so_objs/main_xiaozhi_module.o" APPEND
    DEPENDS "${CMAKE_SOURCE_DIR}/main/playback.inc" "${CMAKE_SOURCE_DIR}/main/xz_memory.inc" "${CMAKE_SOURCE_DIR}/main/xz_alloc.inc" "${MODULE_ABI_DIR}/module_abi.h")

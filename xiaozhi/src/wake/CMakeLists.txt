cmake_minimum_required(VERSION 3.16)

set(MODULE_ABI_DIR "" CACHE PATH "Directory containing module_abi.h")

if(NOT MODULE_ABI_DIR AND EXISTS "${CMAKE_SOURCE_DIR}/../module_abi.h")
    set(MODULE_ABI_DIR "${CMAKE_SOURCE_DIR}/..")
endif()

if(NOT MODULE_ABI_DIR AND DEFINED ENV{CUBICLUA_ROOT} AND EXISTS "$ENV{CUBICLUA_ROOT}/src/dynmod/module_abi.h")
    set(MODULE_ABI_DIR "$ENV{CUBICLUA_ROOT}/src/dynmod")
endif()

if(NOT EXISTS "${MODULE_ABI_DIR}/module_abi.h")
    message(FATAL_ERROR "module_abi.h not found. Set MODULE_ABI_DIR=/path/to/module_abi.h directory or CUBICLUA_ROOT.")
endif()

if(CMAKE_MAKE_PROGRAM AND EXISTS "${CMAKE_MAKE_PROGRAM}")
    set(_wake_ninja_cmd "${CMAKE_MAKE_PROGRAM}")
elseif(DEFINED ENV{NINJA} AND EXISTS "$ENV{NINJA}")
    set(_wake_ninja_cmd "$ENV{NINJA}")
elseif(DEFINED ENV{IDF_TOOLS_PATH})
    set(_wake_ninja_candidate "$ENV{IDF_TOOLS_PATH}/tools/ninja/ninja.exe")
    if(EXISTS "${_wake_ninja_candidate}")
        set(_wake_ninja_cmd "${_wake_ninja_candidate}")
    endif()
endif()

if(_wake_ninja_cmd)
    file(TO_CMAKE_PATH "${_wake_ninja_cmd}" _wake_ninja_cmd)
endif()

if(_wake_ninja_cmd)
    set(CMAKE_MAKE_PROGRAM "${_wake_ninja_cmd}" CACHE FILEPATH "Path to ninja executable" FORCE)
    set(ENV{CMAKE_MAKE_PROGRAM} "${_wake_ninja_cmd}")
    set(ENV{NINJA} "${_wake_ninja_cmd}")
    get_filename_component(_wake_ninja_dir "${_wake_ninja_cmd}" DIRECTORY)
    if(_wake_ninja_dir)
        set(ENV{PATH} "${_wake_ninja_dir};$ENV{PATH}")
    endif()
    set(_wake_extra_cmake_arg "-DCMAKE_MAKE_PROGRAM=${_wake_ninja_cmd}")
else()
    set(_wake_extra_cmake_arg "")
endif()

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
if(_wake_extra_cmake_arg)
    idf_build_set_property(EXTRA_CMAKE_ARGS "${_wake_extra_cmake_arg}" APPEND)
endif()

project(wake)

execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-libgcc-file-name
    OUTPUT_VARIABLE WAKE_LIBGCC
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-file-name=libm.a
    OUTPUT_VARIABLE WAKE_LIBM
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

if(NOT DEFINED WAKE_MODEL_PATH)
    set(WAKE_MODEL_PATH "/sd/apps/xiaozhi/wake")
endif()
idf_build_set_property(COMPILE_DEFINITIONS "WAKE_USE_ESP_SR=1" APPEND)
idf_build_set_property(COMPILE_DEFINITIONS
    "WAKE_MODEL_PATH=${WAKE_MODEL_PATH}"
    APPEND
)
set(_wake_ninja_cmd "")
if(CMAKE_MAKE_PROGRAM AND EXISTS "${CMAKE_MAKE_PROGRAM}")
    set(_wake_ninja_cmd "${CMAKE_MAKE_PROGRAM}")
elseif(DEFINED ENV{NINJA} AND EXISTS "$ENV{NINJA}")
    set(_wake_ninja_cmd "$ENV{NINJA}")
elseif(DEFINED ENV{IDF_TOOLS_PATH})
    set(_wake_ninja_candidate "${ENV{IDF_TOOLS_PATH}}/tools/ninja/ninja.exe")
    if(EXISTS "${_wake_ninja_candidate}")
        set(_wake_ninja_cmd "${_wake_ninja_candidate}")
    endif()
endif()
if(_wake_ninja_cmd)
    set(CMAKE_MAKE_PROGRAM "${_wake_ninja_cmd}" CACHE FILEPATH "Path to ninja executable" FORCE)
    get_filename_component(_wake_ninja_dir "${_wake_ninja_cmd}" DIRECTORY)
    if(_wake_ninja_dir)
        set(ENV{PATH} "${_wake_ninja_dir};$ENV{PATH}")
        set(ENV{NINJA} "${_wake_ninja_cmd}")
        set(ENV{CMAKE_MAKE_PROGRAM} "${_wake_ninja_cmd}")
    endif()
    idf_build_set_property(EXTRA_CMAKE_ARGS "-DCMAKE_MAKE_PROGRAM=${_wake_ninja_cmd}" APPEND)
endif()
idf_build_get_property(wake_build_dir BUILD_DIR)
idf_component_get_property(wake_esp_sr_dir espressif__esp-sr COMPONENT_DIR)

set(wake_esp_sr_lib_dir "${wake_esp_sr_dir}/lib/${IDF_TARGET}")
set(wake_patched_lib_dir "${wake_build_dir}/patched_libs")
set(wake_patched_wakenet_lib "${wake_patched_lib_dir}/libwakenet_picfix.a")
set(wake_patched_speech_lib "${wake_patched_lib_dir}/libc_speech_features_picfix.a")
set(wake_copied_dl_lib "${wake_patched_lib_dir}/libdl_lib.a")
set(wake_copied_hufzip_lib "${wake_patched_lib_dir}/libhufzip.a")
string(REPLACE "-elf-gcc" "-elf-objcopy" wake_objcopy "${CMAKE_C_COMPILER}")

add_custom_command(
    OUTPUT "${wake_patched_wakenet_lib}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${wake_patched_lib_dir}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${wake_esp_sr_lib_dir}/libwakenet.a"
            "${wake_patched_wakenet_lib}"
    COMMAND "${wake_objcopy}"
            --rename-section .rodata.esp_sr_wakenet9_quantized=.data.esp_sr_wakenet9_quantized,alloc,load,contents,data
            --rename-section .rodata.esp_sr_wakenet9l_quantized=.data.esp_sr_wakenet9l_quantized,alloc,load,contents,data
            --rename-section .rodata.esp_sr_wakenet9s_quantized=.data.esp_sr_wakenet9s_quantized,alloc,load,contents,data
            "patched_libs/libwakenet_picfix.a"
    DEPENDS "${wake_esp_sr_lib_dir}/libwakenet.a"
    VERBATIM
)

add_custom_command(
    OUTPUT "${wake_patched_speech_lib}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${wake_patched_lib_dir}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${wake_esp_sr_lib_dir}/libc_speech_features.a"
            "${wake_patched_speech_lib}"
    COMMAND "${wake_objcopy}"
            --rename-section .rodata.esp_fbank_f32=.data.esp_fbank_f32,alloc,load,contents,data
            --rename-section .rodata.esp_fbank_s16=.data.esp_fbank_s16,alloc,load,contents,data
            "patched_libs/libc_speech_features_picfix.a"
    DEPENDS "${wake_esp_sr_lib_dir}/libc_speech_features.a"
    VERBATIM
)

add_custom_command(
    OUTPUT "${wake_copied_dl_lib}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${wake_patched_lib_dir}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${wake_esp_sr_lib_dir}/libdl_lib.a"
            "${wake_copied_dl_lib}"
    DEPENDS "${wake_esp_sr_lib_dir}/libdl_lib.a"
    VERBATIM
)

add_custom_command(
    OUTPUT "${wake_copied_hufzip_lib}"
    COMMAND ${CMAKE_COMMAND} -E make_directory "${wake_patched_lib_dir}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${wake_esp_sr_lib_dir}/libhufzip.a"
            "${wake_copied_hufzip_lib}"
    DEPENDS "${wake_esp_sr_lib_dir}/libhufzip.a"
    VERBATIM
)

add_custom_target(wake_picfix_libs
    DEPENDS
        "${wake_patched_wakenet_lib}"
        "${wake_patched_speech_lib}"
        "${wake_copied_dl_lib}"
        "${wake_copied_hufzip_lib}"
)

set(wake_so_include_dirs
    "${MODULE_ABI_DIR}"
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
    "${IDF_PATH}/components/vfs/include"
    "${IDF_PATH}/components/spi_flash/include"
    "${IDF_PATH}/components/esp_partition/include"
    "${IDF_PATH}/components/spiffs/include"
    "${IDF_PATH}/components/fatfs/diskio"
    "${IDF_PATH}/components/fatfs/src"
    "${IDF_PATH}/components/fatfs/vfs"
    "${CMAKE_SOURCE_DIR}/managed_components/espressif__cjson/cJSON"
    "${wake_esp_sr_dir}/include/${IDF_TARGET}"
    "${wake_esp_sr_dir}/src/include"
    "${wake_esp_sr_dir}/lib/${IDF_TARGET}"
    "${wake_esp_sr_dir}/esp-dl/dl"
    "${wake_esp_sr_dir}/esp-dl/dl/base"
    "${wake_esp_sr_dir}/esp-dl/dl/module"
)
foreach(wake_so_include_dir IN LISTS wake_so_include_dirs)
    idf_build_set_property(COMPILE_INCLUDE_DIRECTORIES "${wake_so_include_dir}" APPEND)
endforeach()
set(ELF_LIBS
    "${wake_esp_sr_dir}/src/esp_sr_debug.c"
    "${wake_patched_wakenet_lib}"
    "${wake_patched_speech_lib}"
    "${wake_copied_dl_lib}"
    "${wake_copied_hufzip_lib}"
    "${wake_build_dir}/esp-idf/espressif__cjson/libespressif__cjson.a"
    "${wake_build_dir}/esp-idf/espressif__dl_fft/libespressif__dl_fft.a"
    "${wake_build_dir}/esp-idf/espressif__esp-dsp/libespressif__esp-dsp.a"
    "${WAKE_LIBM}"
    "${WAKE_LIBGCC}"
)
set(ELF_SO_LINK_FLAGS
    "-Wl,-Bsymbolic"
    "-Wl,--exclude-libs,ALL"
    "-Wl,-z,notext"
    "-Wl,--no-check-sections"
    "-Wl,--version-script=${CMAKE_SOURCE_DIR}/exports.map"
    "-Wl,-N"
    "-Wl,-Map,${wake_build_dir}/wake_so.map"
    "-Wl,-T,${CMAKE_SOURCE_DIR}/wake_so.ld"
)

include(elf_loader)
project_so(wake)
add_dependencies(so wake_picfix_libs)

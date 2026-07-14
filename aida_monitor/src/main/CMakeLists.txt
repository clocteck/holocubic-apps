idf_component_register(
    SRCS "font_module.c"
    INCLUDE_DIRS
        "."
        "../../../mp3_player/src/main"
)

target_compile_options(${COMPONENT_LIB} PRIVATE
    -fPIC
    -fvisibility=hidden
    -fno-jump-tables
    -fno-tree-switch-conversion
)

idf_build_get_property(font_build_dir BUILD_DIR)
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-libgcc-file-name
    OUTPUT_VARIABLE FONT_LIBGCC
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
execute_process(
    COMMAND ${CMAKE_C_COMPILER} -print-file-name=libm.a
    OUTPUT_VARIABLE FONT_LIBM
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

set(font_so_include_dirs
    "${CMAKE_CURRENT_SOURCE_DIR}"
    "${CMAKE_CURRENT_SOURCE_DIR}/../../../mp3_player/src/main"
    "${CMAKE_BINARY_DIR}/config"
    "${IDF_PATH}/components/newlib/platform_include"
    "${IDF_PATH}/components/esp_common/include"
    "${IDF_PATH}/components/esp_system/include"
    "${IDF_PATH}/components/esp_rom/include"
    "${IDF_PATH}/components/esp_rom/${IDF_TARGET}/include"
    "${IDF_PATH}/components/heap/include"
)
foreach(font_so_include_dir IN LISTS font_so_include_dirs)
    idf_build_set_property(COMPILE_INCLUDE_DIRECTORIES "${font_so_include_dir}" APPEND)
endforeach()

set(ELF_LIBS "${FONT_LIBM}" "${FONT_LIBGCC}")
set(ELF_SO_LINK_FLAGS
    "-Wl,-Bsymbolic"
    "-Wl,--exclude-libs,ALL"
    "-Wl,-z,notext"
    "-Wl,--no-check-sections"
    "-Wl,-N"
    "-Wl,-Map,${font_build_dir}/aida_font_so.map"
)

include(elf_loader)
project_so(aida_font)

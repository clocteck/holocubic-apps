cmake_minimum_required(VERSION 3.16)

if(CMAKE_MAKE_PROGRAM AND EXISTS "${CMAKE_MAKE_PROGRAM}")
    set(_jpg_ninja_cmd "${CMAKE_MAKE_PROGRAM}")
elseif(DEFINED ENV{NINJA} AND EXISTS "$ENV{NINJA}")
    set(_jpg_ninja_cmd "$ENV{NINJA}")
elseif(DEFINED ENV{IDF_TOOLS_PATH})
    set(_jpg_ninja_candidate "$ENV{IDF_TOOLS_PATH}/tools/ninja/ninja.exe")
    if(EXISTS "${_jpg_ninja_candidate}")
        set(_jpg_ninja_cmd "${_jpg_ninja_candidate}")
    endif()
endif()

if(_jpg_ninja_cmd)
    file(TO_CMAKE_PATH "${_jpg_ninja_cmd}" _jpg_ninja_cmd)
    set(CMAKE_MAKE_PROGRAM "${_jpg_ninja_cmd}" CACHE FILEPATH "Path to ninja executable" FORCE)
    set(ENV{CMAKE_MAKE_PROGRAM} "${_jpg_ninja_cmd}")
    set(ENV{NINJA} "${_jpg_ninja_cmd}")
    get_filename_component(_jpg_ninja_dir "${_jpg_ninja_cmd}" DIRECTORY)
    if(_jpg_ninja_dir)
        set(ENV{PATH} "${_jpg_ninja_dir};$ENV{PATH}")
    endif()
    set(_jpg_extra_cmake_arg "-DCMAKE_MAKE_PROGRAM=${_jpg_ninja_cmd}")
else()
    set(_jpg_extra_cmake_arg "")
endif()

set(COMPONENTS
    main
    espressif__esp_jpeg
    espressif__esp_new_jpeg
    espressif__elf_loader
    lwip
)

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
if(_jpg_extra_cmake_arg)
    idf_build_set_property(EXTRA_CMAKE_ARGS "${_jpg_extra_cmake_arg}" APPEND)
endif()

project(jpg)

set(ELF_LIBS
    "${CMAKE_BINARY_DIR}/esp-idf/main/libmain.a"
    "${CMAKE_BINARY_DIR}/esp-idf/espressif__esp_jpeg/libespressif__esp_jpeg.a"
)

set(ELF_SO_LINK_FLAGS
    "-Wl,-Bsymbolic"
    "-Wl,--exclude-libs,ALL"
    "-Wl,-z,notext"
    "-Wl,--no-check-sections"
    "-Wl,--version-script=${CMAKE_CURRENT_LIST_DIR}/exports.map"
    "-Wl,-Map,${CMAKE_BINARY_DIR}/jpg_so.map"
)

include(elf_loader)
project_so(jpg)

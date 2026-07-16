cmake_minimum_required(VERSION 3.25)
project(raidenfighters LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Daytona XBLA requires the daytonaxbla branch of ReXGlue.
set(REXGLUE_SDK_SOURCE_DIR
    "${CMAKE_SOURCE_DIR}/../thirdparty/rexglue-sdk"
    CACHE PATH "Path to the required ReXGlue SDK source tree")

if(EXISTS "${REXGLUE_SDK_SOURCE_DIR}/CMakeLists.txt")
    add_subdirectory("${REXGLUE_SDK_SOURCE_DIR}" rexglue-sdk)
else()
    message(FATAL_ERROR
        "Required ReXGlue SDK submodule not found. Run:\n"
        "  git submodule update --init --recursive\n"
        "Expected branch: daytonaxbla\n"
        "Expected path: ${REXGLUE_SDK_SOURCE_DIR}")
endif()

# Include generated source list from rexglue codegen.
# On a fresh clone this file doesn't exist yet; create an empty stub so CMake
# configure succeeds before the first codegen run.
set(_SOURCES_CMAKE "${CMAKE_SOURCE_DIR}/../generated/sources.cmake")
if(NOT EXISTS "${_SOURCES_CMAKE}")
    message(STATUS "generated/sources.cmake not found — run codegen before building (see README)")
    file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/../generated")
    file(WRITE "${_SOURCES_CMAKE}" "# Auto-created stub; run codegen to populate\nset(GENERATED_SOURCES)\n")
endif()
include("${_SOURCES_CMAKE}")

add_executable(raidenfighters
    src/main.cpp
    src/stubs.cpp
    src/keyboard_driver.cpp
    ${GENERATED_SOURCES}
)

# Let rexglue_configure_target add: entry point, rex_app.cpp, mcmodel=large,
# GTK3, RPATH, and other platform flags.
rexglue_configure_target(raidenfighters GPU_PLUGINS xenos)

# Multi-module title: default.xex (this exe, the menu) + jj6/jj7/jj8.xex (the
# three Raiden Fighters games, XexLoadImage'd when picked from GAME PLAY).
# Codegen emits generated/dll_targets.cmake, which builds each guest module into
# its own shared library (libraidenfighters_<module>.so) colocated with this exe.
set(REXGLUE_HOST_TARGET raidenfighters)
set(_DLL_TARGETS_CMAKE "${CMAKE_SOURCE_DIR}/../generated/dll_targets.cmake")
if(EXISTS "${_DLL_TARGETS_CMAKE}")
    include("${_DLL_TARGETS_CMAKE}")
endif()

target_include_directories(raidenfighters PRIVATE
    ${CMAKE_SOURCE_DIR}/../generated
    ${CMAKE_SOURCE_DIR}/../ppc
    ${REXGLUE_SDK_SOURCE_DIR}/thirdparty/simde
    ${REXGLUE_SDK_SOURCE_DIR}/include/simde
    ${REXGLUE_SDK_SOURCE_DIR}/thirdparty/imgui
    ${CMAKE_BINARY_DIR}/rexglue-sdk/include
)

target_link_libraries(raidenfighters PRIVATE
    rex::runtime
)

target_compile_definitions(raidenfighters PRIVATE PPC_INCLUDE_DETAIL)

target_compile_options(raidenfighters PRIVATE
    -fno-strict-aliasing
    -ffp-model=strict
    -fno-char8_t
    $<$<CONFIG:Debug>:-g -O0>
    $<$<CONFIG:Release>:-O3 -DNDEBUG>
    $<$<CONFIG:RelWithDebInfo>:-O2 -g -DNDEBUG>
)

# Force all kernel symbols into the executable (needed for hook registration)
if(WIN32)
    target_link_options(raidenfighters PRIVATE
        "LINKER:/WHOLEARCHIVE:$<TARGET_FILE:rex::kernel>"
    )
else()
    target_link_options(raidenfighters PRIVATE
        -Wl,--whole-archive $<TARGET_FILE:rex::runtime> -Wl,--no-whole-archive
    )
endif()

add_custom_target(raidenfighters_codegen
    COMMAND $<TARGET_FILE:rex::rexglue> --force codegen ${CMAKE_SOURCE_DIR}/../config/rfa_manifest.toml
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/../config
    COMMENT "Regenerating Daytona codegen with vendored ReXGlue SDK"
    VERBATIM
)

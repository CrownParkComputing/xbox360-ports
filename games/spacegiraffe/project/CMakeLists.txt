cmake_minimum_required(VERSION 3.25)
project(spacegiraffe LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Space Giraffe XBLA uses the ReXGlue SDK
set(REXGLUE_SDK_SOURCE_DIR
    "/home/jon/rexglue-sdk"
    CACHE PATH "Path to the required ReXGlue SDK source tree")

if(EXISTS "${REXGLUE_SDK_SOURCE_DIR}/CMakeLists.txt")
    add_subdirectory("${REXGLUE_SDK_SOURCE_DIR}" rexglue-sdk)
else()
    message(FATAL_ERROR
        "Required ReXGlue SDK not found at ${REXGLUE_SDK_SOURCE_DIR}")
endif()

# Include generated source list from rexglue codegen.
set(_SOURCES_CMAKE "${CMAKE_SOURCE_DIR}/../generated/sources.cmake")
if(NOT EXISTS "${_SOURCES_CMAKE}")
    message(STATUS "generated/sources.cmake not found — run codegen before building")
    file(MAKE_DIRECTORY "${CMAKE_SOURCE_DIR}/../generated")
    file(WRITE "${_SOURCES_CMAKE}" "# Auto-created stub; run codegen to populate\nset(GENERATED_SOURCES)\n")
endif()
include("${_SOURCES_CMAKE}")

add_executable(spacegiraffe
    src/main.cpp
    src/stubs.cpp
    src/keyboard_driver.cpp
    ${GENERATED_SOURCES}
)

# Let rexglue_configure_target add: entry point, rex_app.cpp, mcmodel=large,
# GTK3, RPATH, and other platform flags.
rexglue_configure_target(spacegiraffe)

target_include_directories(spacegiraffe PRIVATE
    ${CMAKE_SOURCE_DIR}/../generated
    ${CMAKE_SOURCE_DIR}/../ppc
    ${REXGLUE_SDK_SOURCE_DIR}/thirdparty/simde
    ${REXGLUE_SDK_SOURCE_DIR}/include/simde
    ${REXGLUE_SDK_SOURCE_DIR}/thirdparty/imgui
    ${CMAKE_BINARY_DIR}/rexglue-sdk/include
)

target_link_libraries(spacegiraffe PRIVATE
    rexruntime
)

target_compile_definitions(spacegiraffe PRIVATE PPC_INCLUDE_DETAIL)

target_compile_options(spacegiraffe PRIVATE
    -fno-strict-aliasing
    -ffp-model=strict
    -fno-char8_t
    $<$<CONFIG:Debug>:-g -O0>
    $<$<CONFIG:Release>:-O3 -DNDEBUG>
    $<$<CONFIG:RelWithDebInfo>:-O2 -g -DNDEBUG>
)

# Force all kernel symbols into the executable (needed for hook registration)
if(WIN32)
    target_link_options(spacegiraffe PRIVATE
        "LINKER:/WHOLEARCHIVE:$<TARGET_FILE:rex::kernel>"
    )
else()
    target_link_options(spacegiraffe PRIVATE
        -Wl,--whole-archive $<TARGET_FILE:rexruntime> -Wl,--no-whole-archive
    )
endif()

add_custom_target(spacegiraffe_codegen
    COMMAND $<TARGET_FILE:rex::rexglue> --force codegen ${CMAKE_SOURCE_DIR}/../config/sg_manifest.toml
    WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}/../config
    COMMENT "Regenerating Space Giraffe codegen with vendored ReXGlue SDK"
    VERBATIM
)

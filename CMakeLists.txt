cmake_minimum_required(VERSION 3.20)
project(bevy_hashlink LANGUAGES C)

set(HASHLINK_DIR "${CMAKE_CURRENT_LIST_DIR}/../.." CACHE PATH "Path to the HashLink repository root")

find_program(CARGO_EXECUTABLE cargo
    HINTS "$ENV{USERPROFILE}/.cargo/bin" "$ENV{HOME}/.cargo/bin"
    REQUIRED
)

set(RUST_TARGET_DIR "${CMAKE_CURRENT_LIST_DIR}/target")
if(WIN32)
    set(RUST_LIBRARY "${RUST_TARGET_DIR}/release/bevy_hashlink_native.lib")
else()
    set(RUST_LIBRARY "${RUST_TARGET_DIR}/release/libbevy_hashlink_native.a")
endif()

add_custom_command(
    OUTPUT "${RUST_LIBRARY}"
    COMMAND "${CARGO_EXECUTABLE}" build --manifest-path "${CMAKE_CURRENT_LIST_DIR}/Cargo.toml" --release
    WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
    DEPENDS
        "${CMAKE_CURRENT_LIST_DIR}/Cargo.toml"
        "${CMAKE_CURRENT_LIST_DIR}/Cargo.lock"
        "${CMAKE_CURRENT_LIST_DIR}/rust-toolchain.toml"
        "${CMAKE_CURRENT_LIST_DIR}/rust/src/lib.rs"
    COMMENT "Building the Bevy ECS Rust core"
    VERBATIM
)
add_custom_target(bevy_rust DEPENDS "${RUST_LIBRARY}")

add_library(bevy.hdll SHARED bevy_hl.c)
add_dependencies(bevy.hdll bevy_rust)
target_include_directories(bevy.hdll PRIVATE "${HASHLINK_DIR}/src")

if(MSVC)
    set(LIBHL_PATH "${HASHLINK_DIR}/x64/Release/libhl.lib" CACHE FILEPATH "Path to libhl.lib")
    if(NOT EXISTS "${LIBHL_PATH}")
        message(FATAL_ERROR "libhl.lib not found at ${LIBHL_PATH}; build HashLink Release x64 first")
    endif()
    target_link_libraries(bevy.hdll PRIVATE
        "${RUST_LIBRARY}"
        "${LIBHL_PATH}"
        advapi32 bcrypt ntdll userenv ws2_32
    )
else()
    find_library(HASHLINK_LIBRARY NAMES hl libhl PATHS "${HASHLINK_DIR}" REQUIRED)
    target_link_libraries(bevy.hdll PRIVATE "${RUST_LIBRARY}" "${HASHLINK_LIBRARY}" pthread dl m)
    target_link_options(bevy.hdll PRIVATE "-Wl,--no-undefined")
endif()

set_target_properties(bevy.hdll PROPERTIES
    PREFIX ""
    OUTPUT_NAME "bevy"
    SUFFIX ".hdll"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)

install(TARGETS bevy.hdll DESTINATION bin)

cmake_minimum_required(VERSION 3.15)
project(MediaRemoteAdapter LANGUAGES OBJC)

set(MEDIAREMOTEADAPTER_FRAMEWORK_NAME "MediaRemoteAdapter"
    CACHE STRING "The output name of the adapter framework")
set(MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS "100"
    CACHE STRING "Delay until handling changed now playing information")

if(NOT MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS MATCHES "^[0-9]+$")
    message(FATAL_ERROR "The debounce delay must be a positive integer, "
                        "got ${MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS}")
endif()

set(SOURCES
    src/adapter/globals.m
    src/adapter/stream_payload_keys.m
    src/adapter/stream.m
    src/adapter/test.m
    src/private/MediaRemote.m
    src/utility/Debounce.m
    src/utility/helpers.m)
set(HEADERS include/MediaRemoteAdapter.h)

set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64;arm64e")

add_library(MediaRemoteAdapter SHARED ${SOURCES})

if(NOT "${MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS}" STREQUAL "0")
    message("Compiling framework with a debounce delay of "
            "${MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS} milliseconds")
    target_compile_definitions(
        MediaRemoteAdapter
        PRIVATE
            "DEBOUNCE_DELAY_MILLIS=${MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS}")
endif()

set_target_properties(
    MediaRemoteAdapter
    PROPERTIES FRAMEWORK TRUE
               FRAMEWORK_VERSION A
               MACOSX_FRAMEWORK_IDENTIFIER
               "com.example.${MEDIAREMOTEADAPTER_FRAMEWORK_NAME}"
               MACOSX_FRAMEWORK_SHORT_VERSION_STRING 0.1
               MACOSX_FRAMEWORK_BUNDLE_VERSION 0.1.0
               MACOSX_FRAMEWORK_BUNDLE_NAME
               "${MEDIAREMOTEADAPTER_FRAMEWORK_NAME}"
               PUBLIC_HEADER "${HEADERS}"
               OUTPUT_NAME "${MEDIAREMOTEADAPTER_FRAMEWORK_NAME}")

target_link_libraries(MediaRemoteAdapter "-framework Foundation"
                      "-framework AppKit" "-framework JavaScriptCore")

target_include_directories(MediaRemoteAdapter
                           PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_include_directories(MediaRemoteAdapter
                           PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

add_custom_command(
    TARGET MediaRemoteAdapter
    POST_BUILD
    COMMAND codesign --force --deep --sign -
            $<TARGET_BUNDLE_DIR:MediaRemoteAdapter>
    COMMENT "Ad-hoc signing ${MEDIAREMOTEADAPTER_FRAMEWORK_NAME}.framework")

# TODO make debounce optional and configurable with CMake

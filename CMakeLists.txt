cmake_minimum_required(VERSION 3.15)
project(MediaRemoteAdapter LANGUAGES OBJC)

set(ADAPTER_VERSION_MAJOR 0)
set(ADAPTER_VERSION_MINOR 1)
set(ADAPTER_VERSION_PATCH 1)
set(ADAPTER_VERSION_SHORT "${ADAPTER_VERSION_MAJOR}.${ADAPTER_VERSION_MINOR}")
set(ADAPTER_VERSION
    "${ADAPTER_VERSION_MAJOR}.${ADAPTER_VERSION_MINOR}.${ADAPTER_VERSION_PATCH}"
)

set(MEDIAREMOTEADAPTER_FRAMEWORK_NAME "MediaRemoteAdapter"
    CACHE STRING "The output name of the adapter framework")
set(MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS "100"
    CACHE STRING "Delay until handling changed now playing information")

if(NOT MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS MATCHES "^[0-9]+$")
    message(FATAL_ERROR "The debounce delay must be a positive integer, "
                        "got ${MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS}")
endif()

set(SOURCES
    src/adapter/get.m
    src/adapter/globals.m
    src/adapter/keys.m
    src/adapter/now_playing.m
    src/adapter/stream.m
    src/adapter/test.m
    src/private/MediaRemote.m
    src/utility/Debounce.m
    src/utility/helpers.m)
set(HEADERS include/MediaRemoteAdapter.h)

set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64;arm64e")

add_library(MediaRemoteAdapter SHARED ${SOURCES})

if(NOT "${MEDIAREMOTEADAPTER_DEBOUNCE_DELAY_MILLIS}" STREQUAL "0")
    message("Compiling adapter framework with a debounce delay of "
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
               "com.vandenbe.${MEDIAREMOTEADAPTER_FRAMEWORK_NAME}"
               MACOSX_FRAMEWORK_SHORT_VERSION_STRING "${ADAPTER_VERSION_SHORT}"
               MACOSX_FRAMEWORK_BUNDLE_VERSION "${ADAPTER_VERSION}"
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

set(ADAPTER_FRAMEWORK_PATH
    "${CMAKE_CURRENT_BINARY_DIR}/${MEDIAREMOTEADAPTER_FRAMEWORK_NAME}.framework"
    CACHE PATH "Path to built adapter framework")

add_subdirectory(media-control)

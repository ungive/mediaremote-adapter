cmake_minimum_required(VERSION 3.15)
project(MediaRemoteAdapter LANGUAGES OBJC)

set(MEDIAREMOTEADAPTER_FRAMEWORK_NAME "MediaRemoteAdapter"
    CACHE STRING "The output name of the adapter framework")

set(SOURCES src/MediaRemoteAdapter.m src/MediaRemoteAdapterKeys.m
            src/MediaRemote.m src/Debounce.m)
set(HEADERS include/MediaRemoteAdapter.h)

set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64;arm64e")

add_library(MediaRemoteAdapter SHARED ${SOURCES})

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

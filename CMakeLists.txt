cmake_minimum_required(VERSION 3.15)

project(MediaRemoteAdapter LANGUAGES OBJC)

set(SOURCES src/MediaRemoteAdapter.m src/MediaRemoteAdapterKeys.m
            src/MediaRemote.m src/Debounce.m)
set(HEADERS include/MediaRemoteAdapter.h)

set(CMAKE_OSX_ARCHITECTURES "x86_64;arm64")

add_library(MediaRemoteAdapter SHARED ${SOURCES})

set_target_properties(
    MediaRemoteAdapter
    PROPERTIES FRAMEWORK TRUE
               FRAMEWORK_VERSION A
               MACOSX_FRAMEWORK_IDENTIFIER com.example.MediaRemoteAdapter
               MACOSX_FRAMEWORK_SHORT_VERSION_STRING 0.1
               MACOSX_FRAMEWORK_BUNDLE_VERSION 0.1.0
               PUBLIC_HEADER "${HEADERS}")

target_link_libraries(MediaRemoteAdapter "-framework Foundation"
                      "-framework AppKit" "-framework JavaScriptCore")

target_include_directories(MediaRemoteAdapter
                           PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_include_directories(MediaRemoteAdapter
                           PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

install(TARGETS MediaRemoteAdapter FRAMEWORK DESTINATION .
        PUBLIC_HEADER DESTINATION MediaRemoteAdapter.framework/Headers)

# TODO make debounce optional and configurable with CMake

cmake_minimum_required(VERSION 3.15)
project(media_control NONE) # No language needed, just installing files

if(NOT DEFINED ADAPTER_FRAMEWORK_PATH)
    message(FATAL_ERROR "ADAPTER_FRAMEWORK_PATH is not set")
endif()

set(OUT_DIR "${CMAKE_CURRENT_BINARY_DIR}/dist")

set(ADAPTER_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../bin/mediaremote-adapter.pl")

set(BINARY "${CMAKE_CURRENT_SOURCE_DIR}/bin/media-control")

set(BIN_DIR "${OUT_DIR}/bin")
set(LIBEXEC_BIN "${OUT_DIR}/libexec/bin")
set(LIB_DIR "${OUT_DIR}/lib")
get_filename_component(ADAPTER_FRAMEWORK_DIRNAME "${ADAPTER_FRAMEWORK_PATH}"
                       NAME)

install(PROGRAMS "${BINARY}" DESTINATION "${BIN_DIR}")
install(PROGRAMS "${ADAPTER_SCRIPT}" DESTINATION "${LIBEXEC_BIN}")
install(DIRECTORY "${ADAPTER_FRAMEWORK_PATH}" DESTINATION "${LIB_DIR}")

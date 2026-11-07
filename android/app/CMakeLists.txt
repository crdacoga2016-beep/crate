cmake_minimum_required(VERSION 3.14)
project(crate_audio_core)

add_library(crate_audio_core SHARED
  ${CMAKE_CURRENT_LIST_DIR}/../../src/native/crate_audio_core.cpp
)

target_compile_features(crate_audio_core PUBLIC cxx_std_17)
target_include_directories(crate_audio_core PRIVATE
  ${CMAKE_CURRENT_LIST_DIR}/../../src/native
)
target_compile_definitions(crate_audio_core PRIVATE CRATE_AUDIO_CORE_EXPORTS)
set_target_properties(crate_audio_core PROPERTIES
  OUTPUT_NAME "crate_audio_core"
  PREFIX "lib"
  SUFFIX ".so"
)

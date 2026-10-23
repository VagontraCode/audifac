cmake_minimum_required(VERSION 3.22.1)
project(audifac_ffmpeg CXX)

# Minimal static FFmpeg (WMA / APE / WavPack / TTA), built by tools/ffmpeg/build.sh.
set(FFMPEG_DIR ${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg/${ANDROID_ABI})
if(NOT EXISTS ${FFMPEG_DIR}/lib/libavformat.a)
    message(FATAL_ERROR "FFmpeg for ${ANDROID_ABI} is missing: run tools/ffmpeg/build.sh <ndk> (Linux / WSL)")
endif()

foreach(lib avformat avcodec avutil)
    add_library(${lib} STATIC IMPORTED)
    set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION ${FFMPEG_DIR}/lib/lib${lib}.a)
endforeach()

add_library(audifac_ffmpeg SHARED ffmpeg_reader.cpp)
target_include_directories(audifac_ffmpeg PRIVATE ${FFMPEG_DIR}/include)
target_compile_options(audifac_ffmpeg PRIVATE -O2 -fvisibility=hidden -ffunction-sections -fdata-sections)
# Link order matters for static libs: users before what they use.
target_link_libraries(audifac_ffmpeg avformat avcodec avutil log m)
target_link_options(audifac_ffmpeg PRIVATE -Wl,--gc-sections -Wl,--exclude-libs,ALL -Wl,-z,max-page-size=16384)

# DSP hot loops (NEON): no FFmpeg, loaded on its own.
add_library(audifac_dsp SHARED dsp.cpp)
target_compile_options(audifac_dsp PRIVATE -O3 -fvisibility=hidden)
target_link_options(audifac_dsp PRIVATE -Wl,-z,max-page-size=16384)

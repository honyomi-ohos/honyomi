cmake_minimum_required(VERSION 3.5.0)
project(mihon_jsvm_engine)

add_library(jsvmengine SHARED
    jsvm_engine.cpp
    html_selector.cpp)

target_include_directories(jsvmengine PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

target_link_libraries(jsvmengine PUBLIC
    libace_napi.z.so
    libjsvm.so
    libhilog_ndk.z.so)

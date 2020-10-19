#!/bin/bash

PATH_TO_LIBWEBRTC_SOURCES="/Users/markcao/Documents/Webrtc/static_lib/include"
PATH_TO_LIBWEBRTC_BINARY="/Users/markcao/Documents/Webrtc/src/out/mac_static_lib/obj"
PATH_TO_OPENSSL_HEADERS="/usr/local/Cellar/openssl@1.1/1.1.1g/include"

cmake . -Bbuild                                              \
  -DLIBWEBRTC_INCLUDE_PATH:PATH=${PATH_TO_LIBWEBRTC_SOURCES} \
  -DLIBWEBRTC_BINARY_PATH:PATH=${PATH_TO_LIBWEBRTC_BINARY}   \
  -DOPENSSL_INCLUDE_DIR:PATH=${PATH_TO_OPENSSL_HEADERS}      \
  -DCMAKE_USE_OPENSSL=ON \
  -DUSE_SYSTEM_CURL=ON \
  -DBUILD_CPR_TESTS=OFF \
  -DUSE_SYSTEM_GTEST=OFF

make -C build
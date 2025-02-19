# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

ARG parent_image
FROM $parent_image

# Install libstdc++ to use llvm_mode.
RUN apt-get update && \
    apt-get install -y wget libstdc++-5-dev libtool-bin automake flex bison \
                       libglib2.0-dev libpixman-1-dev python3-setuptools unzip \
                       apt-utils apt-transport-https ca-certificates

# Download and compile afl++.
RUN git clone https://github.com/AFLplusplus/AFLplusplus.git /afl && \
    cd /afl && \
    git checkout bb45398d0bbad0b86e311fa6effc286206ecc611

# Build without Python support as we don't need it.
# Set AFL_NO_X86 to skip flaky tests.
RUN cd /afl && unset CFLAGS && unset CXXFLAGS && \
    export CC=clang && export AFL_NO_X86=1 && \
    PYTHON_INCLUDE=/ make && make install && \
    make -C utils/aflpp_driver && \
    cp utils/aflpp_driver/libAFLDriver.a /

# Install the packages we need.
RUN apt-get install -y ninja-build flex bison python zlib1g-dev cargo 

# Install Z3 from binary
RUN wget -qO /tmp/z3x64.zip https://github.com/Z3Prover/z3/releases/download/z3-4.8.7/z3-4.8.7-x64-ubuntu-16.04.zip && \
     unzip -jd /usr/include /tmp/z3x64.zip "*/include/*.h" && \
     unzip -jd /usr/lib /tmp/z3x64.zip "*/bin/libz3.so" && \
     rm -f /tmp/*.zip && \
     ldconfig

ENV CFLAGS=""
ENV CXXFLAGS=""

# Get and install symcc.
RUN cd / && \
    git clone https://github.com/vanhauser-thc/adacc symcc && \
    cd symcc && \
    git checkout 72b5687a6e3d1e5e477b10e77dd0047611b6b5b9 && \
    cd ./runtime/qsym_backend && \
    git clone https://github.com/adalogics/qsym && \
    cd qsym && \
    git checkout adalogics && \
    cd /symcc && \
    mkdir build && \
    cd build && \
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DQSYM_BACKEND=ON \
          -DZ3_TRUST_SYSTEM_VERSION=ON ../ && \
    ninja -j 3 && \
    cd ../examples && \
    export SYMCC_PC=1 && \
    ../build/symcc -c ./libfuzz-harness-proxy.c -o /libfuzzer-harness.o && \
    cd ../ && echo "[+] Installing cargo now 4" && \
    cargo install --path util/symcc_fuzzing_helper

RUN cd / && \
    wget https://raw.githubusercontent.com/llvm/llvm-project/5feb80e748924606531ba28c97fe65145c65372e/compiler-rt/lib/fuzzer/standalone/StandaloneFuzzTargetMain.c -O /StandaloneFuzzTargetMain.c && \
    clang -O2 -c /StandaloneFuzzTargetMain.c && \
    ar rc /libStandaloneFuzzTarget.a StandaloneFuzzTargetMain.o && \
    rm /StandaloneFuzzTargetMain.c

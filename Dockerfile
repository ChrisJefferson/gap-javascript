FROM i386/debian:stable
MAINTAINER Chris Jefferson (caj21@st-andrews.ac.uk)


# This docker file builds GAP (www.gap-system.org) into webassembly, using
# emscripten.

# Most of the complication comes from setting up an environment where we can
# build GAP without having to make any changes.

# Mostly, one builds using emscripten by running configure scripts prefixed
# with 'emconfigure' and make scripts with 'emmake', and "everything works".
# We need to make some small changes.

# 1) We must build in a 32-bit environment, to make GMP work
# 2) We download and install an older version fo binaryen, as the latest
#    (1.38.10 as of this writing) doesn't build on 32-bit ubuntu.
# 3) We build GAP's internal gmp and zlib using emscripten manually, and
#    then tell GAP to use them.

#    ****IMPORTANT****
#
#    At the very end we run the magic line:
#  /binaryen-git/bin/wasm-opt gap.wasm --spill-pointers -o gap-spilled.wasm
#  Without this, the resulting GAP will crash randomly, although this does
#  slow things down a lot.
#  
#  WHY: GAP's garbage collector reads the stack to see which variables are
#  currently being accessed. By default emscripten programs cannot read the
#  values of "registers".  The --spill-pointers code forces all pointers
#  to be written to memory GAP can see, so the garbage collector works.

# This code has been tested with git commit 
# e9c3804a9f2d4785627921217f5f28f18467b227 (2018-07-26). If it does not
# work with the new master branch, try using this instead (see line 106)

WORKDIR /

RUN apt-get update \
    && apt-get install -y --no-install-recommends apt-utils gnupg ca-certificates build-essential cmake \
                            curl git-core openjdk-8-jre-headless python automake autoconf texinfo wget \
    && apt-mark hold openjdk-8-jre-headless \
    && apt-mark hold make 


RUN curl -sL https://deb.nodesource.com/setup_8.x | bash - \
    && apt-get install -y nodejs

RUN curl https://s3.amazonaws.com/mozilla-games/emscripten/releases/emsdk-portable.tar.gz > emsdk-portable.tar.gz \
    && tar xzf emsdk-portable.tar.gz \
    && rm emsdk-portable.tar.gz \
    && cd emsdk-portable \
    && ./emsdk update

ENV EMCC_SDK_VERSION 1.38.10
ENV EMCC_SDK_ARCH 32


RUN cd emsdk-portable \
    && ./emsdk install --build=MinSizeRel sdk-tag-$EMCC_SDK_VERSION-${EMCC_SDK_ARCH}bit

ENV EMCC_BINARYEN_VERSION 1.37.40

RUN cd emsdk-portable \
    && ./emsdk install --build=MinSizeRel binaryen-tag-${EMCC_BINARYEN_VERSION}-${EMCC_SDK_ARCH}bit
RUN cd emsdk-portable \
    && mkdir -p /clang \
    && cp -r /emsdk-portable/clang/tag-e$EMCC_SDK_VERSION/build_tag-e${EMCC_SDK_VERSION}_${EMCC_SDK_ARCH}/bin /clang \
    && mkdir -p /clang/src \
    && cp /emsdk-portable/clang/tag-e$EMCC_SDK_VERSION/src/emscripten-version.txt /clang/src/ \
    && mkdir -p /emscripten \
    && cp -r /emsdk-portable/emscripten/tag-$EMCC_SDK_VERSION/* /emscripten \
    && cp -r /emsdk-portable/emscripten/tag-${EMCC_SDK_VERSION}_${EMCC_SDK_ARCH}bit_optimizer/optimizer /emscripten/ \
    && mkdir -p /binaryen \
    && cp -r /emsdk-portable/binaryen/tag-${EMCC_BINARYEN_VERSION}_${EMCC_SDK_ARCH}bit_binaryen/* /binaryen \
    && echo "import os\nLLVM_ROOT='/clang/bin/'\nNODE_JS='nodejs'\nEMSCRIPTEN_ROOT='/emscripten'\nEMSCRIPTEN_NATIVE_OPTIMIZER='/emscripten/optimizer'\nSPIDERMONKEY_ENGINE = ''\nV8_ENGINE = ''\nTEMP_DIR = '/tmp'\nCOMPILER_ENGINE = NODE_JS\nJS_ENGINES = [NODE_JS]\nBINARYEN_ROOT = '/binaryen/'\n" > ~/.emscripten \
    && rm -rf /emsdk-portable \
    && rm -rf /emscripten/tests \
    && rm -rf /emscripten/site \
    && rm -rf /binaryen/src /binaryen/lib /binaryen/CMakeFiles \
    && for prog in em++ em-config emar emcc emconfigure emmake emranlib emrun emscons emcmake; do \
           ln -sf /emscripten/$prog /usr/local/bin; done \
    && apt-get -y clean \
    && apt-get -y autoclean \
    && apt-get -y autoremove \
    && echo "Installed ... testing"
RUN emcc --version \
    && mkdir -p /tmp/emscripten_test && cd /tmp/emscripten_test \
    && printf '#include <iostream>\nint main(){std::cout<<"HELLO"<<std::endl;return 0;}' > test.cpp \
    && em++ -O2 test.cpp -o test.js && nodejs test.js \
    && em++ test.cpp -o test.js && nodejs test.js \
    && em++ -s WASM=1 test.cpp -o test.js && nodejs test.js \
    && cd / \
    && rm -rf /tmp/emscripten_test \
    && echo "All done."

RUN git clone https://github.com/WebAssembly/binaryen --branch version_49 binaryen-git
RUN cd binaryen-git \
    && cmake . \
    && make -j 4
RUN echo "2" > cheese
RUN git clone https://www.github.com/gap-system/gap
RUN cd gap \
    && git pull \
    && git checkout master
#   Change previous line for this, for a known good commit
#   && git checkout e9c3804a9f2d4785627921217f5f28f18467b227
RUN cd gap/extern/gmp \
    && CC_FOR_BUILD=/usr/bin/gcc ABI=standard emconfigure ./configure \
    --build i686-pc-linux-gnu --host none --disable-assembly --enable-cxx \
    --prefix=${HOME}/opt \
    && emmake make -j 4 \
    && emmake make install
RUN cd gap/extern/zlib \
    && emconfigure ./configure --prefix=${HOME}/opt \
    && emmake make -j 4 \
    && emmake make install
RUN cd gap \
    && ./autogen.sh \
    && emconfigure ./configure --with-gmp=${HOME}/opt --with-zlib=${HOME}/opt \
    && emmake make -j4
RUN cd gap \
    && make bootstrap-pkg-minimal
RUN cd gap \
    && cp gap gap.bc \
    && emcc gap.bc -o gap.html -s ALLOW_MEMORY_GROWTH=1 -O2 \
        --preload-file pkg --preload-file lib --preload-file grp \
    && /binaryen-git/bin/wasm-opt gap.wasm --spill-pointers -o gap-spilled.wasm \
    && mv gap-spilled.wasm gap.wasm
RUN cd gap \
    && ((find lib grp pkg | xargs gzip -f) || true)
RUN cd gap \
    && cp gap gap.bc \
    && emcc gap.bc -o gap-gz.html -s ALLOW_MEMORY_GROWTH=1 -O2 \
        --preload-file pkg --preload-file lib --preload-file grp \
    && /binaryen-git/bin/wasm-opt gap-gz.wasm --spill-pointers -o gap-gz-spilled.wasm \
    && mv gap-gz-spilled.wasm gap-gz.wasm

RUN cd gap \
    && mkdir jsout \
    && cp gap* jsout

# This last part, spill-pointers, is required to make sure all pointers on the stack
# end up in the gap-visible memory, for GASMAN.
VOLUME ["/src"]
WORKDIR /src

This demonstrates how to compile GAP to Javascript (badly).

Some brief instructions are at the top of the docker file.

To build, install docker, then type './extract-web.sh'.

Mostly the install is a standard execution of emscripten,
except we need to use a docker image to make sure various
fragile libraries (in particular gmp) are built and installed
in the correct way.

WARNING: The resulting Javascript is (a) quite slow, and
(b) has a *HORRIBLE* interface. Help is welcome in improving
the interface.
#!/bin/bash
docker kill gap-js-run
docker rm gap-js-run
docker build -t gap-js . &&
rm -rf jsout &&
docker run --name gap-js-run -d -t gap-js /bin/bash  &&
docker cp gap-js-run:/gap out

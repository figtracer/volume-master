#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift run -c release VolumeCheck
clang -std=c11 -O1 -g -fsanitize=address,undefined \
    -I Sources/VolumeDSP/include Sources/VolumeDSP/VolumeDSP.c Tests/RoutingCheck.c \
    -framework CoreAudio -o .build/RoutingCheck
.build/RoutingCheck

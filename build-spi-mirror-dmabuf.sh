#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
XML=$(find /usr/share/cargo/registry -path '*/wlr-protocols/unstable/wlr-export-dmabuf-unstable-v1.xml' -print -quit)
if [ -z "$XML" ]; then
    echo 'Protocol XML not found: sudo apt install librust-wayland-protocols-wlr-dev' >&2
    exit 1
fi
wayland-scanner client-header "$XML" wlr-export-dmabuf-unstable-v1-client-protocol.h
wayland-scanner private-code "$XML" wlr-export-dmabuf-unstable-v1-protocol.c
gcc -O2 -Wall -Wextra -std=gnu11 -o spi-mirror-dmabuf \
    spi-mirror-dmabuf.c wlr-export-dmabuf-unstable-v1-protocol.c \
    $(pkg-config --cflags --libs wayland-client libdrm)
echo 'Built: ./spi-mirror-dmabuf'

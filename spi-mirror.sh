#!/bin/bash

while true; do
    sudo -u pi env XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-0 \
        grim -t ppm - | \
    ffmpeg -loglevel error -f image2pipe -vcodec ppm -i pipe:0 \
        -vf "scale=480:320:flags=fast_bilinear,format=rgb565le" \
        -frames:v 1 -f rawvideo -pix_fmt rgb565le -y /run/spi-frame.raw

    if [ "$(stat -c%s /run/spi-frame.raw 2>/dev/null)" = "307200" ]; then
        dd if=/run/spi-frame.raw of=/dev/fb0 bs=307200 count=1 status=none
    fi

    sleep 0.02
done

for image in /tmp/chip8-video-*.raw ; do
    if [ ! -f "${image::-4}.bmp" ]; then
        cat bmp_header.bin "${image}" > "${image::-4}.bmp"
        magick "${image::-4}.bmp" -flip "${image::-4}.bmp"
    fi
done

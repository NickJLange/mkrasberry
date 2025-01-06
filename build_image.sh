#!/bin/bash

OSIMAGE=$1
target=$2

kernel=kernels/Image

mac_last=$(printf "%x" $(shuf -i 0-255 -n 1));
if [[ -z ${target} ]]; then
  echo "Usage: $0 <osimage> <target>"
  exit 1
fi

PI_BASE=/Volumes/bootfs
new_image="$(basename ${OSIMAGE})-${target}.img"

echo building $new_image and checking $PI_BASE
#-c == clonefile, 
cp -cf images/$(basename ${OSIMAGE}) build_images/${new_image}
ls -l build_images/${new_image}


# Resizing Image to 5Gb due to transient dependencies
dd if=/dev/zero of=build_images/${new_image} seek=5 obs=1G count=0

hdiutil attach build_images/${new_image}
if [ -d ${PI_BASE} ]; then 
    . ./us-ny-wifi.sh
    ./post_install.sh
fi
which_drive=$(hdiutil info | awk 'BEGIN{RS="====+";} /'$target'/' | tail -n 4 | grep FDisk | cut -f 1)
hdiutil detach $which_drive

echo "Launching $new_image as a standalone VM as root for now - I'm not sure if we can predict the ip"
echo "from another window, run the configure script with host_override_ip"

sudo qemu-system-aarch64 -machine virt -cpu cortex-a72 -smp 6 -m 4G -kernel $kernel \
    -append "root=/dev/vda2 rootfstype=ext4 rw panic=0 console=ttyAMA0" \
   -drive format=raw,file=build_images/$new_image,if=none,id=hd0,cache=writeback   \
   -device virtio-blk,drive=hd0,bootindex=0 -device virtio-net-pci,mac=6A:B7:0B:DE:5D:$mac_last,netdev=net0 \
   -netdev vmnet-shared,id=net0  -monitor telnet:127.0.0.1:5555,server,nowait
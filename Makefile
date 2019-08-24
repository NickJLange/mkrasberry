
HII=1

OSIMAGE=2019-06-20-raspbian-buster-lite.img

install_os:
	echo ${OSIMAGE}
	echo time sudo dd if=${OSIMAGE} of=/dev/disk2 bs=1m conv=sync
	diskutil list

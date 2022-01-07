
HII=1

OSIMAGE=images/2021-10-30-raspios-bullseye-arm64-lite.img

install_os:
	echo ${OSIMAGE}
	echo time sudo dd if=${OSIMAGE} of=/dev/disk2 bs=1m conv=sync
	diskutil list

post:
	if [ -d /Volumes/boot ]; then \
		  ./post_install.sh;\
		fi

configure:
	grep newbie hosts
	grep -i ${hostlist}	hosts
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=newbie playbooks/initial-playbook-stage-1.yml || true
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-2.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-3.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-4.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-5.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-5.yml
	#reboot for DNS to kick in / make sure everything comes up
  ANSIBLE_HOST_KEY_CHECKING=False 	ansible -v -b -m reboot terraDelta
	echo ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} podman-install.yml




all: install_os post_install

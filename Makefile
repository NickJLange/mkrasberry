
HII=1
BASE=/Volumes/bootfs
OSIMAGE=images/2021-10-30-raspios-bullseye-arm64-lite.img

install_os:
	echo ${OSIMAGE}
	echo time sudo dd if=${OSIMAGE} of=/dev/disk2 bs=1m conv=sync
	diskutil list

post:
	if [ -d ${BASE} ]; then \
		  ./post_install.sh;\
		fi

configure:
	grep newbie hosts
	grep -i ${hostlist}	hosts
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=newbie playbooks/initial-playbook-stage-1.yml || true
	echo "Sleeping 75 Seconds for SSH to unwind"
	sleep 75
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-2.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-3.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-4.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/initial-playbook-stage-5.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/syslog-configure.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/datadog-install.yml
#	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/wireguard-client-install.yml
  ANSIBLE_HOST_KEY_CHECKING=False ansible -vv -b -m reboot ${hostlist}
	#reboot for DNS to kick in / make sure everything comes up




all: install_os post_install

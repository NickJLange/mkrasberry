
HII=1
BASE=/Volumes/bootfs
OSIMAGE=images/2021-10-30-raspios-bullseye-arm64-lite.img
host_ip_string=${host_ip_override}
ifneq ($(host_ip_string),)
host_ip_string :=  "-e ansible_ssh_host=${host_ip_override}"
endif


build_image:
	@./build_image.sh ${OSIMAGE}

install_os:
	echo ${OSIMAGE}
	echo time sudo dd if=${OSIMAGE} of=/dev/${TARGETDISK} bs=1m conv=sync
	diskutil list

post:
	if [ -d ${BASE} ]; then \
		  ./post_install.sh;\
		fi

configure:
	@grep -i ${hostlist}	hosts
	@echo ${host_ip_string} is set
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=newbie -e ansible_ssh_host=${newbie} playbooks/initial-playbook-stage-1.yml || true
	echo "Sleeping 75 Seconds for SSH to unwind"
#	sleep 75
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-2.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-3.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-4.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-5.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/syslog-configure.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/datadog-install.yml
	@echo "Installing wireguard - make sure to restore from backup"
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/fix-locale.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/wireguard-install-simple.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/wireguard-restore.yml -e dnsgroup=${dnsgroup}
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/internal_certs_update_endpoints.yml -e dnsgroup=${dnsgroup}
	ANSIBLE_HOST_KEY_CHECKING=False ansible -vv -b -m reboot ${hostlist} ${host_ip_string}
	#reboot for DNS to kick in / make sure everything comes up

configure_dns:
	@grep -i ${hostlist}	hosts
	@echo ${host_ip_string} is set
	@echo ${dnsgroup} is set
#	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/pihole-install.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/unbound-refresh-localzone.yml -e dnsgroup=miyagi
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/unbound-refresh-localzone.yml -e dnsgroup=newyork
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/unbound-refresh-localzone.yml -e dnsgroup=wisconsin


all: install_os post_install

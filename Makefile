
HII=1
BASE=/Volumes/bootfs
OSIMAGE=images/2021-10-30-raspios-bullseye-arm64-lite.img
host_ip_string=${host_ip_override}
ifneq ($(host_ip_string),)
host_ip_string :=  "-e ansible_ssh_host=${host_ip_override}"
endif

install_os:
	echo ${OSIMAGE}
	echo time sudo dd if=${OSIMAGE} of=/dev/disk2 bs=1m conv=sync
	diskutil list

post:
	if [ -d ${BASE} ]; then \
		  ./post_install.sh;\
		fi

configure:
	@test -n "${hostlist}" || { echo "Error: hostlist is required (e.g., make configure hostlist=myhost newbie=192.168.1.100)"; exit 1; }
	@test -n "${newbie}" || { echo "Error: newbie (IP address) is required for initial stage-1 (e.g., make configure hostlist=myhost newbie=192.168.1.100)"; exit 1; }
	grep newbie hosts
	grep -i ${hostlist}	hosts
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=newbie -e ansible_ssh_host=${newbie} playbooks/initial-playbook-stage-1.yml || true
	# Allow SSH sessions and host key changes triggered by stage-1 to fully settle before running stage-2; 75s is empirically sufficient.
	echo "Sleeping 75 seconds for SSH to unwind before running stage-2 playbook"
	sleep 75
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-2.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-3.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-4.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/initial-playbook-stage-5.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/syslog-configure.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/datadog-install.yml
	@echo "Installing wireguard - make sure to restore from backup"
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/fix-locale.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/wireguard-install-simple.yml
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/internal_certs_update_endpoints.yml -e dnsgroup=${dnsgroup}
	ANSIBLE_HOST_KEY_CHECKING=False ansible -vv -b -m reboot ${hostlist} ${host_ip_string}
	#reboot for DNS to kick in / make sure everything comes up

backup-create:
	@grep -i ${hostlist} hosts
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/backup-services.yml

backup-fetch:
	@grep -i ${hostlist} hosts
	./scripts/backup-fetch.sh ${hostlist}

backup-restore:
	@grep -i ${hostlist} hosts
	./scripts/backup-restore.sh ${hostlist}

backup-restore-full:
	@grep -i ${hostlist} hosts
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=${hostlist} playbooks/restore-services.yml

all: install_os post_install

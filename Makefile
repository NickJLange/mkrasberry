
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

gcloud-credentials-stage:
	@echo "Copying local gcloud credentials to role files directory..."
	@# Verify credentials will be gitignored (check in mkrasberry_config submodule where files actually live)
	@cd mkrasberry_config && git check-ignore -q roles/role-install-gcloud/files/credentials.db 2>/dev/null || { \
		echo "Error: credential files are not git-ignored in mkrasberry_config. Add to mkrasberry_config/.gitignore before staging secrets."; \
		exit 1; }
	@mkdir -p roles/role-install-gcloud/files
	cp ~/.config/gcloud/credentials.db roles/role-install-gcloud/files/
	cp ~/.config/gcloud/access_tokens.db roles/role-install-gcloud/files/
	cp ~/.config/gcloud/active_config roles/role-install-gcloud/files/
	cp ~/.config/gcloud/configurations/config_default roles/role-install-gcloud/files/
	cp ~/.ssh/google_compute_engine roles/role-install-gcloud/files/
	cp ~/.ssh/google_compute_engine.pub roles/role-install-gcloud/files/
	@echo "Credentials and SSH keys staged. Run 'make gcloud-credentials-deploy hostlist=hostname' to deploy."

gcloud-credentials-deploy:
	@test -n "${hostlist}" || { echo "Error: hostlist is required"; exit 1; }
	@test -f roles/role-install-gcloud/files/credentials.db || { echo "Error: credentials.db not staged. Run 'make gcloud-credentials-stage' first"; exit 1; }
	@test -f roles/role-install-gcloud/files/access_tokens.db || { echo "Error: access_tokens.db not staged."; exit 1; }
	@test -f roles/role-install-gcloud/files/active_config || { echo "Error: active_config not staged."; exit 1; }
	@test -f roles/role-install-gcloud/files/config_default || { echo "Error: config_default not staged."; exit 1; }
	@test -f roles/role-install-gcloud/files/google_compute_engine || { echo "Error: google_compute_engine SSH key not staged."; exit 1; }
	@test -f roles/role-install-gcloud/files/google_compute_engine.pub || { echo "Error: google_compute_engine.pub not staged."; exit 1; }
	@grep -i ${hostlist} hosts
	ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook ${host_ip_string} -e hostlist=${hostlist} playbooks/gcloud-credentials-deploy.yml

all: install_os post_install

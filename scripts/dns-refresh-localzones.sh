#!/bin/bash
set -euo pipefail

# Wrapper script to refresh Unbound localzone DNS records for all
# nicklange.family subdomains and push them out to all resolvers.
#
# This uses the existing Ansible inventory (hosts) and the
# playbook playbooks/unbound-refresh-localzone.yml which imports
# the pihole.container role's unbound_localzone tasks.
#
# By default this targets the [pihole] group (all resolvers) and
# regenerates localzone configs for each dnsgroup below.

source .venv/bin/activate

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "${SCRIPT_DIR}")"
cd "${PROJECT_ROOT}"

# Ansible host group that contains all DNS resolvers
HOSTLIST="${1:-pihole}"

# dnsgroups corresponding to each geographic subdomain/region.
# Using the top-level region groups (newyork, wisconsin, miyagi)
# ensures ALL devices in that region (linux, osx, iot, misc, etc.)
# are included when generating local DNS records.
#
# newyork.nicklange.family   -> newyork
# wisconsin.nicklange.family -> wisconsin
# miyagi.nicklange.family    -> miyagi
DNS_GROUPS=(
  "newyork"
  "wisconsin"
  "miyagi"
)

echo "Using Ansible inventory at: ${PROJECT_ROOT}/hosts"
echo "Target resolver group (hostlist): ${HOSTLIST}"

for dnsgroup in "${DNS_GROUPS[@]}"; do
  echo "------------------------------------------------------------"
  echo "Refreshing DNS localzone for dnsgroup='${dnsgroup}'..."
  ANSIBLE_HOST_KEY_CHECKING=False \
    ansible-playbook \
      -e "hostlist=${HOSTLIST}" \
      -e "dnsgroup=${dnsgroup}" \
      playbooks/unbound-refresh-localzone.yml
  echo "Completed refresh for dnsgroup='${dnsgroup}'"
  echo
done

echo "All DNS localzone refreshes completed for nicklange.family subdomains."

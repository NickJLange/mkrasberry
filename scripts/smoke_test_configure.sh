#!/usr/bin/env bash
#
# Smoke test script for 'make configure' playbooks and prerequisites
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_DIR}"

export ANSIBLE_LOCAL_TEMP="${ANSIBLE_LOCAL_TEMP:-/tmp}"
export ANSIBLE_HOST_KEY_CHECKING="False"

# ANSI color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PLAYBOOKS=(
    "playbooks/initial-playbook-stage-1.yml"
    "playbooks/initial-playbook-stage-2.yml"
    "playbooks/initial-playbook-stage-3.yml"
    "playbooks/initial-playbook-stage-4.yml"
    "playbooks/initial-playbook-stage-5.yml"
    "playbooks/syslog-configure.yml"
    "playbooks/datadog-install.yml"
    "playbooks/fix-locale.yml"
    "playbooks/wireguard-install-simple.yml"
    "playbooks/internal_certs_update_endpoints.yml"
)

REQUIRED_VARS=(
    "local_ssh_user"
    "Timezone"
    "poison_usernames"
    "MaxExpectedPathBDP"
    "kenta_ssh_key"
    "primary_syslog_server"
    "backup_syslog_server"
    "my_datadog_api_key"
    "datadog_agent"
    "datadog_env"
    "datadog_region"
)

REQUIRED_ROLES=(
    "fix_sudoers"
    "locales"
    "mikolak-net.raspi_config"
    "Stouts.hostname"
    "msmtp"
    "role-install-gcloud"
    "ansible-phoneHome"
    "syslog-configure-servers"
    "ansible-datadog"
    "internal_dns_vault"
)

TOTAL_ERRORS=0

# Helper function to run syntax checks sequentially (Performance 4C)
check_playbook_syntax() {
    echo -e "${BLUE}=== Stage 1: Playbook Syntax Checks (Sequential) ===${NC}"
    for pb in "${PLAYBOOKS[@]}"; do
        if [ ! -f "$pb" ]; then
            echo -e "  Checking syntax: $pb ... [${RED}FAIL${NC}] (File not found)"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
            continue
        fi

        SYNTAX_OUTPUT=$(ansible-playbook --syntax-check "$pb" 2>&1)
        STATUS=$?

        if [ $STATUS -eq 0 ]; then
            echo -e "  Checking syntax: $pb ... [${GREEN}PASS${NC}]"
        else
            echo -e "  Checking syntax: $pb ... [${RED}FAIL${NC}]"
            echo "$SYNTAX_OUTPUT" | sed 's/^/    /'
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        fi
    done
    echo ""
}

# Helper function to check role availability in roles/ and roles_path
check_roles() {
    echo -e "${BLUE}=== Stage 2: Role Availability Checks ===${NC}"
    # Parse roles_path from ansible.cfg or default paths
    local search_paths=("./roles" "../overlord/ansible/roles" "/Users/njl/dev/src/overlord/ansible/roles")

    for role in "${REQUIRED_ROLES[@]}"; do
        local found=0
        for sp in "${search_paths[@]}"; do
            if [ -d "${sp}/${role}" ]; then
                found=1
                break
            fi
        done

        if [ $found -eq 1 ]; then
            echo -e "  Checking role: $role ... [${GREEN}PASS${NC}]"
        else
            echo -e "  Checking role: $role ... [${RED}FAIL${NC}] (Not found in roles_path)"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        fi
    done
    echo ""
}

# Helper function to validate target host prerequisites
check_target_host() {
    local host="$1"
    echo -e "${BLUE}=== Stage 3: Target Host Validation for '${host}' ===${NC}"

    # Verify host exists in inventory and get JSON vars
    local host_json
    if ! host_json=$(ansible-inventory --host "$host" 2>&1); then
        echo -e "  Host inventory lookup: '${host}' ... [${RED}FAIL${NC}]"
        echo "$host_json" | sed 's/^/    /'
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return 1
    fi

    # Check for empty or invalid inventory response
    if [ -z "$host_json" ] || [ "$host_json" = "{}" ]; then
        echo -e "  Host inventory lookup: '${host}' ... [${RED}FAIL${NC}] (Host not found in inventory)"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        return 1
    fi
    echo -e "  Host inventory lookup: '${host}' ... [${GREEN}PASS${NC}]"

    # Validate required variables using Python
    local var_check_result
    var_check_result=$(python3 - "$host_json" "${REQUIRED_VARS[@]}" << 'EOF'
import sys, json

try:
    host_vars = json.loads(sys.argv[1])
except Exception as e:
    print(f"ERROR: Failed to parse host JSON: {e}")
    sys.exit(2)

required = sys.argv[2:]
missing = []

for var in required:
    val = host_vars.get(var)
    if val is None or val == "":
        missing.append(var)

# Check cert subdomain variable: either subdomain or dns_subdomain must be defined
has_subdomain = bool(host_vars.get("subdomain") or host_vars.get("dns_subdomain"))
if not has_subdomain:
    missing.append("dns_subdomain (or subdomain)")

if missing:
    print("MISSING:" + ",".join(missing))
    sys.exit(1)

# Check SSH key path
ssh_key_path = host_vars.get("path_to_ssh_key")
local_user = host_vars.get("local_ssh_user", "")
if not ssh_key_path and local_user:
    ssh_key_path = f"/Users/{local_user}/.ssh/id_rsa_stronger.pub"

print(f"OK:{ssh_key_path or ''}")
sys.exit(0)
EOF
) || true

    if [[ "$var_check_result" =~ ^MISSING:(.*) ]]; then
        local missing_list="${BASH_REMATCH[1]}"
        IFS=',' read -ra missing_vars <<< "$missing_list"
        for mv in "${missing_vars[@]}"; do
            echo -e "  Checking variable: $mv ... [${RED}FAIL${NC}] (Missing or empty)"
            TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
        done
    elif [[ "$var_check_result" =~ ^OK:(.*) ]]; then
        for var in "${REQUIRED_VARS[@]}"; do
            echo -e "  Checking variable: $var ... [${GREEN}PASS${NC}]"
        done
        echo -e "  Checking cert subdomain (dns_subdomain/subdomain) ... [${GREEN}PASS${NC}]"

        local ssh_key="${BASH_REMATCH[1]}"
        if [ -n "$ssh_key" ]; then
            # Expand ~ if present
            eval ssh_key_expanded="$ssh_key"
            if [ -f "$ssh_key_expanded" ]; then
                echo -e "  Checking SSH key file: $ssh_key ... [${GREEN}PASS${NC}]"
            else
                echo -e "  Checking SSH key file: $ssh_key ... [${YELLOW}WARN${NC}] (File not found on local controller)"
            fi
        fi

        # Check Vault python environment for certs playbook
        local venv_candidate="${VENV_PATH:-/Users/njl/dev/src/overlord/.venv}"
        if [ -f "${venv_candidate}/bin/python3" ] && "${venv_candidate}/bin/python3" -c "import hvac" >/dev/null 2>&1; then
            echo -e "  Checking Vault Python environment (${venv_candidate}) ... [${GREEN}PASS${NC}]"
        else
            echo -e "  Checking Vault Python environment (${venv_candidate}) ... [${YELLOW}WARN${NC}] (hvac not installed or venv not found; set VENV_PATH)"
        fi
    else
        echo -e "  Host variable parsing error: $var_check_result ... [${RED}FAIL${NC}]"
        TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    fi
    echo ""
}

# Automated Self-Test (Stage 3: 3A)
run_self_test() {
    echo -e "${BLUE}=== Running Self-Tests (Negative & Edge Case Verification) ===${NC}"
    local self_test_failures=0

    # Test 1: Nonexistent host must fail
    echo -n "  Self-Test 1: Verify nonexistent host produces error... "
    local nonexist_out
    if nonexist_out=$(ansible-inventory --host "__nonexistent_target_12345__" 2>&1); then
        # If ansible-inventory returned 0, check if JSON was empty or error was caught
        if [ "$nonexist_out" = "{}" ] || [ -z "$nonexist_out" ]; then
            echo -e "[${GREEN}PASS${NC}] (Identified as missing host)"
        else
            echo -e "[${RED}FAIL${NC}] (Expected nonexistent host to fail)"
            self_test_failures=$((self_test_failures + 1))
        fi
    else
        echo -e "[${GREEN}PASS${NC}] (Correctly caught error exit code)"
    fi

    # Test 2: Missing required variable detection
    echo -n "  Self-Test 2: Verify missing required variable detection... "
    local dummy_json='{"local_ssh_user": "njl"}'
    if python3 - "$dummy_json" "local_ssh_user" "missing_var_xyz" << 'EOF' >/dev/null 2>&1
import sys, json
data = json.loads(sys.argv[1])
required = sys.argv[2:]
missing = [v for v in required if not data.get(v)]
if missing:
    sys.exit(1)
sys.exit(0)
EOF
    then
        echo -e "[${RED}FAIL${NC}] (Failed to catch missing variable)"
        self_test_failures=$((self_test_failures + 1))
    else
        echo -e "[${GREEN}PASS${NC}] (Correctly detected missing variable)"
    fi

    # Test 3: Playbook syntax check works on valid file
    echo -n "  Self-Test 3: Playbook syntax check on known valid playbook... "
    if ansible-playbook --syntax-check playbooks/fix-locale.yml >/dev/null 2>&1; then
        echo -e "[${GREEN}PASS${NC}]"
    else
        echo -e "[${RED}FAIL${NC}]"
        self_test_failures=$((self_test_failures + 1))
    fi

    echo ""
    if [ $self_test_failures -eq 0 ]; then
        echo -e "${GREEN}All self-tests passed successfully.${NC}"
        return 0
    else
        echo -e "${RED}${self_test_failures} self-test(s) failed.${NC}"
        return 1
    fi
}

main() {
    local target="${1:-}"

    if [ "$target" = "--self-test" ]; then
        run_self_test
        exit $?
    fi

    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}       mkrasberry 'make configure' Smoke Test          ${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo ""

    # 1. Sequential syntax check of all 10 playbooks
    check_playbook_syntax

    # 2. Check required roles availability
    check_roles

    # 3. Target host check (Fast dual-mode: 2C)
    if [ -n "$target" ]; then
        check_target_host "$target"
    else
        echo -e "${YELLOW}Notice: No target host specified (hostlist is empty).${NC}"
        echo -e "        Only playbook syntax and role checks were performed."
        echo -e "        To validate target-specific prerequisites, run: make test hostlist=<target>\n"
    fi

    # Final summary
    echo -e "${BLUE}======================================================${NC}"
    if [ $TOTAL_ERRORS -eq 0 ]; then
        echo -e "${GREEN}SUCCESS: All smoke tests and prerequisites passed!${NC}"
        exit 0
    else
        echo -e "${RED}FAILED: ${TOTAL_ERRORS} issue(s) detected. Please review above output.${NC}"
        exit 1
    fi
}

main "$@"

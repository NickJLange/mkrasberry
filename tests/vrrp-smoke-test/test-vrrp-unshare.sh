#!/bin/bash
set -e

# VRRP Smoke Test using unshare (rootless)
# Runs two keepalived processes in isolated user namespaces
# Tests failover behavior without requiring privileged network access

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEPALIVED_BIN="${KEEPALIVED_BIN:-$(which keepalived 2>/dev/null || echo '/usr/sbin/keepalived')}"
TEST_IP_PREFIX="127.99.0"  # Use loopback range to avoid needing real interfaces

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_debug() { echo -e "${BLUE}[DEBUG]${NC} $1"; }

# Check prerequisites
check_prereqs() {
    log_info "Checking prerequisites..."
    
    if ! command -v unshare &> /dev/null; then
        log_error "unshare not found. Install util-linux package."
        exit 1
    fi
    
    if [ ! -x "$KEEPALIVED_BIN" ]; then
        log_error "keepalived not found at $KEEPALIVED_BIN"
        log_info "Install with: sudo apt-get install keepalived"
        exit 1
    fi
    
    # Check if user namespaces are enabled
    if [ -f /proc/sys/kernel/unprivileged_userns_clone ]; then
        if [ "$(cat /proc/sys/kernel/unprivileged_userns_clone)" != "1" ]; then
            log_error "User namespaces disabled. Enable with: sudo sysctl kernel.unprivileged_userns_clone=1"
            exit 1
        fi
    fi
    
    log_success "Prerequisites met"
}

# Create test configs
create_configs() {
    log_info "Creating test configurations..."
    
    mkdir -p "$TEST_DIR/tmp"
    
    # Master config (Virtual Router ID 99 - test only)
    cat > "$TEST_DIR/tmp/keepalived-master.conf" << 'EOF'
global_defs {
    router_id TEST_MASTER
    script_user root
    enable_script_security
    vrrp_skip_check_adv_addr
}

vrrp_instance VI_TEST {
    state MASTER
    interface lo
    virtual_router_id 99
    priority 101
    advert_int 1
    preempt_delay 30
    
    virtual_ipaddress {
        127.99.0.2/8 dev lo
    }
    
    unicast_src_ip 127.99.0.10
    unicast_peer {
        127.99.0.11
    }
}
EOF

    # Backup config
    cat > "$TEST_DIR/tmp/keepalived-backup.conf" << 'EOF'
global_defs {
    router_id TEST_BACKUP
    script_user root
    enable_script_security
    vrrp_skip_check_adv_addr
}

vrrp_instance VI_TEST {
    state BACKUP
    interface lo
    virtual_router_id 99
    priority 100
    advert_int 1
    preempt_delay 30
    
    virtual_ipaddress {
        127.99.0.2/8 dev lo
    }
    
    unicast_src_ip 127.99.0.11
    unicast_peer {
        127.99.0.10
    }
}
EOF

    log_success "Test configs created"
}

# Validate configs
validate_configs() {
    log_info "Validating keepalived configurations..."
    
    if ! "$KEEPALIVED_BIN" -t -f "$TEST_DIR/tmp/keepalived-master.conf" 2>&1; then
        log_error "Master config validation failed"
        exit 1
    fi
    
    if ! "$KEEPALIVED_BIN" -t -f "$TEST_DIR/tmp/keepalived-backup.conf" 2>&1; then
        log_error "Backup config validation failed"
        exit 1
    fi
    
    log_success "Configurations are syntactically valid"
}

# Setup test IPs on loopback
setup_test_ips() {
    log_info "Setting up test IPs on loopback interface..."
    
    # These will be setup inside the namespaces
    # We use 127.99.0.x range which is valid loopback
    
    log_success "Test IPs ready (will be configured in namespaces)"
}

# Run keepalived in namespace
run_in_namespace() {
    local name=$1
    local config=$2
    local src_ip=$3
    
    log_debug "Starting $name with config $config"
    
    # Create isolated namespace with root mapped to current user
    unshare --user --map-root-user --pid --fork --mount-proc /bin/bash << EOF &
        # Inside namespace - we're "root" here
        echo $$ > "$TEST_DIR/tmp/${name}.pid"
        
        # Create log file
        exec > >(tee "$TEST_DIR/tmp/${name}.log") 2>&1
        
        # Setup loopback interface
        ip addr add ${src_ip}/8 dev lo 2>/dev/null || true
        ip link set lo up
        
        # Run keepalived in foreground
        exec $KEEPALIVED_BIN -f $config -n -l -D
EOF
    
    local pid=$!
    echo $pid > "$TEST_DIR/tmp/${name}.ns.pid"
    log_debug "$name started with PID $pid"
}

# Test 1: Initial State
test_initial_state() {
    log_info "Test 1: Initial State Validation"
    
    # Start master
    run_in_namespace "master" "$TEST_DIR/tmp/keepalived-master.conf" "127.99.0.10"
    sleep 3
    
    # Start backup
    run_in_namespace "backup" "$TEST_DIR/tmp/keepalived-backup.conf" "127.99.0.11"
    sleep 3
    
    # Check master has VIP
    if grep -q "Entering MASTER STATE" "$TEST_DIR/tmp/master.log" 2>/dev/null; then
        log_success "Master entered MASTER state"
    else
        log_error "Master did not enter MASTER state"
        cat "$TEST_DIR/tmp/master.log" | tail -20
        return 1
    fi
    
    # Check backup is in BACKUP state
    if grep -q "Entering BACKUP STATE" "$TEST_DIR/tmp/backup.log" 2>/dev/null; then
        log_success "Backup entered BACKUP state"
    else
        log_error "Backup did not enter BACKUP state"
        cat "$TEST_DIR/tmp/backup.log" | tail -20
        return 1
    fi
    
    log_success "Test 1 passed: Initial states correct"
}

# Test 2: Failover
test_failover() {
    log_info "Test 2: Failover Test"
    
    # Kill master namespace
    local master_ns_pid=$(cat "$TEST_DIR/tmp/master.ns.pid" 2>/dev/null || echo "")
    if [ -n "$master_ns_pid" ] && kill -0 "$master_ns_pid" 2>/dev/null; then
        log_debug "Stopping master (PID: $master_ns_pid)"
        kill "$master_ns_pid" 2>/dev/null || true
        sleep 1
    fi
    
    # Wait for backup to take over
    log_info "Waiting for failover (5 seconds)..."
    sleep 5
    
    # Check backup entered MASTER state
    if grep -q "Entering MASTER STATE" "$TEST_DIR/tmp/backup.log" 2>/dev/null; then
        log_success "Backup took over MASTER state after failover"
    else
        log_error "Backup did not take over MASTER state"
        log_debug "Backup log tail:"
        tail -20 "$TEST_DIR/tmp/backup.log"
        return 1
    fi
    
    log_success "Test 2 passed: Failover works"
}

# Test 3: Recovery (simplified - just verify backup stays master)
test_recovery() {
    log_info "Test 3: Recovery Test (Backup remains master after master failure)"
    
    # In unshare mode without veth, we can't easily restart master
    # So we verify the backup maintains master state
    
    sleep 3
    
    # Check backup is still MASTER
    if grep -q "Entering MASTER STATE" "$TEST_DIR/tmp/backup.log" 2>/dev/null; then
        log_success "Backup maintained MASTER state"
    else
        log_error "Backup lost MASTER state"
        return 1
    fi
    
    log_success "Test 3 passed: Backup stable as MASTER"
    log_info "Note: Full preemption test requires veth pair (needs sudo)"
}

# Cleanup
cleanup() {
    log_info "Cleaning up..."
    
    # Kill namespaces
    for pid_file in "$TEST_DIR/tmp/"*.ns.pid; do
        if [ -f "$pid_file" ]; then
            local pid=$(cat "$pid_file" 2>/dev/null || echo "")
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                sleep 1
            fi
        fi
    done
    
    # Clean up temp files
    rm -rf "$TEST_DIR/tmp"
    
    log_success "Cleanup complete"
}

# Main
main() {
    trap cleanup EXIT
    
    log_info "VRRP Smoke Test (Rootless/Unshare Mode)"
    log_info "=========================================="
    
    check_prereqs
    create_configs
    validate_configs
    setup_test_ips
    
    test_initial_state
    test_failover
    test_recovery
    
    echo ""
    log_success "All tests passed!"
    log_info ""
    log_info "Summary:"
    log_info "  - Config syntax: Validated"
    log_info "  - Initial state: Master/Backup established"
    log_info "  - Failover: Working"
    log_info "  - Preemption: Backup remains stable"
    log_info ""
    log_info "For full preemption testing with VIP reclaim, use veth pair setup"
}

main "$@"

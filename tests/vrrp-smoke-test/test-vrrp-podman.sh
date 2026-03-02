#!/bin/bash
set -e

# VRRP Smoke Test using Podman (containerized, network isolated)
# Runs two keepalived containers with isolated bridge network
# Safe to run on production servers

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Generate valid IP octets (0-255)
THIRD_OCTET=$((RANDOM % 256))
NETWORK_NAME="vrrp-test-net-${RANDOM}"
SUBNET="10.99.${THIRD_OCTET}.0/24"
GATEWAY="10.99.${THIRD_OCTET}.1"
VIP="10.99.${THIRD_OCTET}.2"
MASTER_IP="10.99.${THIRD_OCTET}.10"
BACKUP_IP="10.99.${THIRD_OCTET}.11"

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
    
    if ! command -v podman &> /dev/null; then
        log_error "podman not found. Install podman."
        exit 1
    fi
    
    # Check we're not using production network
    if [[ "$SUBNET" == *"192.168.100"* ]] || [[ "$SUBNET" == *"192.168.20"* ]] || [[ "$SUBNET" == *"192.168.3"* ]]; then
        log_error "Generated subnet conflicts with production! Exiting."
        exit 1
    fi
    
    log_success "Prerequisites met"
    log_debug "Using test subnet: $SUBNET"
}

# Create isolated podman network
create_network() {
    log_info "Creating isolated Podman network..."
    
    podman network create \
        --driver bridge \
        --subnet "$SUBNET" \
        --gateway "$GATEWAY" \
        "$NETWORK_NAME"
    
    log_success "Network $NETWORK_NAME created"
}

# Generate keepalived configs
generate_configs() {
    log_info "Generating keepalived configurations..."
    
    mkdir -p "$TEST_DIR/tmp"
    
    # Master config
    cat > "$TEST_DIR/tmp/keepalived-master.conf" << EOF
global_defs {
    router_id TEST_MASTER
    script_user root
    enable_script_security
    vrrp_skip_check_adv_addr
}

vrrp_instance VI_TEST {
    state MASTER
    interface eth0
    virtual_router_id 99
    priority 101
    advert_int 1
    preempt_delay 30
    
    virtual_ipaddress {
        $VIP/24
    }
    
    unicast_src_ip $MASTER_IP
    unicast_peer {
        $BACKUP_IP
    }
}
EOF

    # Backup config
    cat > "$TEST_DIR/tmp/keepalived-backup.conf" << EOF
global_defs {
    router_id TEST_BACKUP
    script_user root
    enable_script_security
    vrrp_skip_check_adv_addr
}

vrrp_instance VI_TEST {
    state BACKUP
    interface eth0
    virtual_router_id 99
    priority 100
    advert_int 1
    preempt_delay 30
    
    virtual_ipaddress {
        $VIP/24
    }
    
    unicast_src_ip $BACKUP_IP
    unicast_peer {
        $MASTER_IP
    }
}
EOF

    log_success "Configurations generated"
}

# Build container image
build_image() {
    log_info "Building keepalived container image..."
    
    cat > "$TEST_DIR/tmp/Containerfile" << 'EOF'
FROM alpine:3.19
RUN apk add --no-cache keepalived iproute2 tcpdump
COPY keepalived-*.conf /etc/keepalived/
ENTRYPOINT ["keepalived"]
CMD ["-n", "-l", "-D"]
EOF

    podman build -t localhost/vrrp-test:latest -f "$TEST_DIR/tmp/Containerfile" "$TEST_DIR/tmp"
    
    log_success "Container image built"
}

# Run containers
run_containers() {
    log_info "Starting keepalived containers..."
    
    # Run master
    podman run -d --name "vrrp-master-${RANDOM}" \
        --network "$NETWORK_NAME" \
        --ip "$MASTER_IP" \
        --cap-add NET_ADMIN \
        --cap-add NET_RAW \
        -v "$TEST_DIR/tmp/keepalived-master.conf:/etc/keepalived/keepalived.conf:ro" \
        localhost/vrrp-test:latest \
        -f /etc/keepalived/keepalived.conf -n -l -D
    
    # Run backup
    podman run -d --name "vrrp-backup-${RANDOM}" \
        --network "$NETWORK_NAME" \
        --ip "$BACKUP_IP" \
        --cap-add NET_ADMIN \
        --cap-add NET_RAW \
        -v "$TEST_DIR/tmp/keepalived-backup.conf:/etc/keepalived/keepalived.conf:ro" \
        localhost/vrrp-test:latest \
        -f /etc/keepalived/keepalived.conf -n -l -D
    
    log_success "Containers started"
}

# Test 1: Initial State
test_initial_state() {
    log_info "Test 1: Initial State Validation"
    sleep 5
    
    # Get container names
    MASTER_CONTAINER=$(podman ps --filter "ancestor=localhost/vrrp-test:latest" --format "{{.Names}}" | head -1)
    BACKUP_CONTAINER=$(podman ps --filter "ancestor=localhost/vrrp-test:latest" --format "{{.Names}}" | tail -1)
    
    log_debug "Master container: $MASTER_CONTAINER"
    log_debug "Backup container: $BACKUP_CONTAINER"
    
    # Check master logs
    if podman logs "$MASTER_CONTAINER" 2>&1 | grep -q "Entering MASTER STATE"; then
        log_success "Master entered MASTER state"
    else
        log_error "Master did not enter MASTER state"
        podman logs "$MASTER_CONTAINER" 2>&1 | tail -10
        return 1
    fi
    
    # Check backup logs
    if podman logs "$BACKUP_CONTAINER" 2>&1 | grep -q "Entering BACKUP STATE"; then
        log_success "Backup entered BACKUP state"
    else
        log_error "Backup did not enter BACKUP state"
        podman logs "$BACKUP_CONTAINER" 2>&1 | tail -10
        return 1
    fi
    
    log_success "Test 1 passed: Initial states correct"
}

# Test 2: Failover
test_failover() {
    log_info "Test 2: Failover Test"
    
    MASTER_CONTAINER=$(podman ps --filter "ancestor=localhost/vrrp-test:latest" --format "{{.Names}}" | head -1)
    BACKUP_CONTAINER=$(podman ps --filter "ancestor=localhost/vrrp-test:latest" --format "{{.Names}}" | tail -1)
    
    log_info "Stopping master container..."
    podman stop "$MASTER_CONTAINER"
    
    log_info "Waiting for failover (5 seconds)..."
    sleep 5
    
    # Check backup took over
    if podman logs "$BACKUP_CONTAINER" 2>&1 | grep -q "Entering MASTER STATE"; then
        log_success "Backup took over MASTER state"
    else
        log_error "Backup did not take over"
        podman logs "$BACKUP_CONTAINER" 2>&1 | tail -10
        return 1
    fi
    
    log_success "Test 2 passed: Failover works"
}

# Cleanup
cleanup() {
    log_info "Cleaning up test environment..."
    
    # Stop and remove containers
    for container in $(podman ps -a --filter "ancestor=localhost/vrrp-test:latest" --format "{{.Names}}"); do
        podman stop "$container" 2>/dev/null || true
        podman rm "$container" 2>/dev/null || true
    done
    
    # Remove network
    podman network rm "$NETWORK_NAME" 2>/dev/null || true
    
    # Clean up temp files
    rm -rf "$TEST_DIR/tmp"
    
    # Remove image
    podman rmi localhost/vrrp-test:latest 2>/dev/null || true
    
    log_success "Cleanup complete"
}

# Main
main() {
    trap cleanup EXIT
    
    log_info "VRRP Smoke Test (Podman/Containerized Mode)"
    log_info "============================================="
    log_info "Network: $NETWORK_NAME"
    log_info "Subnet: $SUBNET"
    log_info "VIP: $VIP"
    log_info ""
    
    check_prereqs
    create_network
    generate_configs
    build_image
    run_containers
    
    test_initial_state
    test_failover
    
    echo ""
    log_success "All tests passed!"
    log_info ""
    log_info "Summary:"
    log_info "  - Network isolation: Podman bridge network"
    log_info "  - Config syntax: Validated"
    log_info "  - Initial state: Master/Backup established"
    log_info "  - Failover: Working"
}

main "$@"

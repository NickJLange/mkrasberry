# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

mkrasberry is a Raspberry Pi infrastructure automation project that uses Ansible to deploy and manage a distributed network of Raspberry Pi devices across multiple geographic locations (New York, Wisconsin, Japan/Miyagi). The project creates a homogeneous, containerized infrastructure running services like DNS filtering, home automation, VPN, monitoring, and logging.

## Architecture

The project follows an **Infrastructure as Code (IaC)** approach with:
- **Multi-stage deployment**: Device initialization through 5 sequential playbook stages
- **Container-first architecture**: All services run in Podman containers
- **Geographic distribution**: Three primary locations with centralized management
- **Service-oriented design**: Modular Ansible roles for different services
- **Centralized monitoring**: Datadog and Telegraf integration

## Key Commands

### Image Building and Device Provisioning
```bash
make build_image                    # Build customized Raspberry Pi OS images
make install_os TARGETDISK=disk2    # Flash OS images to SD cards
make post                          # Post-installation configuration
make configure hostlist=hostname    # Full device configuration pipeline
make configure_dns hostlist=hostname # DNS-specific configuration
```

### Manual Ansible Execution
```bash
# Stage-by-stage deployment
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=hostname playbooks/initial-playbook-stage-1.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=hostname playbooks/initial-playbook-stage-2.yml
# ... continues through stage-5

# Service-specific deployments
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=hostname playbooks/pihole-install.yml
ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=hostname playbooks/syslog-container.yml
```

### Host IP Override
Use `host_ip_override` variable to target specific IP addresses:
```bash
make configure hostlist=hostname host_ip_override=192.168.1.100
```

## Directory Structure

- **`playbooks/`**: Main Ansible playbooks for different deployment scenarios
  - `initial-playbook-stage-*.yml`: Multi-stage device initialization
  - Service-specific playbooks (pihole, homeassistant, wireguard, etc.)
- **`roles/`**: Reusable Ansible roles organized by service type
  - Container roles: `*.container` (pihole.container, homeassistant.container, etc.)
  - Infrastructure roles: wireguard, telegraf, security components
  - System roles: podman setup, locales, monitoring
- **`group_vars/` & `host_vars/`**: Ansible inventory configuration by geography and service
- **`images/`**: Base Raspberry Pi OS images
- **`build_images/`**: Output directory for customized OS images

## Container Role Architecture

Container roles follow a standardized pattern:
- **Podman validation**: Check for Podman installation
- **User management**: Create service users and groups
- **Installation tasks**: Container deployment and configuration
- **Service templates**: Systemd service files for container management
- **Configuration templates**: Application-specific config files

### Example Container Role Structure
```
roles/service.container/
├── tasks/
│   ├── main.yml        # Entry point with validation
│   ├── install.yml     # Container deployment
│   └── config.yml      # Configuration management
├── templates/
│   ├── container.service.j2  # Systemd service template
│   └── config.conf.j2        # Application config template
└── defaults/main.yml   # Default variables
```

## Geographic Network Architecture

- **New York** (192.168.100.x): Primary location with full service stack
- **Wisconsin** (192.168.20.x): Secondary location
- **Japan/Miyagi** (192.168.3.x): Remote location

## Key Services Deployed

- **Pi-hole**: DNS filtering and ad blocking
- **Home Assistant**: Home automation platform
- **WireGuard**: VPN connectivity
- **Node-RED**: IoT flow programming
- **Telegraf**: Metrics collection
- **Vault**: Secrets management
- **Syslog**: Centralized logging

## Development Notes

- **No formal testing framework**: Testing is primarily manual/integration-based
- **Podman over Docker**: All containerization uses Podman
- **SSH agent dependency**: Some operations require ssh-agent to be running
- **Multi-stage initialization**: Device setup requires sequential playbook execution
- **IP override capability**: Use `host_ip_override` for targeting specific addresses during setup

## Known Issues

From README.md:
- TODO: Use `hosts: "{{ansibleTarget}}"` from CLI with `-e` instead of hardcoded targets
- TODO: Implement ssh-agent on run

## Common Patterns

When working with container roles:
1. Always validate Podman installation first
2. Use standardized user/group creation patterns
3. Follow the template structure for systemd services
4. Implement proper variable validation in main.yml
5. Use consistent naming conventions: `container_*` variables for generic settings, service-specific variables for application config
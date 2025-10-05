# GEMINI.md

This document guides developers and AI assistants in understanding and working with the `mkrasberry` repository.

## Project Overview

`mkrasberry` is an Infrastructure as Code (IaC) project for automating the setup and management of a distributed network of Raspberry Pi devices. It uses Ansible to deploy containerized services across multiple geographic locations, creating a consistent and centrally managed infrastructure.

## Core Architecture

*   **Ansible Driven**: Configuration is managed entirely by Ansible playbooks and roles.
*   **Containerized Services**: All applications run in Podman containers for isolation and consistency.
*   **Multi-Stage Deployment**: New devices are provisioned through a sequence of five Ansible playbooks (`initial-playbook-stage-1.yml` through `stage-5.yml`).
*   **Geographic Distribution**: The network is designed for multiple locations, with specific configurations managed in `group_vars/`.
*   **Modular Roles**: Functionality is broken down into reusable Ansible roles, especially for container deployments (`*.container`).

## Key Commands & Workflows

The `Makefile` provides the primary interface for common tasks.

*   **Build a custom OS image**:
    ```bash
    make build_image
    ```
*   **Flash an OS image to an SD card** (e.g., to `/dev/disk2`):
    ```bash
    make install_os TARGETDISK=disk2
    ```
*   **Run the full configuration pipeline on a host**:
    ```bash
    make configure hostlist=hostname
    ```
*   **Target a host with a specific IP** (useful for initial setup):
    ```bash
    make configure hostlist=hostname host_ip_override=192.168.1.100
    ```
*   **Run a specific playbook manually**:
    ```bash
    ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -e hostlist=hostname playbooks/pihole-install.yml
    ```

## Directory Structure

*   `playbooks/`: Contains the main Ansible playbooks for orchestrating deployments.
    *   `initial-playbook-stage-*.yml`: For sequential device provisioning.
    *   Service-specific playbooks (`pihole-install.yml`, `home-assistant-install.yml`, etc.).
*   `roles/`: Houses modular Ansible roles.
    *   `*.container/`: Standardized roles for deploying services in Podman containers.
*   `mkrasberry_config/`: Contains Ansible inventory, including:
    *   `hosts`: The main inventory file.
    *   `group_vars/`: Variables scoped to geographic locations or service groups.
    *   `host_vars/`: Variables specific to individual hosts.
*   `build_images/`: The output directory for OS images created by `make build_image`.

## Container Role Convention

Container roles (`roles/*.container`) follow a standard structure:

*   **`tasks/main.yml`**: Entrypoint that validates Podman is installed and includes other tasks.
*   **`tasks/install.yml`**: Handles Podman container creation and deployment.
*   **`tasks/config.yml`**: Manages application configuration inside the container.
*   **`templates/*.service.j2`**: A Jinja2 template for the systemd service that manages the container.
*   **`defaults/main.yml`**: Default variables for the role.

## Development Notes

*   **Primary Tooling**: Use `make` for all standard workflows.
*   **Containerization**: The project exclusively uses Podman, not Docker.
*   **Testing**: There is no formal automated testing suite. Testing is performed manually through integration and deployment verification.
*   **FIXME**: The `README.md` notes that playbooks should be updated to use a dynamic `ansibleTarget` variable instead of hardcoded host references.

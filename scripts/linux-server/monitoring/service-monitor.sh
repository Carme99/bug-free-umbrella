#!/bin/bash

#############################################################################
# Service Monitoring Script
#
# Description: Monitor critical system services and optionally restart failed ones
# Compatible: Ubuntu Server 20.04+, Rocky Linux 8.x/9.x
# Requirements: Root or sudo privileges
#
# Usage: sudo ./service-monitor.sh [options]
# Options:
#   -h, --help       Show help message
#   -r, --restart    Automatically restart failed services
#   -c, --config     Path to config file with service list
#
# Exit Codes:
#   0 - All services running
#   1 - One or more services failed
#   2 - Critical error
#############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Settings
AUTO_RESTART=false
CONFIG_FILE=""
EXIT_CODE=0

# Default critical services (will be populated based on distribution)
CRITICAL_SERVICES=()

#############################################################################
# Functions
#############################################################################

print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
    EXIT_CODE=1
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

show_help() {
    cat << EOF
Service Monitoring Script

Usage: sudo $0 [options]

Options:
    -h, --help       Show this help message
    -r, --restart    Automatically restart failed services
    -c, --config     Path to config file with custom service list

Description:
    Monitors critical system services and reports their status.
    Can optionally attempt to restart failed services.

    Default monitored services vary by distribution:

    Ubuntu: sshd, cron, systemd-resolved, ufw
    Rocky Linux: sshd, crond, firewalld, chronyd

Exit Codes:
    0 - All services running
    1 - One or more services failed
    2 - Critical error

Examples:
    sudo $0                     # Monitor services
    sudo $0 -r                  # Monitor and auto-restart failed
    sudo $0 -c /etc/services    # Use custom service list

Config File Format:
    One service name per line, e.g.:
    sshd
    nginx
    mysql
    postgresql

EOF
    exit 0
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}ERROR: This script must be run as root or with sudo${NC}"
        exit 2
    fi
}

detect_distribution() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        DISTRO="unknown"
    fi
}

load_default_services() {
    # Load default critical services based on distribution
    if [ "$DISTRO" = "ubuntu" ]; then
        CRITICAL_SERVICES=("ssh" "cron" "systemd-resolved")

        # Check if UFW is installed
        if systemctl list-unit-files | grep -q "^ufw.service"; then
            CRITICAL_SERVICES+=("ufw")
        fi

    elif [ "$DISTRO" = "rocky" ]; then
        CRITICAL_SERVICES=("sshd" "crond" "chronyd")

        # Check if firewalld is installed
        if systemctl list-unit-files | grep -q "^firewalld.service"; then
            CRITICAL_SERVICES+=("firewalld")
        fi
    else
        # Generic services for unknown distros
        CRITICAL_SERVICES=("sshd" "cron")
    fi
}

load_custom_services() {
    if [ -n "$CONFIG_FILE" ]; then
        if [ -f "$CONFIG_FILE" ]; then
            print_info "Loading services from: $CONFIG_FILE"
            CRITICAL_SERVICES=()
            while IFS= read -r line; do
                # Skip empty lines and comments
                [[ "$line" =~ ^[[:space:]]*$ ]] && continue
                [[ "$line" =~ ^[[:space:]]*# ]] && continue
                CRITICAL_SERVICES+=("$line")
            done < "$CONFIG_FILE"
        else
            echo -e "${RED}ERROR: Config file not found: $CONFIG_FILE${NC}"
            exit 2
        fi
    fi
}

check_service_status() {
    local service=$1

    # Try to find the service (handle both .service suffix and without)
    local service_name="$service"
    if ! systemctl list-unit-files | grep -q "^${service}.service"; then
        # Try common variations
        if systemctl list-unit-files | grep -q "^${service}d.service"; then
            service_name="${service}d"
        fi
    fi

    # Check if service exists
    if ! systemctl list-unit-files | grep -q "^${service_name}.service"; then
        print_info "Service '$service' not found/installed"
        return 0
    fi

    # Check if service is active
    if systemctl is-active --quiet "$service_name"; then
        print_success "$service_name is running"

        # Show additional info if enabled
        local enabled_status=$(systemctl is-enabled "$service_name" 2>/dev/null || echo "unknown")
        echo "  Status: active | Enabled: $enabled_status"

        # Show uptime
        local start_time=$(systemctl show "$service_name" --property=ActiveEnterTimestamp --value)
        if [ -n "$start_time" ]; then
            echo "  Started: $start_time"
        fi

        return 0
    else
        print_error "$service_name is NOT running"

        # Get failure reason
        local status_output=$(systemctl status "$service_name" --no-pager -l 2>&1 | head -10)
        echo "  Status details:"
        echo "$status_output" | grep -E "(Active:|Main PID:|Loaded:)" | sed 's/^/    /'

        # Attempt restart if enabled
        if [ "$AUTO_RESTART" = true ]; then
            print_info "Attempting to restart $service_name..."
            if systemctl restart "$service_name" 2>/dev/null; then
                sleep 2
                if systemctl is-active --quiet "$service_name"; then
                    print_success "Successfully restarted $service_name"
                    EXIT_CODE=0
                else
                    print_error "Failed to restart $service_name"
                fi
            else
                print_error "Restart command failed for $service_name"
            fi
        fi

        return 1
    fi
}

check_failed_services() {
    print_header "Failed Services Check"

    # List all failed services
    local failed_count=$(systemctl --failed --no-pager --no-legend | wc -l)

    if [ "$failed_count" -eq 0 ]; then
        print_success "No failed services detected"
    else
        print_warning "$failed_count failed services detected:"
        echo ""
        systemctl --failed --no-pager | head -20
    fi

    echo ""
}

monitor_services() {
    print_header "Service Status Monitoring"

    echo "Monitored services: ${#CRITICAL_SERVICES[@]}"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    for service in "${CRITICAL_SERVICES[@]}"; do
        check_service_status "$service"
        echo ""
    done
}

show_service_logs() {
    print_header "Recent Service Logs (Failed Services)"

    for service in "${CRITICAL_SERVICES[@]}"; do
        # Check if service exists and is failed
        if systemctl list-unit-files | grep -q "^${service}.service"; then
            if ! systemctl is-active --quiet "$service"; then
                echo -e "${YELLOW}Logs for $service:${NC}"
                journalctl -u "$service" --no-pager -n 10 --since "1 hour ago" 2>/dev/null || echo "  No recent logs"
                echo ""
            fi
        fi
    done
}

generate_summary() {
    print_header "Monitoring Summary"

    case $EXIT_CODE in
        0)
            echo -e "${GREEN}Status: OK${NC}"
            echo "All monitored services are running normally"
            ;;
        1)
            echo -e "${RED}Status: FAILED${NC}"
            echo "One or more services are not running"
            echo ""
            if [ "$AUTO_RESTART" = false ]; then
                echo "Recommendation: Run with -r flag to auto-restart failed services"
                echo "Or manually investigate and restart:"
                for service in "${CRITICAL_SERVICES[@]}"; do
                    if systemctl list-unit-files | grep -q "^${service}.service"; then
                        if ! systemctl is-active --quiet "$service"; then
                            echo "  sudo systemctl restart $service"
                        fi
                    fi
                done
            fi
            ;;
        2)
            echo -e "${RED}Status: ERROR${NC}"
            echo "Critical error occurred during monitoring"
            ;;
    esac

    echo ""
}

#############################################################################
# Main
#############################################################################

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -r|--restart)
                AUTO_RESTART=true
                shift
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 2
                ;;
        esac
    done

    # Check root
    check_root

    # Detect distribution
    detect_distribution

    # Load services
    if [ -n "$CONFIG_FILE" ]; then
        load_custom_services
    else
        load_default_services
    fi

    # Run monitoring
    echo ""
    print_header "Linux Service Monitor"
    echo "Distribution: $DISTRO"
    echo "Auto-restart: $AUTO_RESTART"
    echo ""

    monitor_services
    check_failed_services

    # Show logs only if there are failures
    if [ $EXIT_CODE -ne 0 ]; then
        show_service_logs
    fi

    generate_summary

    exit $EXIT_CODE
}

# Run main
main "$@"

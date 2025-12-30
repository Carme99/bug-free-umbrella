#!/bin/bash

#############################################################################
# System Health Check Script
#
# Description: Comprehensive system health monitoring for Ubuntu and Rocky Linux
# Compatible: Ubuntu Server 20.04+, Rocky Linux 8.x/9.x
# Requirements: Root or sudo privileges
#
# Usage: sudo ./system-health-check.sh [options]
# Options:
#   -h, --help     Show this help message
#   -q, --quiet    Minimal output (errors only)
#   -v, --verbose  Detailed output
#
# Exit Codes:
#   0 - System healthy
#   1 - Warnings detected (review recommended)
#   2 - Critical issues detected (immediate action required)
#############################################################################

set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
VERBOSE=false
QUIET=false
EXIT_CODE=0

# Thresholds
CPU_THRESHOLD=80
MEMORY_THRESHOLD=85
DISK_THRESHOLD=85
LOAD_THRESHOLD=4.0

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
    EXIT_CODE=2
}

print_info() {
    [ "$QUIET" = false ] && echo -e "${BLUE}[i]${NC} $1"
}

show_help() {
    cat << EOF
System Health Check Script

Usage: sudo $0 [options]

Options:
    -h, --help      Show this help message
    -q, --quiet     Minimal output (errors only)
    -v, --verbose   Detailed output

Description:
    Performs comprehensive system health checks including:
    - Distribution and kernel information
    - CPU usage and load average
    - Memory and swap usage
    - Disk space utilization
    - Critical service status
    - System uptime

Exit Codes:
    0 - System healthy
    1 - Warnings detected
    2 - Critical issues detected

Examples:
    sudo $0                 # Standard health check
    sudo $0 -v              # Verbose output
    sudo $0 -q              # Quiet mode

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
        VERSION=$VERSION_ID
        echo -e "${GREEN}Distribution:${NC} $NAME $VERSION"
    else
        echo -e "${YELLOW}Warning: Cannot detect distribution${NC}"
        DISTRO="unknown"
    fi
}

check_system_info() {
    print_header "System Information"

    detect_distribution
    echo -e "${GREEN}Hostname:${NC} $(hostname)"
    echo -e "${GREEN}Kernel:${NC} $(uname -r)"
    echo -e "${GREEN}Architecture:${NC} $(uname -m)"

    # Uptime
    local uptime_info=$(uptime -p 2>/dev/null || uptime)
    echo -e "${GREEN}Uptime:${NC} $uptime_info"

    # Last boot
    if command -v who &> /dev/null; then
        local last_boot=$(who -b 2>/dev/null | awk '{print $3, $4}')
        [ -n "$last_boot" ] && echo -e "${GREEN}Last Boot:${NC} $last_boot"
    fi

    echo ""
}

check_cpu() {
    print_header "CPU Status"

    # CPU count
    local cpu_count=$(nproc)
    echo -e "${GREEN}CPU Cores:${NC} $cpu_count"

    # Current CPU usage
    if command -v top &> /dev/null; then
        local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        local cpu_idle=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d'%' -f1)
        local cpu_used=$(echo "100 - $cpu_idle" | bc 2>/dev/null || echo "N/A")

        if [ "$cpu_used" != "N/A" ]; then
            echo -e "${GREEN}CPU Usage:${NC} ${cpu_used}%"

            if (( $(echo "$cpu_used > $CPU_THRESHOLD" | bc -l 2>/dev/null || echo 0) )); then
                print_warning "High CPU usage: ${cpu_used}%"
            else
                print_success "CPU usage normal: ${cpu_used}%"
            fi
        fi
    fi

    # Load average
    if [ -f /proc/loadavg ]; then
        local load_avg=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
        local load_1min=$(echo $load_avg | awk '{print $1}')
        echo -e "${GREEN}Load Average:${NC} $load_avg (1min, 5min, 15min)"

        # Check if 1-minute load is high (compared to CPU count)
        if (( $(echo "$load_1min > $cpu_count * 1.5" | bc -l 2>/dev/null || echo 0) )); then
            print_warning "High load average: $load_1min (CPU cores: $cpu_count)"
        else
            print_success "Load average normal"
        fi
    fi

    echo ""
}

check_memory() {
    print_header "Memory Status"

    if command -v free &> /dev/null; then
        # Get memory info in MB
        local mem_info=$(free -m | grep "Mem:")
        local total_mem=$(echo $mem_info | awk '{print $2}')
        local used_mem=$(echo $mem_info | awk '{print $3}')
        local free_mem=$(echo $mem_info | awk '{print $4}')
        local available_mem=$(echo $mem_info | awk '{print $7}')

        # Calculate percentage
        local mem_percent=$((used_mem * 100 / total_mem))

        echo -e "${GREEN}Total Memory:${NC} ${total_mem} MB"
        echo -e "${GREEN}Used Memory:${NC} ${used_mem} MB (${mem_percent}%)"
        echo -e "${GREEN}Free Memory:${NC} ${free_mem} MB"
        echo -e "${GREEN}Available Memory:${NC} ${available_mem} MB"

        if [ $mem_percent -gt $MEMORY_THRESHOLD ]; then
            print_warning "High memory usage: ${mem_percent}%"
        else
            print_success "Memory usage normal: ${mem_percent}%"
        fi

        # Check swap
        local swap_info=$(free -m | grep "Swap:")
        local total_swap=$(echo $swap_info | awk '{print $2}')
        local used_swap=$(echo $swap_info | awk '{print $3}')

        if [ $total_swap -gt 0 ]; then
            local swap_percent=$((used_swap * 100 / total_swap))
            echo -e "${GREEN}Swap Usage:${NC} ${used_swap}MB / ${total_swap}MB (${swap_percent}%)"

            if [ $swap_percent -gt 50 ]; then
                print_warning "Swap usage high: ${swap_percent}%"
            fi
        else
            print_info "No swap configured"
        fi
    fi

    echo ""
}

check_disk() {
    print_header "Disk Status"

    if command -v df &> /dev/null; then
        echo -e "${GREEN}Filesystem Usage:${NC}"

        # Get disk usage for major filesystems
        df -h | grep -E '^/dev/' | while read line; do
            local filesystem=$(echo $line | awk '{print $1}')
            local size=$(echo $line | awk '{print $2}')
            local used=$(echo $line | awk '{print $3}')
            local avail=$(echo $line | awk '{print $4}')
            local percent=$(echo $line | awk '{print $5}' | tr -d '%')
            local mount=$(echo $line | awk '{print $6}')

            echo "  $mount: ${used}/${size} (${percent}%) - Available: ${avail}"

            if [ $percent -ge 90 ]; then
                print_error "Critical disk space on ${mount}: ${percent}%"
            elif [ $percent -ge $DISK_THRESHOLD ]; then
                print_warning "Low disk space on ${mount}: ${percent}%"
            fi
        done

        # Check inodes
        if [ "$VERBOSE" = true ]; then
            echo ""
            echo -e "${GREEN}Inode Usage:${NC}"
            df -i | grep -E '^/dev/' | while read line; do
                local mount=$(echo $line | awk '{print $6}')
                local percent=$(echo $line | awk '{print $5}' | tr -d '%')
                echo "  $mount: ${percent}%"

                if [ $percent -ge 90 ]; then
                    print_warning "High inode usage on ${mount}: ${percent}%"
                fi
            done
        fi
    fi

    echo ""
}

check_services() {
    print_header "Critical Services Status"

    # Define critical services based on distribution
    local critical_services=("sshd" "cron")

    if [ "$DISTRO" = "ubuntu" ]; then
        critical_services+=("ufw" "systemd-resolved")
    elif [ "$DISTRO" = "rocky" ]; then
        critical_services+=("firewalld" "chronyd")
    fi

    if command -v systemctl &> /dev/null; then
        for service in "${critical_services[@]}"; do
            if systemctl list-unit-files | grep -q "^${service}.service"; then
                if systemctl is-active --quiet $service; then
                    print_success "$service is running"
                else
                    print_error "$service is NOT running"
                fi
            else
                [ "$VERBOSE" = true ] && print_info "$service not installed"
            fi
        done
    else
        print_warning "systemctl not available, skipping service checks"
    fi

    echo ""
}

check_network() {
    print_header "Network Status"

    # Check primary network interface
    if command -v ip &> /dev/null; then
        local primary_iface=$(ip route | grep default | awk '{print $5}' | head -n1)
        if [ -n "$primary_iface" ]; then
            local ip_addr=$(ip addr show $primary_iface | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)
            echo -e "${GREEN}Primary Interface:${NC} $primary_iface"
            echo -e "${GREEN}IP Address:${NC} $ip_addr"
            print_success "Network interface $primary_iface is up"
        else
            print_error "No default network route found"
        fi
    fi

    # Check internet connectivity
    if ping -c 1 -W 2 8.8.8.8 &> /dev/null; then
        print_success "Internet connectivity: OK"
    else
        print_warning "Internet connectivity: Failed (ping to 8.8.8.8)"
    fi

    # Check DNS resolution
    if command -v nslookup &> /dev/null; then
        if nslookup google.com &> /dev/null; then
            print_success "DNS resolution: OK"
        else
            print_warning "DNS resolution: Failed"
        fi
    elif command -v host &> /dev/null; then
        if host google.com &> /dev/null; then
            print_success "DNS resolution: OK"
        else
            print_warning "DNS resolution: Failed"
        fi
    fi

    echo ""
}

check_security() {
    print_header "Security Status"

    # Check firewall
    if [ "$DISTRO" = "ubuntu" ] && command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            print_success "Firewall (UFW) is active"
        else
            print_warning "Firewall (UFW) is not active"
        fi
    elif [ "$DISTRO" = "rocky" ] && command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            print_success "Firewall (firewalld) is active"
        else
            print_warning "Firewall (firewalld) is not active"
        fi
    fi

    # Check for available security updates
    if [ "$DISTRO" = "ubuntu" ]; then
        local sec_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
        if [ $sec_updates -gt 0 ]; then
            print_warning "$sec_updates security updates available"
        else
            print_success "No security updates pending"
        fi
    elif [ "$DISTRO" = "rocky" ]; then
        if command -v dnf &> /dev/null; then
            local sec_updates=$(dnf updateinfo list security 2>/dev/null | grep -i security | wc -l)
            if [ $sec_updates -gt 0 ]; then
                print_warning "$sec_updates security updates available"
            else
                print_success "No security updates pending"
            fi
        fi
    fi

    # Check SELinux (Rocky Linux)
    if command -v getenforce &> /dev/null; then
        local selinux_status=$(getenforce)
        echo -e "${GREEN}SELinux:${NC} $selinux_status"
        if [ "$selinux_status" = "Disabled" ]; then
            print_warning "SELinux is disabled"
        fi
    fi

    echo ""
}

generate_summary() {
    print_header "Health Check Summary"

    case $EXIT_CODE in
        0)
            echo -e "${GREEN}Status: HEALTHY${NC}"
            echo "All system checks passed successfully."
            ;;
        1)
            echo -e "${YELLOW}Status: WARNING${NC}"
            echo "Some checks generated warnings. Review recommended."
            ;;
        2)
            echo -e "${RED}Status: CRITICAL${NC}"
            echo "Critical issues detected. Immediate action required."
            ;;
    esac

    echo ""
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
}

#############################################################################
# Main
#############################################################################

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Check root privileges
    check_root

    # Run checks
    echo ""
    print_header "Linux Server Health Check"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    check_system_info
    check_cpu
    check_memory
    check_disk
    check_services
    check_network
    check_security
    generate_summary

    exit $EXIT_CODE
}

# Run main function
main "$@"

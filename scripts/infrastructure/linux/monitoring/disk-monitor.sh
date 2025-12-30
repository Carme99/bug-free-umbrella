#!/bin/bash

#############################################################################
# Disk Space Monitoring Script
#
# Description: Monitor disk space usage and alert on thresholds
# Compatible: Ubuntu Server 20.04+, Rocky Linux 8.x/9.x
# Requirements: Root or sudo privileges
#
# Usage: sudo ./disk-monitor.sh [threshold]
# Arguments:
#   threshold - Disk usage percentage to trigger alerts (default: 80)
#
# Exit Codes:
#   0 - All disks below threshold
#   1 - One or more disks above threshold
#   2 - Critical disk space (>95%)
#############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default threshold (%)
THRESHOLD=${1:-80}
CRITICAL_THRESHOLD=95
EXIT_CODE=0

# Email settings (configure if email alerts desired)
SEND_EMAIL=false
EMAIL_TO=""

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
    echo -e "${BLUE}[i]${NC} $1"
}

show_usage() {
    cat << EOF
Disk Space Monitoring Script

Usage: $0 [threshold]

Arguments:
    threshold    Disk usage percentage to trigger alerts (default: 80)

Description:
    Monitors all mounted filesystems and alerts when disk usage
    exceeds the specified threshold.

Exit Codes:
    0 - All disks below threshold
    1 - One or more disks above warning threshold
    2 - Critical disk space (>95%)

Examples:
    $0              # Use default 80% threshold
    $0 85           # Alert at 85% usage
    $0 90           # Alert at 90% usage

Recommended Usage:
    - Add to cron for automated monitoring
    - Configure email alerts for critical notifications
    - Run hourly or daily depending on disk growth rate

EOF
    exit 0
}

validate_threshold() {
    if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}Error: Threshold must be a number${NC}"
        exit 2
    fi

    if [ "$THRESHOLD" -lt 1 ] || [ "$THRESHOLD" -gt 100 ]; then
        echo -e "${RED}Error: Threshold must be between 1 and 100${NC}"
        exit 2
    fi
}

check_disk_usage() {
    print_header "Disk Space Monitoring"
    echo "Alert Threshold: ${THRESHOLD}%"
    echo "Critical Threshold: ${CRITICAL_THRESHOLD}%"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    # Get all mounted filesystems
    df -h | grep -E '^/dev/' | while read line; do
        local filesystem=$(echo $line | awk '{print $1}')
        local size=$(echo $line | awk '{print $2}')
        local used=$(echo $line | awk '{print $3}')
        local avail=$(echo $line | awk '{print $4}')
        local percent=$(echo $line | awk '{print $5}' | tr -d '%')
        local mount=$(echo $line | awk '{print $6}')

        echo -e "${BLUE}Filesystem:${NC} $mount ($filesystem)"
        echo "  Size: $size | Used: $used | Available: $avail | Usage: ${percent}%"

        # Check against thresholds
        if [ "$percent" -ge "$CRITICAL_THRESHOLD" ]; then
            print_error "CRITICAL: Disk usage at ${percent}% on $mount"
            echo "  Action required: Clean up disk space immediately!"
            EXIT_CODE=2
        elif [ "$percent" -ge "$THRESHOLD" ]; then
            print_warning "WARNING: Disk usage at ${percent}% on $mount"
            echo "  Recommendation: Review and clean up disk space soon"
            [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
        else
            print_success "OK: Disk usage at ${percent}% on $mount"
        fi

        echo ""
    done
}

check_inode_usage() {
    print_header "Inode Usage"

    df -i | grep -E '^/dev/' | while read line; do
        local filesystem=$(echo $line | awk '{print $1}')
        local mount=$(echo $line | awk '{print $6}')
        local iused=$(echo $line | awk '{print $3}')
        local ifree=$(echo $line | awk '{print $4}')
        local ipercent=$(echo $line | awk '{print $5}' | tr -d '%')

        echo -e "${BLUE}Filesystem:${NC} $mount ($filesystem)"
        echo "  Inodes Used: $iused | Inodes Free: $ifree | Usage: ${ipercent}%"

        if [ "$ipercent" -ge 90 ]; then
            print_error "CRITICAL: Inode usage at ${ipercent}% on $mount"
            [ $EXIT_CODE -lt 2 ] && EXIT_CODE=2
        elif [ "$ipercent" -ge 80 ]; then
            print_warning "WARNING: Inode usage at ${ipercent}% on $mount"
            [ $EXIT_CODE -lt 1 ] && EXIT_CODE=1
        else
            print_success "OK: Inode usage at ${ipercent}% on $mount"
        fi

        echo ""
    done
}

show_largest_directories() {
    print_header "Largest Directories (Top 10)"

    # Find largest directories in root
    echo "Analyzing disk usage... (this may take a moment)"
    echo ""

    du -h / --max-depth=2 2>/dev/null | sort -rh | head -10 | while read size dir; do
        echo "  $size - $dir"
    done

    echo ""
}

suggest_cleanup() {
    print_header "Cleanup Suggestions"

    echo "Common locations to check for cleanup:"
    echo ""

    # Check /tmp size
    if [ -d /tmp ]; then
        local tmp_size=$(du -sh /tmp 2>/dev/null | awk '{print $1}')
        echo "  /tmp: $tmp_size"
        echo "    - Clear temporary files: sudo find /tmp -type f -atime +7 -delete"
    fi

    # Check /var/log size
    if [ -d /var/log ]; then
        local log_size=$(du -sh /var/log 2>/dev/null | awk '{print $1}')
        echo "  /var/log: $log_size"
        echo "    - Rotate logs: sudo logrotate -f /etc/logrotate.conf"
        echo "    - Clear old logs: sudo journalctl --vacuum-time=7d"
    fi

    # Check package cache
    if command -v apt-get &> /dev/null; then
        local cache_size=$(du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}')
        echo "  APT cache: $cache_size"
        echo "    - Clean cache: sudo apt-get clean"
        echo "    - Remove old packages: sudo apt-get autoremove"
    elif command -v dnf &> /dev/null; then
        echo "  DNF cache:"
        echo "    - Clean cache: sudo dnf clean all"
        echo "    - Remove old kernels: sudo dnf remove $(dnf repoquery --installonly --latest-limit=-2 -q)"
    fi

    # Check for old kernels (Ubuntu)
    if [ -d /boot ] && command -v dpkg &> /dev/null; then
        local kernel_count=$(dpkg -l | grep linux-image | wc -l)
        if [ "$kernel_count" -gt 3 ]; then
            echo "  Old kernels detected: $kernel_count installed"
            echo "    - Remove old kernels: sudo apt-get autoremove --purge"
        fi
    fi

    # Check Docker if installed
    if command -v docker &> /dev/null; then
        echo "  Docker:"
        echo "    - Remove unused images: sudo docker image prune -a"
        echo "    - Remove unused volumes: sudo docker volume prune"
        echo "    - Full cleanup: sudo docker system prune -a"
    fi

    # Check journal size
    if command -v journalctl &> /dev/null; then
        local journal_size=$(journalctl --disk-usage 2>/dev/null | awk '{print $7}')
        echo "  Systemd journal: $journal_size"
        echo "    - Limit by time: sudo journalctl --vacuum-time=30d"
        echo "    - Limit by size: sudo journalctl --vacuum-size=500M"
    fi

    echo ""
}

generate_summary() {
    print_header "Monitoring Summary"

    case $EXIT_CODE in
        0)
            echo -e "${GREEN}Status: OK${NC}"
            echo "All filesystems below threshold (${THRESHOLD}%)"
            ;;
        1)
            echo -e "${YELLOW}Status: WARNING${NC}"
            echo "One or more filesystems above threshold (${THRESHOLD}%)"
            echo "Review warnings above and consider cleanup"
            ;;
        2)
            echo -e "${RED}Status: CRITICAL${NC}"
            echo "Critical disk space detected (>${CRITICAL_THRESHOLD}%)"
            echo "IMMEDIATE ACTION REQUIRED - Clean up disk space now!"
            ;;
    esac

    echo ""
}

send_email_alert() {
    if [ "$SEND_EMAIL" = true ] && [ -n "$EMAIL_TO" ]; then
        if command -v mail &> /dev/null; then
            local subject="[DISK ALERT] $(hostname) - Disk Space Warning"
            echo "Disk space alert on $(hostname) at $(date)" | mail -s "$subject" "$EMAIL_TO"
        fi
    fi
}

#############################################################################
# Main
#############################################################################

main() {
    # Check for help
    if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
        show_usage
    fi

    # Validate threshold
    validate_threshold

    # Run checks
    echo ""
    check_disk_usage
    check_inode_usage
    show_largest_directories
    suggest_cleanup
    generate_summary

    # Send email if critical
    if [ $EXIT_CODE -ge 1 ]; then
        send_email_alert
    fi

    exit $EXIT_CODE
}

# Run main
main "$@"

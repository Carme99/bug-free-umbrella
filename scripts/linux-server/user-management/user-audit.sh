#!/bin/bash

#############################################################################
# User Account Audit Script
#
# Description: Comprehensive user account security audit
# Compatible: Ubuntu Server 20.04+, Rocky Linux 8.x/9.x
# Requirements: Root or sudo privileges
#
# Usage: sudo ./user-audit.sh [options]
# Options:
#   -h, --help        Show help message
#   -v, --verbose     Detailed output
#   -d, --days N      Consider users inactive after N days (default: 90)
#
# Exit Codes:
#   0 - No issues found
#   1 - Warnings detected
#   2 - Critical security issues
#############################################################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Settings
VERBOSE=false
INACTIVE_DAYS=90
EXIT_CODE=0

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

show_help() {
    cat << EOF
User Account Audit Script

Usage: sudo $0 [options]

Options:
    -h, --help        Show this help message
    -v, --verbose     Detailed output with full user lists
    -d, --days N      Mark users inactive after N days (default: 90)

Description:
    Performs comprehensive user account audit including:
    - User account enumeration
    - Privileged account detection (sudo/wheel)
    - Inactive user identification
    - UID 0 account verification
    - Password policy compliance
    - Shell access review
    - Last login tracking

Exit Codes:
    0 - No security issues
    1 - Warnings detected
    2 - Critical security issues

Examples:
    sudo $0              # Standard audit
    sudo $0 -v           # Verbose with full details
    sudo $0 -d 60        # Flag users inactive for 60+ days

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

audit_user_accounts() {
    print_header "User Account Summary"

    # Count users
    local total_users=$(wc -l < /etc/passwd)
    local system_users=$(awk -F: '$3 < 1000 {print $1}' /etc/passwd | wc -l)
    local regular_users=$(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd | wc -l)
    local nologin_users=$(grep -c '/nologin\|/false' /etc/passwd || echo 0)

    echo -e "${GREEN}Total accounts:${NC} $total_users"
    echo -e "${GREEN}System accounts (UID < 1000):${NC} $system_users"
    echo -e "${GREEN}Regular user accounts (UID >= 1000):${NC} $regular_users"
    echo -e "${GREEN}Accounts with no login:${NC} $nologin_users"
    echo ""

    if [ "$VERBOSE" = true ]; then
        echo "Regular user accounts:"
        awk -F: '$3 >= 1000 && $3 != 65534 {printf "  %-20s UID: %-5s Shell: %s\n", $1, $3, $7}' /etc/passwd
        echo ""
    fi
}

check_privileged_users() {
    print_header "Privileged User Accounts"

    # Check for UID 0 accounts
    echo "Accounts with UID 0 (root privileges):"
    local uid_zero=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
    local uid_zero_count=$(echo "$uid_zero" | wc -l)

    if [ "$uid_zero_count" -eq 1 ] && [ "$uid_zero" = "root" ]; then
        print_success "Only root has UID 0"
    else
        print_error "Multiple UID 0 accounts detected:"
        echo "$uid_zero" | while read user; do
            echo "  - $user"
        done
    fi
    echo ""

    # Check sudo/wheel group
    if [ "$DISTRO" = "ubuntu" ]; then
        echo "Sudo group members:"
        local sudo_users=$(getent group sudo | cut -d: -f4)
        if [ -n "$sudo_users" ]; then
            echo -e "${GREEN}Users with sudo access:${NC}"
            echo "$sudo_users" | tr ',' '\n' | while read user; do
                echo "  - $user"
                if [ "$VERBOSE" = true ]; then
                    local last_login=$(lastlog -u "$user" 2>/dev/null | tail -1 | awk '{print $4, $5, $6, $9}')
                    echo "    Last login: $last_login"
                fi
            done

            local sudo_count=$(echo "$sudo_users" | tr ',' '\n' | wc -l)
            if [ "$sudo_count" -gt 5 ]; then
                print_warning "High number of sudo users ($sudo_count) - review recommended"
            else
                print_success "Sudo user count acceptable: $sudo_count"
            fi
        else
            print_info "No users in sudo group"
        fi

    elif [ "$DISTRO" = "rocky" ]; then
        echo "Wheel group members:"
        local wheel_users=$(getent group wheel | cut -d: -f4)
        if [ -n "$wheel_users" ]; then
            echo -e "${GREEN}Users with wheel access:${NC}"
            echo "$wheel_users" | tr ',' '\n' | while read user; do
                echo "  - $user"
                if [ "$VERBOSE" = true ]; then
                    local last_login=$(lastlog -u "$user" 2>/dev/null | tail -1 | awk '{print $4, $5, $6, $9}')
                    echo "    Last login: $last_login"
                fi
            done

            local wheel_count=$(echo "$wheel_users" | tr ',' '\n' | wc -l)
            if [ "$wheel_count" -gt 5 ]; then
                print_warning "High number of wheel users ($wheel_count) - review recommended"
            else
                print_success "Wheel user count acceptable: $wheel_count"
            fi
        else
            print_info "No users in wheel group"
        fi
    fi

    echo ""
}

check_inactive_users() {
    print_header "Inactive User Accounts"

    echo "Checking for users inactive for more than $INACTIVE_DAYS days..."
    echo ""

    local inactive_found=false
    local current_epoch=$(date +%s)
    local threshold_epoch=$((current_epoch - (INACTIVE_DAYS * 86400)))

    # Get regular users
    awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd | while read username; do
        # Get last login
        local lastlog_output=$(lastlog -u "$username" 2>/dev/null | tail -1)

        # Check if user has never logged in
        if echo "$lastlog_output" | grep -q "Never logged in"; then
            print_warning "User '$username' has NEVER logged in"
            echo "  Created but never used - consider removing"
            inactive_found=true
        else
            # Try to get last login date
            local last_login_date=$(echo "$lastlog_output" | awk '{print $4, $5, $6, $9}')

            if [ -n "$last_login_date" ] && [ "$last_login_date" != "**" ]; then
                # Convert to epoch (rough estimate)
                local login_epoch=$(date -d "$last_login_date" +%s 2>/dev/null || echo 0)

                if [ "$login_epoch" -lt "$threshold_epoch" ] && [ "$login_epoch" -ne 0 ]; then
                    print_warning "User '$username' inactive since: $last_login_date"
                    echo "  Last login more than $INACTIVE_DAYS days ago"
                    inactive_found=true
                elif [ "$VERBOSE" = true ]; then
                    print_success "User '$username' active - Last login: $last_login_date"
                fi
            fi
        fi
    done

    if [ "$inactive_found" = false ]; then
        print_success "No inactive users detected (threshold: $INACTIVE_DAYS days)"
    fi

    echo ""
}

check_shell_access() {
    print_header "Shell Access Review"

    echo "Users with valid shell access:"
    awk -F: '$7 ~ /bash|sh|zsh|ksh/ && $3 >= 1000 {print $1, $7}' /etc/passwd | while read user shell; do
        echo "  $user -> $shell"
    done
    echo ""

    # Check service accounts with shells
    echo "System accounts with login shells (potential security risk):"
    local risky_accounts=$(awk -F: '$3 < 1000 && $7 ~ /bash|sh|zsh|ksh/ && $1 != "root" {print $1, $7}' /etc/passwd)
    if [ -n "$risky_accounts" ]; then
        print_warning "System accounts with login shells found:"
        echo "$risky_accounts" | while read user shell; do
            echo "  $user -> $shell"
        done
    else
        print_success "No system accounts with unnecessary shell access"
    fi

    echo ""
}

check_password_status() {
    print_header "Password Status"

    # Check for accounts with empty passwords
    echo "Checking for accounts with empty passwords..."
    local empty_pass=$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null | grep -v '^[#!]' || echo "")

    if [ -z "$empty_pass" ]; then
        print_success "No accounts with empty passwords"
    else
        print_error "Accounts with empty/locked passwords:"
        echo "$empty_pass" | while read user; do
            echo "  - $user"
        done
    fi
    echo ""

    # Check password aging for regular users
    if [ "$VERBOSE" = true ]; then
        echo "Password aging information:"
        awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd | while read user; do
            local age_info=$(chage -l "$user" 2>/dev/null | grep "Password expires" || echo "No expiry set")
            echo "  $user: $age_info"
        done
        echo ""
    fi
}

check_locked_accounts() {
    print_header "Locked Accounts"

    echo "Checking for locked user accounts..."
    local locked_users=$(passwd -S -a 2>/dev/null | grep -E 'L\s' | awk '{print $1}' || echo "")

    if [ -n "$locked_users" ]; then
        echo -e "${GREEN}Locked accounts:${NC}"
        echo "$locked_users" | while read user; do
            echo "  - $user"
        done
    else
        print_info "No locked accounts found"
    fi

    echo ""
}

check_recent_logins() {
    print_header "Recent Login Activity"

    echo "Users logged in currently:"
    who | awk '{print $1, $2, $3, $4}' | sort -u
    echo ""

    if [ "$VERBOSE" = true ]; then
        echo "Last 10 successful logins:"
        last -n 10 -F | head -10
        echo ""

        echo "Recent failed login attempts:"
        if [ -f /var/log/auth.log ]; then
            grep "Failed password" /var/log/auth.log 2>/dev/null | tail -5 || echo "  No failed attempts"
        elif [ -f /var/log/secure ]; then
            grep "Failed password" /var/log/secure 2>/dev/null | tail -5 || echo "  No failed attempts"
        fi
    fi

    echo ""
}

generate_summary() {
    print_header "Audit Summary"

    case $EXIT_CODE in
        0)
            echo -e "${GREEN}Status: SECURE${NC}"
            echo "No user account security issues detected"
            ;;
        1)
            echo -e "${YELLOW}Status: WARNINGS${NC}"
            echo "User account warnings detected - review recommended"
            ;;
        2)
            echo -e "${RED}Status: CRITICAL${NC}"
            echo "Critical user account security issues found"
            ;;
    esac

    echo ""
    echo "Recommendations:"
    echo "  - Review inactive users and disable/remove if not needed"
    echo "  - Ensure privileged access is limited to authorized personnel"
    echo "  - Implement regular password rotation policies"
    echo "  - Monitor failed login attempts for suspicious activity"
    echo "  - Remove unnecessary shell access from system accounts"
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
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -d|--days)
                INACTIVE_DAYS="$2"
                shift 2
                ;;
            *)
                echo "Unknown option: $1"
                exit 2
                ;;
        esac
    done

    # Check root
    check_root

    # Detect distribution
    detect_distribution

    # Run audit
    echo ""
    print_header "Linux User Account Audit"
    echo "Distribution: $DISTRO"
    echo "Inactive threshold: $INACTIVE_DAYS days"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    audit_user_accounts
    check_privileged_users
    check_inactive_users
    check_shell_access
    check_password_status
    check_locked_accounts
    check_recent_logins
    generate_summary

    exit $EXIT_CODE
}

# Run main
main "$@"

#!/bin/bash

#############################################################################
# Security Audit Script
#
# Description: Comprehensive security baseline audit for Ubuntu and Rocky Linux
# Compatible: Ubuntu Server 20.04+, Rocky Linux 8.x/9.x
# Requirements: Root or sudo privileges
#
# Usage: sudo ./security-audit.sh [options]
# Options:
#   -h, --help     Show this help message
#   -v, --verbose  Detailed output
#   -r, --report   Generate detailed report file
#
# Exit Codes:
#   0 - No security issues found
#   1 - Security warnings detected
#   2 - Critical security issues detected
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
GENERATE_REPORT=false
REPORT_FILE=""
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
Security Audit Script

Usage: sudo $0 [options]

Options:
    -h, --help      Show this help message
    -v, --verbose   Detailed output
    -r, --report    Generate detailed report file

Description:
    Performs comprehensive security audit including:
    - Firewall configuration
    - SSH security settings
    - User privilege escalation
    - Password policies
    - Available security updates
    - SELinux/AppArmor status
    - Open ports analysis
    - Failed login attempts

Exit Codes:
    0 - No security issues
    1 - Warnings detected
    2 - Critical security issues

Examples:
    sudo $0                 # Run security audit
    sudo $0 -v              # Verbose output
    sudo $0 -r              # Generate report file

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
    else
        DISTRO="unknown"
    fi
}

check_firewall() {
    print_header "Firewall Status"

    if [ "$DISTRO" = "ubuntu" ]; then
        if command -v ufw &> /dev/null; then
            local ufw_status=$(ufw status | head -n1)
            echo -e "${GREEN}UFW Status:${NC} $ufw_status"

            if echo "$ufw_status" | grep -q "Status: active"; then
                print_success "UFW firewall is active"

                if [ "$VERBOSE" = true ]; then
                    echo ""
                    echo "Active Rules:"
                    ufw status numbered | tail -n +4
                fi
            else
                print_error "UFW firewall is INACTIVE"
            fi
        else
            print_warning "UFW not installed"
        fi

    elif [ "$DISTRO" = "rocky" ]; then
        if command -v firewall-cmd &> /dev/null; then
            if systemctl is-active --quiet firewalld; then
                print_success "firewalld is active"

                local default_zone=$(firewall-cmd --get-default-zone 2>/dev/null)
                echo -e "${GREEN}Default Zone:${NC} $default_zone"

                if [ "$VERBOSE" = true ]; then
                    echo ""
                    echo "Active Zones:"
                    firewall-cmd --get-active-zones
                    echo ""
                    echo "Services allowed in $default_zone:"
                    firewall-cmd --zone=$default_zone --list-services
                fi
            else
                print_error "firewalld is NOT active"
            fi
        else
            print_warning "firewalld not installed"
        fi
    fi

    echo ""
}

check_ssh() {
    print_header "SSH Configuration Security"

    if [ -f /etc/ssh/sshd_config ]; then
        local sshd_config="/etc/ssh/sshd_config"

        # Check PermitRootLogin
        local root_login=$(grep -E "^PermitRootLogin" $sshd_config | awk '{print $2}' || echo "not set")
        echo -e "${GREEN}PermitRootLogin:${NC} $root_login"
        if [ "$root_login" = "yes" ]; then
            print_error "Root login via SSH is ENABLED (security risk)"
        elif [ "$root_login" = "no" ] || [ "$root_login" = "prohibit-password" ]; then
            print_success "Root login properly restricted"
        else
            print_warning "PermitRootLogin not explicitly set"
        fi

        # Check PasswordAuthentication
        local pass_auth=$(grep -E "^PasswordAuthentication" $sshd_config | awk '{print $2}' || echo "not set")
        echo -e "${GREEN}PasswordAuthentication:${NC} $pass_auth"
        if [ "$pass_auth" = "no" ]; then
            print_success "Password authentication disabled (key-based only)"
        elif [ "$pass_auth" = "yes" ]; then
            print_warning "Password authentication enabled (consider key-based auth)"
        fi

        # Check Protocol
        if grep -qE "^Protocol 1" $sshd_config; then
            print_error "SSH Protocol 1 detected (deprecated and insecure)"
        else
            print_success "SSH Protocol 2 in use (or default)"
        fi

        # Check Port
        local ssh_port=$(grep -E "^Port" $sshd_config | awk '{print $2}' || echo "22")
        echo -e "${GREEN}SSH Port:${NC} $ssh_port"
        if [ "$ssh_port" != "22" ]; then
            print_info "SSH running on non-standard port: $ssh_port"
        fi

        # Check MaxAuthTries
        local max_tries=$(grep -E "^MaxAuthTries" $sshd_config | awk '{print $2}' || echo "not set")
        echo -e "${GREEN}MaxAuthTries:${NC} $max_tries"
        if [ "$max_tries" != "not set" ] && [ "$max_tries" -le 3 ]; then
            print_success "MaxAuthTries set to secure value: $max_tries"
        elif [ "$max_tries" = "not set" ]; then
            print_info "MaxAuthTries using default (6)"
        fi

    else
        print_warning "SSH config file not found"
    fi

    echo ""
}

check_users() {
    print_header "User Account Security"

    # Check for UID 0 accounts (should only be root)
    echo "Checking for accounts with UID 0..."
    local uid_zero=$(awk -F: '$3 == 0 {print $1}' /etc/passwd)
    if [ "$(echo "$uid_zero" | wc -l)" -eq 1 ] && [ "$uid_zero" = "root" ]; then
        print_success "Only root has UID 0"
    else
        print_error "Multiple accounts with UID 0 detected:"
        echo "$uid_zero"
    fi

    # Check for accounts with empty passwords
    echo ""
    echo "Checking for accounts with empty passwords..."
    local empty_pass=$(awk -F: '$2 == "" {print $1}' /etc/shadow 2>/dev/null || echo "")
    if [ -z "$empty_pass" ]; then
        print_success "No accounts with empty passwords"
    else
        print_error "Accounts with empty passwords found:"
        echo "$empty_pass"
    fi

    # Check sudo/wheel group members
    echo ""
    if [ "$DISTRO" = "ubuntu" ]; then
        echo "Checking sudo group members..."
        local sudo_users=$(getent group sudo | cut -d: -f4)
        if [ -n "$sudo_users" ]; then
            echo -e "${GREEN}Sudo users:${NC} $sudo_users"
            local user_count=$(echo "$sudo_users" | tr ',' '\n' | wc -l)
            if [ $user_count -gt 5 ]; then
                print_warning "Large number of sudo users ($user_count) - review recommended"
            fi
        else
            print_info "No users in sudo group"
        fi
    elif [ "$DISTRO" = "rocky" ]; then
        echo "Checking wheel group members..."
        local wheel_users=$(getent group wheel | cut -d: -f4)
        if [ -n "$wheel_users" ]; then
            echo -e "${GREEN}Wheel users:${NC} $wheel_users"
            local user_count=$(echo "$wheel_users" | tr ',' '\n' | wc -l)
            if [ $user_count -gt 5 ]; then
                print_warning "Large number of wheel users ($user_count) - review recommended"
            fi
        else
            print_info "No users in wheel group"
        fi
    fi

    echo ""
}

check_updates() {
    print_header "Security Updates"

    if [ "$DISTRO" = "ubuntu" ]; then
        # Update package cache quietly
        apt-get update -qq 2>/dev/null

        # Check for security updates
        local sec_updates=$(apt list --upgradable 2>/dev/null | grep -i security | wc -l)
        local total_updates=$(apt list --upgradable 2>/dev/null | tail -n +2 | wc -l)

        echo -e "${GREEN}Security Updates:${NC} $sec_updates"
        echo -e "${GREEN}Total Updates:${NC} $total_updates"

        if [ $sec_updates -gt 0 ]; then
            print_error "$sec_updates security updates available - install immediately"
            if [ "$VERBOSE" = true ]; then
                echo ""
                echo "Security updates available:"
                apt list --upgradable 2>/dev/null | grep -i security
            fi
        else
            print_success "No security updates pending"
        fi

    elif [ "$DISTRO" = "rocky" ]; then
        if command -v dnf &> /dev/null; then
            # Check for security updates
            local sec_updates=$(dnf updateinfo list security 2>/dev/null | grep -i 'security' | wc -l)
            local total_updates=$(dnf check-update 2>/dev/null | grep -v '^$' | grep -v 'Last metadata' | wc -l)

            echo -e "${GREEN}Security Updates:${NC} $sec_updates"
            echo -e "${GREEN}Total Updates:${NC} $total_updates"

            if [ $sec_updates -gt 0 ]; then
                print_error "$sec_updates security updates available - install immediately"
                if [ "$VERBOSE" = true ]; then
                    echo ""
                    echo "Security updates available:"
                    dnf updateinfo list security 2>/dev/null
                fi
            else
                print_success "No security updates pending"
            fi
        fi
    fi

    echo ""
}

check_selinux_apparmor() {
    print_header "Mandatory Access Control"

    # Check SELinux (Rocky Linux)
    if command -v getenforce &> /dev/null; then
        local selinux_status=$(getenforce)
        echo -e "${GREEN}SELinux Status:${NC} $selinux_status"

        case $selinux_status in
            "Enforcing")
                print_success "SELinux is enforcing"
                ;;
            "Permissive")
                print_warning "SELinux is in permissive mode (not enforcing)"
                ;;
            "Disabled")
                print_error "SELinux is disabled"
                ;;
        esac

        if [ "$VERBOSE" = true ] && [ "$selinux_status" != "Disabled" ]; then
            echo ""
            echo "SELinux Policy:"
            sestatus | grep "Loaded policy"
        fi
    fi

    # Check AppArmor (Ubuntu)
    if command -v aa-status &> /dev/null; then
        if systemctl is-active --quiet apparmor; then
            local profiles=$(aa-status --profiled 2>/dev/null || echo "0")
            local enforced=$(aa-status --enforced 2>/dev/null || echo "0")
            echo -e "${GREEN}AppArmor:${NC} Active"
            echo -e "${GREEN}Profiles loaded:${NC} $profiles"
            echo -e "${GREEN}Profiles enforced:${NC} $enforced"

            if [ "$enforced" -gt 0 ]; then
                print_success "AppArmor is active with $enforced enforced profiles"
            else
                print_warning "AppArmor active but no enforced profiles"
            fi
        else
            print_warning "AppArmor is not active"
        fi
    fi

    echo ""
}

check_open_ports() {
    print_header "Open Ports Analysis"

    if command -v ss &> /dev/null; then
        echo "Listening TCP ports:"
        ss -tlnp | grep LISTEN | while read line; do
            local port=$(echo "$line" | awk '{print $4}' | awk -F: '{print $NF}')
            local process=$(echo "$line" | awk -F'users:' '{print $2}' | tr -d '()"' | awk -F, '{print $1}')
            echo "  Port $port - $process"
        done

        # Check for commonly exploited ports
        local risky_ports=("23" "21" "445" "139" "3389")
        for port in "${risky_ports[@]}"; do
            if ss -tln | grep -q ":$port "; then
                case $port in
                    23) print_warning "Telnet (port 23) is listening - use SSH instead" ;;
                    21) print_warning "FTP (port 21) is listening - consider SFTP/SCP" ;;
                    445|139) print_info "SMB ports open - ensure proper firewall rules" ;;
                    3389) print_info "RDP (port 3389) is listening - ensure firewall protection" ;;
                esac
            fi
        done
    else
        print_info "ss command not available, skipping port check"
    fi

    echo ""
}

check_failed_logins() {
    print_header "Failed Login Attempts"

    if [ -f /var/log/auth.log ]; then
        # Ubuntu
        local failed_logins=$(grep "Failed password" /var/log/auth.log 2>/dev/null | wc -l)
        echo -e "${GREEN}Failed SSH logins (auth.log):${NC} $failed_logins"

        if [ $failed_logins -gt 100 ]; then
            print_warning "High number of failed login attempts: $failed_logins"
        elif [ $failed_logins -gt 0 ]; then
            print_info "$failed_logins failed login attempts detected"
        else
            print_success "No recent failed login attempts"
        fi

        if [ "$VERBOSE" = true ] && [ $failed_logins -gt 0 ]; then
            echo ""
            echo "Recent failed login IPs:"
            grep "Failed password" /var/log/auth.log 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -5
        fi

    elif [ -f /var/log/secure ]; then
        # Rocky Linux
        local failed_logins=$(grep "Failed password" /var/log/secure 2>/dev/null | wc -l)
        echo -e "${GREEN}Failed SSH logins (secure):${NC} $failed_logins"

        if [ $failed_logins -gt 100 ]; then
            print_warning "High number of failed login attempts: $failed_logins"
        elif [ $failed_logins -gt 0 ]; then
            print_info "$failed_logins failed login attempts detected"
        else
            print_success "No recent failed login attempts"
        fi

        if [ "$VERBOSE" = true ] && [ $failed_logins -gt 0 ]; then
            echo ""
            echo "Recent failed login IPs:"
            grep "Failed password" /var/log/secure 2>/dev/null | awk '{print $(NF-3)}' | sort | uniq -c | sort -rn | head -5
        fi
    fi

    echo ""
}

check_password_policy() {
    print_header "Password Policy"

    # Check password aging settings
    if [ -f /etc/login.defs ]; then
        local pass_max=$(grep "^PASS_MAX_DAYS" /etc/login.defs | awk '{print $2}')
        local pass_min=$(grep "^PASS_MIN_DAYS" /etc/login.defs | awk '{print $2}')
        local pass_warn=$(grep "^PASS_WARN_AGE" /etc/login.defs | awk '{print $2}')

        echo -e "${GREEN}Max password age:${NC} $pass_max days"
        echo -e "${GREEN}Min password age:${NC} $pass_min days"
        echo -e "${GREEN}Password warning:${NC} $pass_warn days"

        if [ "$pass_max" -gt 90 ]; then
            print_warning "Password max age is high: $pass_max days (recommended: 90 or less)"
        else
            print_success "Password max age is acceptable: $pass_max days"
        fi
    fi

    # Check if pam_pwquality is configured
    if [ -f /etc/pam.d/common-password ] || [ -f /etc/pam.d/system-auth ]; then
        if grep -q "pam_pwquality" /etc/pam.d/* 2>/dev/null; then
            print_success "Password quality checking (pam_pwquality) is configured"
        else
            print_warning "Password quality checking may not be configured"
        fi
    fi

    echo ""
}

generate_summary() {
    print_header "Security Audit Summary"

    case $EXIT_CODE in
        0)
            echo -e "${GREEN}Status: SECURE${NC}"
            echo "No security issues detected."
            ;;
        1)
            echo -e "${YELLOW}Status: WARNINGS DETECTED${NC}"
            echo "Some security concerns found. Review and address warnings above."
            ;;
        2)
            echo -e "${RED}Status: CRITICAL ISSUES${NC}"
            echo "Critical security issues detected. Immediate action required."
            ;;
    esac

    echo ""
    echo "Audit completed: $(date '+%Y-%m-%d %H:%M:%S')"
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
            -r|--report)
                GENERATE_REPORT=true
                REPORT_FILE="/var/log/security-audit-$(date +%Y%m%d-%H%M%S).log"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Check root
    check_root

    # Detect distribution
    detect_distribution

    # Run audit
    echo ""
    print_header "Security Audit for Linux Servers"
    echo "Started: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Distribution: $DISTRO"
    echo ""

    check_firewall
    check_ssh
    check_users
    check_updates
    check_selinux_apparmor
    check_open_ports
    check_failed_logins
    check_password_policy
    generate_summary

    if [ "$GENERATE_REPORT" = true ]; then
        echo "Report saved to: $REPORT_FILE"
    fi

    exit $EXIT_CODE
}

# Execute if running the script with output redirection for report
if [ "$GENERATE_REPORT" = true ]; then
    main "$@" | tee "$REPORT_FILE"
else
    main "$@"
fi

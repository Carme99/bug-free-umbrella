#!/bin/bash

#############################################################################
# Network Diagnostics Script
#
# Description: Comprehensive network connectivity and configuration diagnostics
# Compatible: Ubuntu Server 20.04+, Rocky Linux 8.x/9.x
# Requirements: Root or sudo privileges
#
# Usage: sudo ./network-diagnostics.sh [options]
# Options:
#   -h, --help        Show help message
#   -v, --verbose     Detailed output
#   -t, --test HOST   Test connectivity to specific host
#
# Exit Codes:
#   0 - Network healthy
#   1 - Network warnings
#   2 - Critical network issues
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
TEST_HOST=""
EXIT_CODE=0

# Default test endpoints
DEFAULT_TESTS=("8.8.8.8" "1.1.1.1" "google.com" "github.com")

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
Network Diagnostics Script

Usage: sudo $0 [options]

Options:
    -h, --help        Show this help message
    -v, --verbose     Detailed diagnostic output
    -t, --test HOST   Test connectivity to specific host/IP

Description:
    Performs comprehensive network diagnostics including:
    - Network interface status and configuration
    - IP address and routing information
    - DNS resolution testing
    - Gateway connectivity
    - Internet connectivity verification
    - Active network connections
    - Listening ports

Exit Codes:
    0 - Network healthy
    1 - Network warnings detected
    2 - Critical network issues

Examples:
    sudo $0                     # Run full diagnostics
    sudo $0 -v                  # Verbose output
    sudo $0 -t google.com       # Test specific host

EOF
    exit 0
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}ERROR: This script must be run as root or with sudo${NC}"
        exit 2
    fi
}

check_network_interfaces() {
    print_header "Network Interfaces"

    if command -v ip &> /dev/null; then
        # Show all interfaces
        echo "Available network interfaces:"
        ip -br link show | while read interface state mac; do
            local color=$NC
            case $state in
                UP) color=$GREEN ;;
                DOWN) color=$RED ;;
                *) color=$YELLOW ;;
            esac
            echo -e "  ${color}$interface${NC} - $state - $mac"
        done
        echo ""

        # Show IP addresses
        echo "IP Address Configuration:"
        ip -br addr show | grep -v '^lo' | while read interface state addrs; do
            echo "  $interface:"
            echo "    State: $state"
            echo "    Addresses: $addrs"

            # Check if interface is up with IP
            if [ "$state" = "UP" ] && echo "$addrs" | grep -q '[0-9]'; then
                print_success "Interface $interface is up with IP"
            elif [ "$state" = "UP" ]; then
                print_warning "Interface $interface is up but has no IP address"
            elif [ "$state" = "DOWN" ]; then
                print_info "Interface $interface is down"
            fi
        done
    else
        print_warning "ip command not available, using ifconfig"
        ifconfig -a
    fi

    echo ""
}

check_routing() {
    print_header "Routing Information"

    if command -v ip &> /dev/null; then
        echo "Default route:"
        local default_route=$(ip route show default 2>/dev/null || echo "No default route")

        if echo "$default_route" | grep -q "default via"; then
            echo "$default_route"
            local gateway=$(echo "$default_route" | awk '{print $3}')
            local interface=$(echo "$default_route" | awk '{print $5}')
            print_success "Default gateway: $gateway via $interface"
        else
            print_error "No default gateway configured"
        fi
        echo ""

        if [ "$VERBOSE" = true ]; then
            echo "Complete routing table:"
            ip route show
            echo ""
        fi
    else
        route -n
        echo ""
    fi
}

test_gateway_connectivity() {
    print_header "Gateway Connectivity"

    # Get default gateway
    local gateway=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)

    if [ -z "$gateway" ]; then
        print_error "Cannot test gateway - no default gateway configured"
        return
    fi

    echo "Testing connectivity to gateway: $gateway"

    if ping -c 3 -W 2 "$gateway" &> /dev/null; then
        print_success "Gateway $gateway is reachable"

        # Calculate average ping time
        local avg_ping=$(ping -c 3 -W 2 "$gateway" 2>/dev/null | tail -1 | awk -F'/' '{print $5}')
        echo "  Average ping time: ${avg_ping}ms"
    else
        print_error "Cannot reach gateway $gateway"
    fi

    echo ""
}

test_dns_resolution() {
    print_header "DNS Resolution"

    # Show DNS servers
    echo "Configured DNS servers:"
    if [ -f /etc/resolv.conf ]; then
        grep "^nameserver" /etc/resolv.conf | while read ns ip; do
            echo "  $ip"
        done
    fi
    echo ""

    # Test DNS resolution
    local test_domains=("google.com" "github.com")

    for domain in "${test_domains[@]}"; do
        echo "Testing DNS resolution for: $domain"

        if command -v nslookup &> /dev/null; then
            local result=$(nslookup "$domain" 2>&1)
            if echo "$result" | grep -q "Address:"; then
                print_success "DNS resolution successful for $domain"
                if [ "$VERBOSE" = true ]; then
                    echo "$result" | grep "Address:" | tail -2 | sed 's/^/  /'
                fi
            else
                print_error "DNS resolution failed for $domain"
            fi
        elif command -v dig &> /dev/null; then
            if dig +short "$domain" &> /dev/null; then
                print_success "DNS resolution successful for $domain"
                [ "$VERBOSE" = true ] && dig +short "$domain" | sed 's/^/  /'
            else
                print_error "DNS resolution failed for $domain"
            fi
        elif command -v host &> /dev/null; then
            if host "$domain" &> /dev/null; then
                print_success "DNS resolution successful for $domain"
                [ "$VERBOSE" = true ] && host "$domain" | sed 's/^/  /'
            else
                print_error "DNS resolution failed for $domain"
            fi
        else
            print_warning "No DNS tools available (nslookup/dig/host)"
            break
        fi
    done

    echo ""
}

test_internet_connectivity() {
    print_header "Internet Connectivity"

    # Test with multiple endpoints
    local endpoints=("${DEFAULT_TESTS[@]}")

    for endpoint in "${endpoints[@]}"; do
        echo "Testing connectivity to: $endpoint"

        if ping -c 2 -W 3 "$endpoint" &> /dev/null; then
            print_success "Successfully reached $endpoint"
        else
            print_warning "Failed to reach $endpoint"
        fi
    done

    # Test HTTP/HTTPS connectivity
    echo ""
    echo "Testing HTTP/HTTPS connectivity:"

    if command -v curl &> /dev/null; then
        if curl -s -o /dev/null -w "%{http_code}" --max-time 5 https://www.google.com | grep -q "200"; then
            print_success "HTTPS connectivity working (google.com)"
        else
            print_warning "HTTPS connectivity issue (google.com)"
        fi
    elif command -v wget &> /dev/null; then
        if wget -q --spider --timeout=5 https://www.google.com 2>/dev/null; then
            print_success "HTTPS connectivity working (google.com)"
        else
            print_warning "HTTPS connectivity issue (google.com)"
        fi
    else
        print_info "curl/wget not available for HTTP testing"
    fi

    echo ""
}

check_listening_ports() {
    print_header "Listening Ports"

    if command -v ss &> /dev/null; then
        echo "TCP ports listening:"
        ss -tlnp | head -20 | grep LISTEN | while read line; do
            local port=$(echo "$line" | awk '{print $4}' | awk -F: '{print $NF}')
            local process=$(echo "$line" | awk -F'users:' '{print $2}' | cut -d'"' -f2 | head -c 30)
            [ -n "$process" ] && echo "  Port $port - $process" || echo "  Port $port"
        done
        echo ""

        if [ "$VERBOSE" = true ]; then
            echo "UDP ports listening:"
            ss -ulnp | head -10 | grep -v "State" | while read line; do
                local port=$(echo "$line" | awk '{print $4}' | awk -F: '{print $NF}')
                local process=$(echo "$line" | awk -F'users:' '{print $2}' | cut -d'"' -f2 | head -c 30)
                [ -n "$process" ] && echo "  Port $port - $process" || echo "  Port $port"
            done
            echo ""
        fi
    elif command -v netstat &> /dev/null; then
        echo "Listening TCP ports:"
        netstat -tlnp | grep LISTEN | head -20
        echo ""
    else
        print_warning "ss/netstat not available"
    fi
}

check_active_connections() {
    print_header "Active Network Connections"

    if command -v ss &> /dev/null; then
        local established=$(ss -tn | grep ESTAB | wc -l)
        echo -e "${GREEN}Established connections:${NC} $established"

        if [ "$VERBOSE" = true ] && [ $established -gt 0 ]; then
            echo ""
            echo "Active connections (top 10):"
            ss -tnp | grep ESTAB | head -10 | while read line; do
                echo "  $line"
            done
        fi
    elif command -v netstat &> /dev/null; then
        local established=$(netstat -tn | grep ESTABLISHED | wc -l)
        echo -e "${GREEN}Established connections:${NC} $established"

        if [ "$VERBOSE" = true ] && [ $established -gt 0 ]; then
            echo ""
            echo "Active connections (top 10):"
            netstat -tnp | grep ESTABLISHED | head -10
        fi
    fi

    echo ""
}

test_custom_host() {
    if [ -n "$TEST_HOST" ]; then
        print_header "Custom Host Test: $TEST_HOST"

        # Ping test
        echo "Ping test:"
        if ping -c 4 -W 2 "$TEST_HOST" &> /dev/null; then
            print_success "Host $TEST_HOST is reachable via ping"
            local stats=$(ping -c 4 -W 2 "$TEST_HOST" 2>/dev/null | tail -2)
            echo "$stats" | sed 's/^/  /'
        else
            print_error "Host $TEST_HOST is NOT reachable via ping"
        fi

        # Traceroute
        if [ "$VERBOSE" = true ]; then
            echo ""
            echo "Traceroute to $TEST_HOST:"
            if command -v traceroute &> /dev/null; then
                traceroute -m 10 "$TEST_HOST" 2>/dev/null | sed 's/^/  /' || echo "  Traceroute failed"
            elif command -v tracepath &> /dev/null; then
                tracepath -m 10 "$TEST_HOST" 2>/dev/null | sed 's/^/  /' || echo "  Tracepath failed"
            else
                echo "  traceroute/tracepath not available"
            fi
        fi

        echo ""
    fi
}

check_firewall_status() {
    print_header "Firewall Status"

    # Check for UFW (Ubuntu)
    if command -v ufw &> /dev/null; then
        local ufw_status=$(ufw status 2>/dev/null | head -1)
        echo -e "${GREEN}UFW:${NC} $ufw_status"

        if [ "$VERBOSE" = true ]; then
            ufw status numbered 2>/dev/null | tail -n +4 | head -10
        fi
    fi

    # Check for firewalld (Rocky Linux)
    if command -v firewall-cmd &> /dev/null; then
        if systemctl is-active --quiet firewalld; then
            local default_zone=$(firewall-cmd --get-default-zone 2>/dev/null)
            echo -e "${GREEN}firewalld:${NC} active (zone: $default_zone)"

            if [ "$VERBOSE" = true ]; then
                echo "Active zones:"
                firewall-cmd --get-active-zones
            fi
        else
            echo -e "${YELLOW}firewalld:${NC} inactive"
        fi
    fi

    echo ""
}

generate_summary() {
    print_header "Network Diagnostics Summary"

    case $EXIT_CODE in
        0)
            echo -e "${GREEN}Status: HEALTHY${NC}"
            echo "Network connectivity and configuration are working properly"
            ;;
        1)
            echo -e "${YELLOW}Status: WARNINGS${NC}"
            echo "Network is functional but some issues detected"
            ;;
        2)
            echo -e "${RED}Status: CRITICAL${NC}"
            echo "Critical network issues detected"
            ;;
    esac

    echo ""
    echo "Diagnostic completed: $(date '+%Y-%m-%d %H:%M:%S')"
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
            -t|--test)
                TEST_HOST="$2"
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

    # Run diagnostics
    echo ""
    print_header "Network Diagnostics"
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    check_network_interfaces
    check_routing
    test_gateway_connectivity
    test_dns_resolution
    test_internet_connectivity
    check_listening_ports
    check_active_connections
    check_firewall_status
    test_custom_host
    generate_summary

    exit $EXIT_CODE
}

# Run main
main "$@"

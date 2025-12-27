#!/bin/bash

#############################################################################
# Backup Verification Script
#
# Description: Verify backup files and directories for completeness and age
# Compatible: Ubuntu Server 20.04+, Rocky Linux 8.x/9.x
# Requirements: Root or sudo privileges (for some backup locations)
#
# Usage: ./backup-verify.sh [options] <backup_path>
# Arguments:
#   backup_path - Path to backup directory to verify
#
# Options:
#   -h, --help        Show help message
#   -v, --verbose     Detailed output
#   -d, --days N      Alert if backups older than N days (default: 1)
#   -s, --size MIN    Minimum expected backup size in MB (default: 1)
#
# Exit Codes:
#   0 - Backups verified successfully
#   1 - Backup warnings (old or small backups)
#   2 - Critical backup issues (missing or very old)
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
MAX_AGE_DAYS=1
MIN_SIZE_MB=1
BACKUP_PATH=""
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
Backup Verification Script

Usage: $0 [options] <backup_path>

Arguments:
    backup_path      Path to backup directory to verify

Options:
    -h, --help       Show this help message
    -v, --verbose    Detailed output with file listings
    -d, --days N     Alert if backups older than N days (default: 1)
    -s, --size MIN   Minimum expected backup size in MB (default: 1)

Description:
    Verifies backup files by checking:
    - Backup directory existence
    - Presence of backup files
    - Age of most recent backup
    - Size of backup files
    - File count and total space used

Exit Codes:
    0 - Backups verified successfully
    1 - Backup warnings (old or undersized)
    2 - Critical issues (missing or very old)

Examples:
    $0 /var/backups                    # Verify /var/backups
    $0 -d 7 /backup                    # Alert if > 7 days old
    $0 -s 100 -v /mnt/backup           # Min 100MB, verbose
    $0 -d 1 -s 50 /home/backups        # 1 day max, 50MB min

Common Backup Locations:
    /var/backups        - Ubuntu default
    /backup             - Common custom location
    /mnt/backup         - Mounted backup drive
    /home/backup        - User backups

EOF
    exit 0
}

validate_inputs() {
    # Check if backup path provided
    if [ -z "$BACKUP_PATH" ]; then
        echo -e "${RED}ERROR: Backup path required${NC}"
        echo "Usage: $0 [options] <backup_path>"
        echo "Use --help for more information"
        exit 2
    fi

    # Validate numeric inputs
    if ! [[ "$MAX_AGE_DAYS" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ERROR: Days must be a number${NC}"
        exit 2
    fi

    if ! [[ "$MIN_SIZE_MB" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ERROR: Size must be a number${NC}"
        exit 2
    fi
}

check_backup_directory() {
    print_header "Backup Directory Check"

    echo "Checking: $BACKUP_PATH"
    echo ""

    # Check if directory exists
    if [ ! -d "$BACKUP_PATH" ]; then
        print_error "Backup directory does not exist: $BACKUP_PATH"
        echo ""
        echo "Possible issues:"
        echo "  - Path is incorrect"
        echo "  - Backup drive not mounted"
        echo "  - Directory was deleted"
        exit 2
    fi

    print_success "Backup directory exists"

    # Check if directory is readable
    if [ ! -r "$BACKUP_PATH" ]; then
        print_error "Backup directory is not readable"
        echo "Try running with sudo/root privileges"
        exit 2
    fi

    print_success "Backup directory is accessible"

    # Check if directory is writable (for backup processes)
    if [ -w "$BACKUP_PATH" ]; then
        print_success "Backup directory is writable"
    else
        print_warning "Backup directory is read-only"
    fi

    # Show mount point if applicable
    local mount_point=$(df -P "$BACKUP_PATH" | tail -1 | awk '{print $1}')
    echo -e "${GREEN}Filesystem:${NC} $mount_point"

    echo ""
}

analyze_backup_contents() {
    print_header "Backup Contents Analysis"

    # Count files
    local file_count=$(find "$BACKUP_PATH" -type f 2>/dev/null | wc -l)
    local dir_count=$(find "$BACKUP_PATH" -type d 2>/dev/null | wc -l)

    echo -e "${GREEN}Files:${NC} $file_count"
    echo -e "${GREEN}Directories:${NC} $dir_count"

    if [ $file_count -eq 0 ]; then
        print_error "No backup files found in $BACKUP_PATH"
        return
    fi

    print_success "Found $file_count backup files"

    # Calculate total size
    local total_size=$(du -sh "$BACKUP_PATH" 2>/dev/null | awk '{print $1}')
    echo -e "${GREEN}Total size:${NC} $total_size"

    # Show largest files
    if [ "$VERBOSE" = true ]; then
        echo ""
        echo "Largest backup files (top 10):"
        find "$BACKUP_PATH" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -10 | while read size file; do
            echo "  $size - $file"
        done
    fi

    echo ""
}

check_backup_age() {
    print_header "Backup Age Verification"

    echo "Maximum age threshold: $MAX_AGE_DAYS days"
    echo ""

    # Find most recent file
    local newest_file=$(find "$BACKUP_PATH" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)

    if [ -z "$newest_file" ]; then
        print_error "No files found to check age"
        return
    fi

    # Get file modification time
    local file_time=$(stat -c %Y "$newest_file" 2>/dev/null || stat -f %m "$newest_file" 2>/dev/null)
    local current_time=$(date +%s)
    local age_seconds=$((current_time - file_time))
    local age_days=$((age_seconds / 86400))
    local age_hours=$(((age_seconds % 86400) / 3600))

    echo -e "${GREEN}Newest backup:${NC}"
    echo "  File: $(basename "$newest_file")"
    echo "  Modified: $(date -d @$file_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $file_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
    echo "  Age: ${age_days}d ${age_hours}h"

    # Check against threshold
    if [ $age_days -gt $MAX_AGE_DAYS ]; then
        if [ $age_days -gt $((MAX_AGE_DAYS * 7)) ]; then
            print_error "CRITICAL: Newest backup is ${age_days} days old (threshold: $MAX_AGE_DAYS days)"
            EXIT_CODE=2
        else
            print_warning "Newest backup is ${age_days} days old (threshold: $MAX_AGE_DAYS days)"
        fi
    else
        print_success "Backup age is acceptable (${age_days}d ${age_hours}h)"
    fi

    # Find oldest file
    if [ "$VERBOSE" = true ]; then
        echo ""
        local oldest_file=$(find "$BACKUP_PATH" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)
        local oldest_time=$(stat -c %Y "$oldest_file" 2>/dev/null || stat -f %m "$oldest_file" 2>/dev/null)
        local oldest_age_days=$(( (current_time - oldest_time) / 86400 ))

        echo -e "${GREEN}Oldest backup:${NC}"
        echo "  File: $(basename "$oldest_file")"
        echo "  Modified: $(date -d @$oldest_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r $oldest_time '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
        echo "  Age: ${oldest_age_days} days"
    fi

    echo ""
}

check_backup_sizes() {
    print_header "Backup Size Verification"

    echo "Minimum size threshold: ${MIN_SIZE_MB}MB"
    echo ""

    # Check files against minimum size
    local small_files=0
    local total_files=0

    find "$BACKUP_PATH" -type f 2>/dev/null | while read file; do
        total_files=$((total_files + 1))
        local size_bytes=$(stat -c %s "$file" 2>/dev/null || stat -f %z "$file" 2>/dev/null)
        local size_mb=$((size_bytes / 1048576))

        if [ $size_mb -lt $MIN_SIZE_MB ]; then
            small_files=$((small_files + 1))
            if [ "$VERBOSE" = true ]; then
                print_warning "Small backup: $(basename "$file") (${size_mb}MB)"
            fi
        fi
    done

    # Summary
    if [ $small_files -eq 0 ]; then
        print_success "All backup files meet minimum size requirement"
    else
        print_warning "$small_files files are smaller than ${MIN_SIZE_MB}MB"
    fi

    echo ""
}

check_disk_space() {
    print_header "Backup Storage Space"

    # Get disk space for backup location
    local df_output=$(df -h "$BACKUP_PATH" | tail -1)
    local filesystem=$(echo "$df_output" | awk '{print $1}')
    local size=$(echo "$df_output" | awk '{print $2}')
    local used=$(echo "$df_output" | awk '{print $3}')
    local available=$(echo "$df_output" | awk '{print $4}')
    local percent=$(echo "$df_output" | awk '{print $5}' | tr -d '%')

    echo -e "${GREEN}Filesystem:${NC} $filesystem"
    echo -e "${GREEN}Total size:${NC} $size"
    echo -e "${GREEN}Used:${NC} $used ($percent%)"
    echo -e "${GREEN}Available:${NC} $available"

    # Check space availability
    if [ $percent -ge 95 ]; then
        print_error "CRITICAL: Backup storage almost full ($percent%)"
    elif [ $percent -ge 85 ]; then
        print_warning "Backup storage running low ($percent%)"
    else
        print_success "Adequate backup storage available ($percent% used)"
    fi

    echo ""
}

list_backup_files() {
    if [ "$VERBOSE" = true ]; then
        print_header "Backup Files Listing"

        echo "Recent backup files (last 20):"
        find "$BACKUP_PATH" -type f -printf '%T@ %TY-%Tm-%Td %TH:%TM %s %p\n' 2>/dev/null | \
            sort -rn | head -20 | while read timestamp date time size file; do
            local size_mb=$((size / 1048576))
            echo "  $date $time - ${size_mb}MB - $(basename "$file")"
        done

        echo ""
    fi
}

generate_summary() {
    print_header "Verification Summary"

    case $EXIT_CODE in
        0)
            echo -e "${GREEN}Status: VERIFIED${NC}"
            echo "Backups are current and properly configured"
            ;;
        1)
            echo -e "${YELLOW}Status: WARNINGS${NC}"
            echo "Backup warnings detected - review recommendations"
            ;;
        2)
            echo -e "${RED}Status: CRITICAL${NC}"
            echo "Critical backup issues - immediate attention required"
            ;;
    esac

    echo ""
    echo "Recommendations:"
    echo "  - Monitor backup job execution logs"
    echo "  - Test backup restoration periodically"
    echo "  - Verify backup integrity with checksums"
    echo "  - Maintain off-site backup copies"
    echo "  - Document backup and restore procedures"
    echo ""
    echo "Verification completed: $(date '+%Y-%m-%d %H:%M:%S')"
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
                MAX_AGE_DAYS="$2"
                shift 2
                ;;
            -s|--size)
                MIN_SIZE_MB="$2"
                shift 2
                ;;
            -*)
                echo "Unknown option: $1"
                exit 2
                ;;
            *)
                BACKUP_PATH="$1"
                shift
                ;;
        esac
    done

    # Validate inputs
    validate_inputs

    # Run verification
    echo ""
    print_header "Backup Verification"
    echo "Backup path: $BACKUP_PATH"
    echo "Max age: $MAX_AGE_DAYS days"
    echo "Min size: ${MIN_SIZE_MB}MB"
    echo ""

    check_backup_directory
    analyze_backup_contents
    check_backup_age
    check_backup_sizes
    check_disk_space
    list_backup_files
    generate_summary

    exit $EXIT_CODE
}

# Run main
main "$@"

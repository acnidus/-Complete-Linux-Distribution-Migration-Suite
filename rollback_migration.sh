#!/bin/bash

# =============================================================================
# Migration Rollback Script
# =============================================================================
# 
# This script provides emergency rollback functionality to restore a system
# to its previous state if a migration fails or causes issues.
# 
# IMPORTANT: 
# - This script should only be used in emergency situations
# - Ensure you have a valid backup before attempting rollback
# - Rollback may not restore all custom configurations
# - Some data loss may occur during rollback
#
# Author: System Administrator
# Version: 1.0
# Last Updated: 2024
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/migration_rollback.log"
BACKUP_DIR="/backup/pre_migration"
MIGRATION_STATE_FILE="/var/lib/migration_state"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check if backup exists
check_backup_exists() {
    log "Checking backup availability..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found: $BACKUP_DIR"
        error "Cannot proceed with rollback without a valid backup"
        exit 1
    fi
    
    if [[ ! -f "$BACKUP_DIR/installed_packages.txt" ]]; then
        error "Package list backup not found"
        error "Cannot proceed with rollback without package information"
        exit 1
    fi
    
    success "Backup verification passed"
}

# Function to detect current system state
detect_current_state() {
    log "Detecting current system state..."
    
    if [[ -f /etc/redhat-release ]]; then
        local release_content=$(cat /etc/redhat-release)
        log "Current system: $release_content"
    else
        warning "Could not determine current system state"
    fi
    
    # Check if migration state file exists
    if [[ -f "$MIGRATION_STATE_FILE" ]]; then
        log "Migration state file found, reading information..."
        source "$MIGRATION_STATE_FILE"
        log "Previous migration: $SOURCE_DISTRO $SOURCE_VERSION → $TARGET_DISTRO $TARGET_VERSION"
        log "Migration date: $MIGRATION_DATE"
    else
        warning "Migration state file not found, proceeding with basic rollback"
    fi
}

# Function to create rollback plan
create_rollback_plan() {
    log "Creating rollback plan..."
    
    echo
    echo "============================================================================="
    echo "ROLLBACK PLAN"
    echo "============================================================================="
    echo
    echo "The following actions will be performed:"
    echo "1. Stop critical services that might conflict"
    echo "2. Restore configuration files from backup"
    echo "3. Restore package repositories"
    echo "4. Reinstall original distribution packages"
    echo "5. Restore system identification"
    echo "6. Reboot system"
    echo
    echo "WARNING: This process will overwrite current system configuration!"
    echo
    
    read -p "Do you want to proceed with rollback? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Rollback cancelled by user"
        exit 0
    fi
    
    # Additional confirmation for destructive operation
    echo
    echo "FINAL WARNING: This operation will modify your system!"
    echo "Ensure you have saved any important work and have a recovery plan."
    echo
    read -p "Type 'ROLLBACK' to confirm: " -r
    if [[ "$REPLY" != "ROLLBACK" ]]; then
        log "Rollback cancelled - confirmation text did not match"
        exit 0
    fi
}

# Function to stop conflicting services
stop_conflicting_services() {
    log "Stopping potentially conflicting services..."
    
    local services_to_stop=(
        "subscription-manager"
        "rhsmcertd"
        "cockpit"
        "firewalld"
        "sshd"
    )
    
    for service in "${services_to_stop[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log "Stopping service: $service"
            systemctl stop "$service" || warning "Could not stop $service"
        fi
    done
    
    success "Conflicting services stopped"
}

# Function to restore configuration files
restore_config_files() {
    log "Restoring configuration files from backup..."
    
    # Restore critical configuration files
    local config_files=(
        "/etc/passwd"
        "/etc/group"
        "/etc/shadow"
        "/etc/gshadow"
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/fstab"
        "/etc/ssh/sshd_config"
        "/etc/sysconfig/network-scripts/"
        "/etc/selinux/config"
        "/etc/systemd/system/"
        "/etc/crontab"
        "/var/spool/cron/"
    )
    
    for file in "${config_files[@]}"; do
        local backup_file="$BACKUP_DIR/$(basename "$file")"
        if [[ -e "$backup_file" ]]; then
            log "Restoring: $file"
            cp -r "$backup_file" "$file" 2>/dev/null || warning "Could not restore $file"
        fi
    done
    
    # Restore distribution-specific release files
    if [[ -f "$BACKUP_DIR/redhat-release" ]]; then
        cp "$BACKUP_DIR/redhat-release" /etc/redhat-release
    elif [[ -f "$BACKUP_DIR/centos-release" ]]; then
        cp "$BACKUP_DIR/centos-release" /etc/redhat-release
        cp "$BACKUP_DIR/centos-release" /etc/centos-release
    elif [[ -f "$BACKUP_DIR/oracle-release" ]]; then
        cp "$BACKUP_DIR/oracle-release" /etc/redhat-release
        cp "$BACKUP_DIR/oracle-release" /etc/oracle-release
    fi
    
    success "Configuration files restored"
}

# Function to restore package repositories
restore_package_repositories() {
    log "Restoring package repositories..."
    
    # Remove current repositories
    rm -rf /etc/yum.repos.d/*
    
    # Restore original repositories from backup
    if [[ -d "$BACKUP_DIR/yum.repos.d" ]]; then
        cp -r "$BACKUP_DIR/yum.repos.d"/* /etc/yum.repos.d/ 2>/dev/null || warning "Could not restore repositories"
    fi
    
    # Restore EPEL if it was backed up
    if [[ -f "$BACKUP_DIR/epel.repo" ]]; then
        cp "$BACKUP_DIR/epel.repo" /etc/yum.repos.d/
    fi
    
    success "Package repositories restored"
}

# Function to reinstall original distribution packages
reinstall_original_packages() {
    log "Reinstalling original distribution packages..."
    
    # Clean package cache
    if command -v dnf &> /dev/null; then
        dnf clean all
    elif command -v yum &> /dev/null; then
        yum clean all
    fi
    
    # Determine which package manager to use
    local package_manager=""
    if command -v dnf &> /dev/null; then
        package_manager="dnf"
    elif command -v yum &> /dev/null; then
        package_manager="yum"
    else
        error "No package manager found (dnf or yum)"
        exit 1
    fi
    
    # Reinstall distribution release package based on backup
    if [[ -f "$BACKUP_DIR/redhat-release" ]]; then
        log "Reinstalling Red Hat release package..."
        $package_manager install -y redhat-release redhat-release-eula
    elif [[ -f "$BACKUP_DIR/centos-release" ]]; then
        log "Reinstalling CentOS release package..."
        $package_manager install -y centos-release centos-linux-repos
    elif [[ -f "$BACKUP_DIR/oracle-release" ]]; then
        log "Reinstalling Oracle Linux release package..."
        $package_manager install -y oraclelinux-release oraclelinux-release-notes
    fi
    
    # Update package cache
    log "Updating package cache..."
    if [[ "$package_manager" == "dnf" ]]; then
        dnf makecache
    else
        yum makecache
    fi
    
    success "Original distribution packages reinstalled"
}

# Function to verify rollback
verify_rollback() {
    log "Verifying rollback..."
    
    # Check if system now identifies as the original distribution
    if [[ -f /etc/redhat-release ]]; then
        local release_content=$(cat /etc/redhat-release)
        log "System now shows: $release_content"
        
        # Check if it's no longer Rocky Linux
        if ! echo "$release_content" | grep -q "Rocky Linux"; then
            success "System successfully rolled back from Rocky Linux"
        else
            warning "System still shows as Rocky Linux, rollback may be incomplete"
        fi
    fi
    
    # Check if original repositories are working
    if command -v dnf &> /dev/null; then
        if dnf repolist | grep -v "rocky" | grep -q "repo"; then
            success "Original repositories are working"
        else
            warning "Original repositories may not be working properly"
        fi
    elif command -v yum &> /dev/null; then
        if yum repolist | grep -v "rocky" | grep -q "repo"; then
            success "Original repositories are working"
        else
            warning "Original repositories may not be working properly"
        fi
    fi
    
    # Check system health
    log "Performing system health check..."
    if systemctl is-system-running --quiet; then
        success "System is running normally"
    else
        warning "System may have issues. Check systemctl status"
    fi
    
    return 0
}

# Function to create rollback state file
create_rollback_state() {
    local rollback_state_file="/var/lib/rollback_state"
    cat > "$rollback_state_file" << EOF
ROLLBACK_COMPLETED=true
ROLLBACK_DATE=$(date)
ORIGINAL_BACKUP=$BACKUP_DIR
ROLLBACK_LOG=$LOG_FILE
EOF
    
    success "Rollback state file created: $rollback_state_file"
}

# Function to display post-rollback instructions
display_post_rollback_instructions() {
    echo
    echo "============================================================================="
    echo "ROLLBACK COMPLETED!"
    echo "============================================================================="
    echo
    echo "Your system has been rolled back to its previous state."
    echo
    echo "POST-ROLLBACK TASKS:"
    echo "1. Reboot your system: reboot"
    echo "2. Verify all services are running: systemctl status"
    echo "3. Check application functionality"
    echo "4. Verify network connectivity"
    echo "5. Test critical applications and services"
    echo
    echo "IMPORTANT NOTES:"
    echo "- Backup location: $BACKUP_DIR"
    echo "- Rollback log: $LOG_FILE"
    echo "- Some custom configurations may need to be reapplied"
    echo "- Consider reviewing system logs for any issues"
    echo
    echo "If you encounter issues, check the log file: $LOG_FILE"
    echo "You may need to manually restore additional configurations."
    echo
}

# Function to handle errors during rollback
handle_rollback_error() {
    error "Rollback failed at step: $1"
    error "Check the log file: $LOG_FILE"
    echo
    echo "EMERGENCY RECOVERY OPTIONS:"
    echo "1. Try to boot from rescue mode or live CD"
    echo "2. Restore from system backup if available"
    echo "3. Reinstall the original distribution"
    echo "4. Contact system administrator or vendor support"
    echo
    echo "Current system state may be unstable!"
    exit 1
}

# Main rollback function
main() {
    echo "============================================================================="
    echo "Migration Rollback Script"
    echo "============================================================================="
    echo
    
    # Redirect all output to log file
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    
    log "Starting rollback process..."
    
    # Check prerequisites
    check_root
    check_backup_exists
    detect_current_state
    
    # Create rollback plan and get confirmation
    create_rollback_plan
    
    # Perform rollback steps
    stop_conflicting_services
    restore_config_files
    restore_package_repositories
    reinstall_original_packages
    
    # Verify rollback
    if verify_rollback; then
        create_rollback_state
        display_post_rollback_instructions
        success "Rollback completed successfully!"
    else
        handle_rollback_error "verification"
    fi
}

# Trap errors and provide emergency recovery information
trap 'handle_rollback_error "unknown"' ERR

# Run main function
main "$@"

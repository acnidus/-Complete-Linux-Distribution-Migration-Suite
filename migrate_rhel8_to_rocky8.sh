#!/bin/bash

# =============================================================================
# Red Hat Enterprise Linux 8 to Rocky Linux 8 Migration Script
# =============================================================================
# 
# This script migrates a system from Red Hat Enterprise Linux 8.x to Rocky Linux 8.x
# 
# IMPORTANT: 
# - ALWAYS backup your system before running this script
# - Test this migration in a non-production environment first
# - Ensure you have a recovery plan and rollback strategy
# - This script requires root privileges
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
LOG_FILE="/var/log/rhel8_to_rocky8_migration.log"
BACKUP_DIR="/backup/pre_migration"
ROLLBACK_FILE="/etc/yum.repos.d/rhel8_rollback.repo"
MIGRATION_STATE_FILE="/var/lib/migration_state"

# Rocky Linux repositories
ROCKY_REPOS=(
    "https://dl.rockylinux.org/pub/rocky/8/BaseOS/x86_64/os/"
    "https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/"
    "https://dl.rockylinux.org/pub/rocky/8/PowerTools/x86_64/os/"
    "https://dl.rockylinux.org/pub/rocky/8/Devel/x86_64/os/"
)

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check if this is actually RHEL 8
    if ! grep -q "Red Hat Enterprise Linux release 8" /etc/redhat-release 2>/dev/null; then
        error "This system is not running Red Hat Enterprise Linux 8"
        error "Current system: $(cat /etc/redhat-release)"
        exit 1
    fi
    
    # Check available disk space (need at least 5GB free)
    local free_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=5242880  # 5GB in KB
    
    if [[ $free_space -lt $required_space ]]; then
        error "Insufficient disk space. Need at least 5GB free, have $((free_space/1024))MB"
        exit 1
    fi
    
    # Check if system is registered with Red Hat
    if subscription-manager status 2>/dev/null | grep -q "Overall Status: Current"; then
        warning "System is registered with Red Hat. Consider unregistering before migration."
    fi
    
    success "System requirements check passed"
}

# Function to create backup
create_backup() {
    log "Creating system backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup important configuration files
    local config_files=(
        "/etc/yum.repos.d/"
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
        if [[ -e "$file" ]]; then
            cp -r "$file" "$BACKUP_DIR/" 2>/dev/null || warning "Could not backup $file"
        fi
    done
    
    # Backup package list
    rpm -qa --queryformat="%{NAME}\n" | sort > "$BACKUP_DIR/installed_packages.txt"
    
    # Backup repository configuration
    cp -r /etc/yum.repos.d/* "$BACKUP_DIR/" 2>/dev/null || warning "Could not backup repositories"
    
    success "Backup created in $BACKUP_DIR"
}

# Function to verify backup
verify_backup() {
    log "Verifying backup..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found"
        exit 1
    fi
    
    if [[ ! -f "$BACKUP_DIR/installed_packages.txt" ]]; then
        error "Package list backup not found"
        exit 1
    fi
    
    success "Backup verification passed"
}

# Function to create rollback repository
create_rollback_repo() {
    log "Creating rollback repository configuration..."
    
    cat > "$ROLLBACK_FILE" << EOF
# Rollback repository for RHEL 8
# This file contains the original RHEL 8 repository configuration
# Use this to rollback if migration fails

[rhel8-base]
name=Red Hat Enterprise Linux 8 - BaseOS
baseurl=https://cdn.redhat.com/content/dist/rhel8/8/x86_64/baseos/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel8-appstream]
name=Red Hat Enterprise Linux 8 - AppStream
baseurl=https://cdn.redhat.com/content/dist/rhel8/8/x86_64/appstream/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
    
    success "Rollback repository configuration created"
}

# Function to prepare system for migration
prepare_system() {
    log "Preparing system for migration..."
    
    # Update system to latest packages
    log "Updating system packages..."
    dnf update -y || warning "Some packages could not be updated"
    
    # Clean package cache
    dnf clean all
    
    # Disable Red Hat repositories
    log "Disabling Red Hat repositories..."
    for repo in /etc/yum.repos.d/redhat*; do
        if [[ -f "$repo" ]]; then
            sed -i 's/enabled=1/enabled=0/g' "$repo"
        fi
    done
    
    # Remove Red Hat specific packages that might conflict
    log "Removing Red Hat specific packages..."
    dnf remove -y redhat-release redhat-release-eula || warning "Could not remove Red Hat release packages"
    
    success "System preparation completed"
}

# Function to install Rocky Linux repositories
install_rocky_repos() {
    log "Installing Rocky Linux repositories..."
    
    # Download and install Rocky Linux GPG key
    log "Installing Rocky Linux GPG key..."
    rpm --import https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-rockyofficial
    
    # Create Rocky Linux repository files
    cat > /etc/yum.repos.d/rocky-base.repo << EOF
[rocky-base]
name=Rocky Linux 8 - BaseOS
baseurl=https://dl.rockylinux.org/pub/rocky/8/BaseOS/x86_64/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF

    cat > /etc/yum.repos.d/rocky-appstream.repo << EOF
[rocky-appstream]
name=Rocky Linux 8 - AppStream
baseurl=https://dl.rockylinux.org/pub/rocky/8/AppStream/x86_64/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF

    cat > /etc/yum.repos.d/rocky-powertools.repo << EOF
[rocky-powertools]
name=Rocky Linux 8 - PowerTools
baseurl=https://dl.rockylinux.org/pub/rocky/8/PowerTools/x86_64/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF

    cat > /etc/yum.repos.d/rocky-devel.repo << EOF
[rocky-devel]
name=Rocky Linux 8 - Devel
baseurl=https://dl.rockylinux.org/pub/rocky/8/Devel/x86_64/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF
    
    success "Rocky Linux repositories installed"
}

# Function to perform the migration
perform_migration() {
    log "Starting migration process..."
    
    # Update package cache with new repositories
    log "Updating package cache..."
    dnf clean all
    dnf makecache
    
    # Install Rocky Linux release package
    log "Installing Rocky Linux release package..."
    dnf install -y rocky-release
    
    # Update all packages to Rocky Linux versions
    log "Updating packages to Rocky Linux versions..."
    dnf update -y --allowerasing
    
    # Install Rocky Linux specific packages
    log "Installing Rocky Linux specific packages..."
    dnf install -y rocky-logos rocky-backgrounds
    
    # Clean up old Red Hat packages
    log "Cleaning up old Red Hat packages..."
    dnf autoremove -y
    
    success "Migration completed successfully"
}

# Function to verify migration
verify_migration() {
    log "Verifying migration..."
    
    # Check if system now identifies as Rocky Linux
    if grep -q "Rocky Linux release 8" /etc/redhat-release; then
        success "System successfully migrated to Rocky Linux 8"
    else
        error "Migration verification failed. System still shows as: $(cat /etc/redhat-release)"
        return 1
    fi
    
    # Check if Rocky Linux repositories are working
    if dnf repolist | grep -q "rocky"; then
        success "Rocky Linux repositories are working"
    else
        warning "Rocky Linux repositories may not be working properly"
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

# Function to create migration state file
create_migration_state() {
    cat > "$MIGRATION_STATE_FILE" << EOF
MIGRATION_COMPLETED=true
SOURCE_DISTRO=Red Hat Enterprise Linux 8
TARGET_DISTRO=Rocky Linux 8
MIGRATION_DATE=$(date)
BACKUP_LOCATION=$BACKUP_DIR
ROLLBACK_REPO=$ROLLBACK_FILE
EOF
}

# Function to display post-migration instructions
display_post_migration_instructions() {
    echo
    echo "============================================================================="
    echo "MIGRATION COMPLETED SUCCESSFULLY!"
    echo "============================================================================="
    echo
    echo "Your system has been migrated from Red Hat Enterprise Linux 8 to Rocky Linux 8."
    echo
    echo "POST-MIGRATION TASKS:"
    echo "1. Reboot your system: reboot"
    echo "2. Verify all services are running: systemctl status"
    echo "3. Check application functionality"
    echo "4. Update any custom scripts or configurations"
    echo "5. Test critical applications and services"
    echo
    echo "IMPORTANT NOTES:"
    echo "- Backup location: $BACKUP_DIR"
    echo "- Rollback configuration: $ROLLBACK_FILE"
    echo "- Migration log: $LOG_FILE"
    echo "- Some applications may need reconfiguration"
    echo "- Consider updating your monitoring and backup tools"
    echo
    echo "If you encounter issues, check the log file: $LOG_FILE"
    echo "For rollback instructions, see the README file."
    echo
}

# Function to handle errors and provide rollback instructions
handle_error() {
    error "Migration failed at step: $1"
    error "Check the log file: $LOG_FILE"
    echo
    echo "ROLLBACK INSTRUCTIONS:"
    echo "1. Restore from backup: cp -r $BACKUP_DIR/* /"
    echo "2. Re-enable Red Hat repositories"
    echo "3. Reinstall Red Hat release package"
    echo "4. Reboot the system"
    echo
    echo "For detailed rollback instructions, see the README file."
    exit 1
}

# Main migration function
main() {
    echo "============================================================================="
    echo "Red Hat Enterprise Linux 8 to Rocky Linux 8 Migration Script"
    echo "============================================================================="
    echo
    
    # Redirect all output to log file
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    
    log "Starting migration process..."
    
    # Check prerequisites
    check_root
    check_system_requirements
    
    # Create backup
    create_backup
    verify_backup
    
    # Create rollback configuration
    create_rollback_repo
    
    # Prepare system
    prepare_system
    
    # Install Rocky Linux repositories
    install_rocky_repos
    
    # Perform migration
    perform_migration
    
    # Verify migration
    if verify_migration; then
        create_migration_state
        display_post_migration_instructions
        success "Migration completed successfully!"
    else
        handle_error "verification"
    fi
}

# Trap errors and provide rollback information
trap 'handle_error "unknown"' ERR

# Run main function
main "$@"

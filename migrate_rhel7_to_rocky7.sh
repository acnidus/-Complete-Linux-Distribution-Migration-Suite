#!/bin/bash

# =============================================================================
# Red Hat Enterprise Linux 7 to Rocky Linux 7 Migration Script
# =============================================================================
# 
# This script migrates a system from Red Hat Enterprise Linux 7.x to Rocky Linux 7.x
# 
# IMPORTANT: 
# - ALWAYS backup your system before running this script
# - Test this migration in a non-production environment first
# - Ensure you have a recovery plan and rollback strategy
# - This script requires root privileges
# - RHEL 7 reached EOL in June 2024, migration is highly recommended
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
LOG_FILE="/var/log/rhel7_to_rocky7_migration.log"
BACKUP_DIR="/backup/pre_migration"
ROLLBACK_FILE="/etc/yum.repos.d/rhel7_rollback.repo"
MIGRATION_STATE_FILE="/var/lib/migration_state"

# Rocky Linux repositories for RHEL 7 style
ROCKY_REPOS=(
    "https://dl.rockylinux.org/pub/rocky/7/os/x86_64/"
    "https://dl.rockylinux.org/pub/rocky/7/updates/x86_64/"
    "https://dl.rockylinux.org/pub/rocky/7/extras/x86_64/"
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
    
    # Check if this is actually RHEL 7
    if ! grep -q "Red Hat Enterprise Linux Server release 7" /etc/redhat-release 2>/dev/null; then
        error "This system is not running Red Hat Enterprise Linux Server 7"
        error "Current system: $(cat /etc/redhat-release)"
        exit 1
    fi
    
    # Check RHEL version
    local rhel_version=$(grep -o 'release [0-9]\+' /etc/redhat-release | awk '{print $2}')
    if [[ "$rhel_version" != "7" ]]; then
        error "This script is designed for RHEL 7, but system shows version $rhel_version"
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
    
    # Check if system is up to date
    log "Checking if system is up to date..."
    yum check-update --quiet || warning "System has available updates. Consider updating first."
    
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
        "/etc/redhat-release"
        "/etc/system-release"
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
    
    # Backup EPEL configuration if present
    if [[ -f /etc/yum.repos.d/epel.repo ]]; then
        cp /etc/yum.repos.d/epel.repo "$BACKUP_DIR/"
    fi
    
    # Backup subscription information
    if command -v subscription-manager &> /dev/null; then
        subscription-manager list --installed > "$BACKUP_DIR/subscription_info.txt" 2>/dev/null || warning "Could not backup subscription information"
    fi
    
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
# Rollback repository for RHEL 7
# This file contains the original RHEL 7 repository configuration
# Use this to rollback if migration fails

[rhel7-base]
name=Red Hat Enterprise Linux 7 - Base
baseurl=https://cdn.redhat.com/content/dist/rhel7/7/x86_64/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel7-updates]
name=Red Hat Enterprise Linux 7 - Updates
baseurl=https://cdn.redhat.com/content/dist/rhel7/7/x86_64/updates/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel7-extras]
name=Red Hat Enterprise Linux 7 - Extras
baseurl=https://cdn.redhat.com/content/dist/rhel7/7/x86_64/extras/
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
    yum update -y || warning "Some packages could not be updated"
    
    # Clean package cache
    yum clean all
    
    # Disable Red Hat repositories
    log "Disabling Red Hat repositories..."
    for repo in /etc/yum.repos.d/redhat*; do
        if [[ -f "$repo" ]]; then
            sed -i 's/enabled=1/enabled=0/g' "$repo"
        fi
    done
    
    # Remove Red Hat specific packages that might conflict
    log "Removing Red Hat specific packages..."
    yum remove -y redhat-release redhat-release-eula redhat-logos || warning "Could not remove Red Hat release packages"
    
    # Remove EPEL if present (will be reinstalled for Rocky Linux)
    if yum list installed | grep -q epel-release; then
        log "Removing EPEL repository..."
        yum remove -y epel-release
    fi
    
    success "System preparation completed"
}

# Function to install Rocky Linux repositories
install_rocky_repos() {
    log "Installing Rocky Linux repositories..."
    
    # Download and install Rocky Linux GPG key
    log "Installing Rocky Linux GPG key..."
    rpm --import https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-rockyofficial
    
    # Create Rocky Linux repository files for RHEL 7 style
    cat > /etc/yum.repos.d/rocky-base.repo << EOF
[rocky-base]
name=Rocky Linux 7 - Base
baseurl=https://dl.rockylinux.org/pub/rocky/7/os/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
EOF

    cat > /etc/yum.repos.d/rocky-updates.repo << EOF
[rocky-updates]
name=Rocky Linux 7 - Updates
baseurl=https://dl.rockylinux.org/pub/rocky/7/updates/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
EOF

    cat > /etc/yum.repos.d/rocky-extras.repo << EOF
[rocky-extras]
name=Rocky Linux 7 - Extras
baseurl=https://dl.rockylinux.org/pub/rocky/7/extras/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
EOF

    # Install EPEL for Rocky Linux
    log "Installing EPEL repository for Rocky Linux..."
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm
    
    success "Rocky Linux repositories installed"
}

# Function to perform the migration
perform_migration() {
    log "Starting migration process..."
    
    # Update package cache with new repositories
    log "Updating package cache..."
    yum clean all
    yum makecache
    
    # Install Rocky Linux release package
    log "Installing Rocky Linux release package..."
    yum install -y rocky-release
    
    # Update all packages to Rocky Linux versions
    log "Updating packages to Rocky Linux versions..."
    yum update -y
    
    # Install Rocky Linux specific packages
    log "Installing Rocky Linux specific packages..."
    yum install -y rocky-logos rocky-backgrounds
    
    # Clean up old Red Hat packages
    log "Cleaning up old Red Hat packages..."
    yum autoremove -y
    
    success "Migration completed successfully"
}

# Function to verify migration
verify_migration() {
    log "Verifying migration..."
    
    # Check if system now identifies as Rocky Linux
    if grep -q "Rocky Linux release 7" /etc/redhat-release; then
        success "System successfully migrated to Rocky Linux 7"
    else
        error "Migration verification failed. System still shows as: $(cat /etc/redhat-release)"
        return 1
    fi
    
    # Check if Rocky Linux repositories are working
    if yum repolist | grep -q "rocky"; then
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
SOURCE_DISTRO=Red Hat Enterprise Linux 7
TARGET_DISTRO=Rocky Linux 7
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
    echo "Your system has been migrated from Red Hat Enterprise Linux 7 to Rocky Linux 7."
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
    echo "- Rocky Linux 7 will be supported until June 2024"
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
    echo "Red Hat Enterprise Linux 7 to Rocky Linux 7 Migration Script"
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

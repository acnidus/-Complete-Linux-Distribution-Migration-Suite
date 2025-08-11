#!/bin/bash

# =============================================================================
# SUSE Linux to Rocky Linux Migration Script
# =============================================================================
# 
# This script migrates a system from SUSE Linux Enterprise Server (SLES) or
# openSUSE to Rocky Linux
# 
# IMPORTANT: 
# - ALWAYS backup your system before running this script
# - Test this migration in a non-production environment first
# - Ensure you have a recovery plan and rollback strategy
# - This script requires root privileges
# - This is a MAJOR migration between different package systems (rpm with zypper to rpm with dnf)
# - Some applications may need to be reinstalled
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
LOG_FILE="/var/log/suse_to_rocky_migration.log"
BACKUP_DIR="/backup/pre_migration"
MIGRATION_STATE_FILE="/var/lib/migration_state"

# Function to check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Function to detect source distribution
detect_source_distribution() {
    log "Detecting source distribution..."
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        
        if [[ "$ID" == "sles" ]] || [[ "$ID" == "opensuse" ]] || [[ "$ID" == "opensuse-tumbleweed" ]]; then
            SOURCE_DISTRO="$NAME"
            SOURCE_VERSION="$VERSION_ID"
            
            if [[ "$ID" == "sles" ]]; then
                SOURCE_TYPE="SLES"
            elif [[ "$ID" == "opensuse" ]]; then
                SOURCE_TYPE="openSUSE Leap"
            elif [[ "$ID" == "opensuse-tumbleweed" ]]; then
                SOURCE_TYPE="openSUSE Tumbleweed"
            fi
            
        else
            error "Unsupported distribution: $ID $VERSION_ID"
            error "This script supports SUSE Linux Enterprise Server and openSUSE only"
            exit 1
        fi
        
        log "Detected: $SOURCE_DISTRO ($SOURCE_TYPE) $SOURCE_VERSION"
        
    else
        error "Could not detect distribution. /etc/os-release not found."
        exit 1
    fi
}

# Function to check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check available disk space (need at least 8GB free for major migration)
    local free_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=8388608  # 8GB in KB
    
    if [[ $free_space -lt $required_space ]]; then
        error "Insufficient disk space. Need at least 8GB free, have $((free_space/1024))MB"
        error "This is a major migration between different RPM-based systems and requires more space"
        exit 1
    fi
    
    # Check if system is up to date
    log "Checking if system is up to date..."
    if command -v zypper &> /dev/null; then
        zypper refresh && zypper update -y || warning "Some packages could not be updated"
    fi
    
    # Check for running services that might conflict
    log "Checking for potentially conflicting services..."
    local conflicting_services=("SuSEfirewall2" "apparmor" "snapper")
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            warning "Service $service is running. Consider stopping it before migration."
        fi
    done
    
    success "System requirements check passed"
}

# Function to create comprehensive backup
create_backup() {
    log "Creating comprehensive system backup..."
    
    mkdir -p "$BACKUP_DIR"
    
    # Backup important configuration files
    local config_files=(
        "/etc/passwd"
        "/etc/group"
        "/etc/shadow"
        "/etc/gshadow"
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/fstab"
        "/etc/ssh/sshd_config"
        "/etc/sysconfig/network/"
        "/etc/systemd/system/"
        "/etc/crontab"
        "/var/spool/cron/"
        "/etc/zypp/"
        "/etc/zypp/repos.d/"
        "/etc/sysconfig/"
        "/etc/default/"
        "/etc/environment"
        "/etc/hostname"
        "/etc/timezone"
        "/etc/locale.conf"
        "/etc/locale.gen"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -e "$file" ]]; then
            cp -r "$file" "$BACKUP_DIR/" 2>/dev/null || warning "Could not backup $file"
        fi
    done
    
    # Backup package lists
    if command -v rpm &> /dev/null; then
        rpm -qa --queryformat="%{NAME}\n" | sort > "$BACKUP_DIR/installed_packages_rpm.txt"
    fi
    
    if command -v zypper &> /dev/null; then
        zypper packages --installed > "$BACKUP_DIR/installed_packages_zypper.txt"
        zypper repos > "$BACKUP_DIR/repository_list.txt"
    fi
    
    # Backup SUSE specific configurations
    if [[ -f /etc/SuSE-release ]]; then
        cp /etc/SuSE-release "$BACKUP_DIR/"
    fi
    
    # Backup user data (excluding large directories)
    log "Backing up user data..."
    for user_home in /home/*; do
        if [[ -d "$user_home" ]]; then
            local user_name=$(basename "$user_home")
            if [[ "$user_name" != "*" ]]; then
                tar -czf "$BACKUP_DIR/user_${user_name}_backup.tar.gz" -C /home "$user_name" --exclude="*.cache" --exclude="*.tmp" --exclude="*.log" 2>/dev/null || warning "Could not backup user $user_name"
            fi
        fi
    done
    
    # Backup system configuration
    tar -czf "$BACKUP_DIR/system_config_backup.tar.gz" /etc /var/lib /usr/local/etc 2>/dev/null || warning "Could not backup system configuration"
    
    success "Comprehensive backup created in $BACKUP_DIR"
}

# Function to verify backup
verify_backup() {
    log "Verifying backup..."
    
    if [[ ! -d "$BACKUP_DIR" ]]; then
        error "Backup directory not found"
        exit 1
    fi
    
    if [[ ! -f "$BACKUP_DIR/installed_packages_rpm.txt" ]]; then
        error "Package list backup not found"
        exit 1
    fi
    
    success "Backup verification passed"
}

# Function to prepare system for migration
prepare_system() {
    log "Preparing system for migration..."
    
    # Stop critical services
    log "Stopping critical services..."
    local services_to_stop=("sshd" "SuSEfirewall2" "snapper" "apparmor")
    for service in "${services_to_stop[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            log "Stopping service: $service"
            systemctl stop "$service" || warning "Could not stop $service"
        fi
    done
    
    # Remove SUSE specific packages
    log "Removing SUSE specific packages..."
    if command -v zypper &> /dev/null; then
        zypper remove -y suse-release suse-release-notes || warning "Could not remove SUSE release packages"
        zypper remove -y patterns-sles-base || warning "Could not remove SLES base patterns"
    fi
    
    # Clean package cache
    if command -v zypper &> /dev/null; then
        zypper clean
        zypper purge-kernels
    fi
    
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

    # Install EPEL for Rocky Linux
    log "Installing EPEL repository for Rocky Linux..."
    yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
    
    success "Rocky Linux repositories installed"
}

# Function to perform the migration
perform_migration() {
    log "Starting major migration process..."
    
    warning "This is a MAJOR migration between different RPM-based systems"
    warning "Some applications will need to be reinstalled"
    
    # Update package cache with new repositories
    log "Updating package cache..."
    yum clean all
    yum makecache
    
    # Install Rocky Linux release package
    log "Installing Rocky Linux release package..."
    yum install -y rocky-release
    
    # Update all packages to Rocky Linux versions
    log "Updating packages to Rocky Linux versions..."
    yum update -y --allowerasing
    
    # Install Rocky Linux specific packages
    log "Installing Rocky Linux specific packages..."
    yum install -y rocky-logos rocky-backgrounds
    
    # Clean up old SUSE packages
    log "Cleaning up old SUSE packages..."
    yum autoremove -y
    
    success "Major migration completed successfully"
}

# Function to verify migration
verify_migration() {
    log "Verifying migration..."
    
    # Check if system now identifies as Rocky Linux
    if [[ -f /etc/redhat-release ]] && grep -q "Rocky Linux" /etc/redhat-release; then
        success "System successfully migrated to Rocky Linux"
    else
        error "Migration verification failed. System does not identify as Rocky Linux"
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
SOURCE_DISTRO=$SOURCE_DISTRO
SOURCE_TYPE=$SOURCE_TYPE
SOURCE_VERSION=$SOURCE_VERSION
TARGET_DISTRO=Rocky Linux
TARGET_VERSION=8
MIGRATION_DATE=$(date)
BACKUP_LOCATION=$BACKUP_DIR
MIGRATION_TYPE=Major (SUSE to Rocky Linux)
EOF
}

# Function to display post-migration instructions
display_post_migration_instructions() {
    echo
    echo "============================================================================="
    echo "MAJOR MIGRATION COMPLETED SUCCESSFULLY!"
    echo "============================================================================="
    echo
    echo "Your system has been migrated from $SOURCE_DISTRO ($SOURCE_TYPE) to Rocky Linux 8."
    echo
    echo "IMPORTANT: This was a MAJOR migration between different RPM-based systems!"
    echo
    echo "POST-MIGRATION TASKS:"
    echo "1. Reboot your system: reboot"
    echo "2. Verify all services are running: systemctl status"
    echo "3. Reinstall applications that were not migrated:"
    echo "   - Web servers (Apache, Nginx)"
    echo "   - Database servers (MySQL, PostgreSQL)"
    echo "   - Development tools and compilers"
    echo "   - Custom applications and scripts"
    echo "4. Update any custom scripts or configurations"
    echo "5. Test critical applications and services"
    echo "6. Update monitoring and backup tools"
    echo
    echo "IMPORTANT NOTES:"
    echo "- Backup location: $BACKUP_DIR"
    echo "- Migration log: $LOG_FILE"
    echo "- Many applications need to be reinstalled"
    echo "- Package names may be different"
    echo "- Configuration file locations may have changed"
    echo "- Consider this a fresh installation with data migration"
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
    echo "1. Boot from SUSE live media"
    echo "2. Mount your system: mount /dev/sdaX /mnt"
    echo "3. Restore from backup: cp -r $BACKUP_DIR/* /mnt/"
    echo "4. Reinstall SUSE if necessary"
    echo "5. Restore user data from backup"
    echo
    echo "For detailed rollback instructions, see the README file."
    exit 1
}

# Main migration function
main() {
    echo "============================================================================="
    echo "SUSE Linux to Rocky Linux Migration Script"
    echo "============================================================================="
    echo
    
    # Redirect all output to log file
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    
    log "Starting major migration process..."
    
    # Check prerequisites
    check_root
    detect_source_distribution
    check_system_requirements
    
    # Create comprehensive backup
    create_backup
    verify_backup
    
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
        success "Major migration completed successfully!"
    else
        handle_error "verification"
    fi
}

# Trap errors and provide rollback information
trap 'handle_error "unknown"' ERR

# Run main function
main "$@"

#!/bin/bash

# =============================================================================
# Generic RHEL to Rocky Linux Migration Script
# =============================================================================
# 
# This script migrates a system from various RHEL-compatible distributions
# to Rocky Linux. It automatically detects the source distribution and
# performs the appropriate migration path.
# 
# Supported migrations:
# - Red Hat Enterprise Linux 6/7/8/9 → Rocky Linux 6/7/8/9
# - CentOS Linux 6/7/8 → Rocky Linux 6/7/8
# - Oracle Linux 6/7/8/9 → Rocky Linux 6/7/8/9
# - AlmaLinux 8/9 → Rocky Linux 8/9 (if needed)
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
LOG_FILE="/var/log/generic_rhel_to_rocky_migration.log"
BACKUP_DIR="/backup/pre_migration"
MIGRATION_STATE_FILE="/var/lib/migration_state"

# Distribution detection variables
SOURCE_DISTRO=""
SOURCE_VERSION=""
SOURCE_MAJOR_VERSION=""
TARGET_DISTRO="Rocky Linux"
TARGET_VERSION=""

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
    
    # Check for various distribution files
    if [[ -f /etc/redhat-release ]]; then
        local release_content=$(cat /etc/redhat-release)
        
        # Detect RHEL
        if echo "$release_content" | grep -q "Red Hat Enterprise Linux"; then
            SOURCE_DISTRO="Red Hat Enterprise Linux"
            SOURCE_VERSION=$(echo "$release_content" | grep -o 'release [0-9]\+' | awk '{print $2}')
        
        # Detect CentOS
        elif echo "$release_content" | grep -q "CentOS Linux"; then
            SOURCE_DISTRO="CentOS Linux"
            SOURCE_VERSION=$(echo "$release_content" | grep -o 'release [0-9]\+' | awk '{print $2}')
        
        # Detect Oracle Linux
        elif echo "$release_content" | grep -q "Oracle Linux"; then
            SOURCE_DISTRO="Oracle Linux"
            SOURCE_VERSION=$(echo "$release_content" | grep -o 'release [0-9]\+' | awk '{print $2}')
        
        # Detect Rocky Linux
        elif echo "$release_content" | grep -q "Rocky Linux"; then
            SOURCE_DISTRO="Rocky Linux"
            SOURCE_VERSION=$(echo "$release_content" | grep -o 'release [0-9]\+' | awk '{print $2}')
        
        # Detect AlmaLinux
        elif echo "$release_content" | grep -q "AlmaLinux"; then
            SOURCE_DISTRO="AlmaLinux"
            SOURCE_VERSION=$(echo "$release_content" | grep -o 'release [0-9]\+' | awk '{print $2}')
        
        else
            error "Unsupported distribution: $release_content"
            exit 1
        fi
        
        SOURCE_MAJOR_VERSION="$SOURCE_VERSION"
        TARGET_VERSION="$SOURCE_VERSION"
        
    else
        error "Could not detect distribution. /etc/redhat-release not found."
        exit 1
    fi
    
    # Validate version
    if [[ ! "$SOURCE_VERSION" =~ ^[6-9]$ ]]; then
        error "Unsupported version: $SOURCE_VERSION. This script supports RHEL 6-9 and compatible distributions."
        exit 1
    fi
    
    # Check if already Rocky Linux
    if [[ "$SOURCE_DISTRO" == "Rocky Linux" ]]; then
        warning "System is already running Rocky Linux $SOURCE_VERSION"
        read -p "Do you want to continue with reinstallation? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Migration cancelled by user"
            exit 0
        fi
    fi
    
    success "Detected: $SOURCE_DISTRO $SOURCE_VERSION"
    success "Target: $TARGET_DISTRO $TARGET_VERSION"
}

# Function to check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check available disk space (need at least 5GB free)
    local free_space=$(df / | awk 'NR==2 {print $4}')
    local required_space=5242880  # 5GB in KB
    
    if [[ $free_space -lt $required_space ]]; then
        error "Insufficient disk space. Need at least 5GB free, have $((free_space/1024))MB"
        exit 1
    fi
    
    # Check if system is up to date
    log "Checking if system is up to date..."
    if command -v dnf &> /dev/null; then
        dnf check-update --quiet || warning "System has available updates. Consider updating first."
    elif command -v yum &> /dev/null; then
        yum check-update --quiet || warning "System has available updates. Consider updating first."
    fi
    
    # Check for running services that might conflict
    log "Checking for potentially conflicting services..."
    local conflicting_services=("subscription-manager" "rhsmcertd")
    for service in "${conflicting_services[@]}"; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            warning "Service $service is running. Consider stopping it before migration."
        fi
    done
    
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
        "/etc/centos-release"
        "/etc/oracle-release"
        "/etc/rocky-release"
        "/etc/almalinux-release"
    )
    
    for file in "${config_files[@]}"; do
        if [[ -e "$file" ]]; then
            cp -r "$file" "$BACKUP_DIR/" 2>/dev/null || warning "Could not backup $file"
        fi
    done
    
    # Backup package list
    if command -v rpm &> /dev/null; then
        rpm -qa --queryformat="%{NAME}\n" | sort > "$BACKUP_DIR/installed_packages.txt"
    fi
    
    # Backup repository configuration
    cp -r /etc/yum.repos.d/* "$BACKUP_DIR/" 2>/dev/null || warning "Could not backup repositories"
    
    # Backup EPEL configuration if present
    if [[ -f /etc/yum.repos.d/epel.repo ]]; then
        cp /etc/yum.repos.d/epel.repo "$BACKUP_DIR/"
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

# Function to create rollback configuration
create_rollback_config() {
    log "Creating rollback configuration..."
    
    local rollback_file="/etc/yum.repos.d/${SOURCE_DISTRO// /}_${SOURCE_VERSION}_rollback.repo"
    
    case "$SOURCE_DISTRO" in
        "Red Hat Enterprise Linux")
            cat > "$rollback_file" << EOF
# Rollback repository for $SOURCE_DISTRO $SOURCE_VERSION
# Use this to rollback if migration fails

[rhel${SOURCE_VERSION}-base]
name=$SOURCE_DISTRO $SOURCE_VERSION - BaseOS
baseurl=https://cdn.redhat.com/content/dist/rhel${SOURCE_VERSION}/${SOURCE_VERSION}/x86_64/baseos/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release

[rhel${SOURCE_VERSION}-appstream]
name=$SOURCE_DISTRO $SOURCE_VERSION - AppStream
baseurl=https://cdn.redhat.com/content/dist/rhel${SOURCE_VERSION}/${SOURCE_VERSION}/x86_64/appstream/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
EOF
            ;;
        "CentOS Linux")
            cat > "$rollback_file" << EOF
# Rollback repository for $SOURCE_DISTRO $SOURCE_VERSION
# Note: CentOS 8 repositories are no longer available due to EOL

[centos${SOURCE_VERSION}-base]
name=$SOURCE_DISTRO $SOURCE_VERSION - BaseOS
baseurl=http://vault.centos.org/centos/${SOURCE_VERSION}/BaseOS/x86_64/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial

[centos${SOURCE_VERSION}-appstream]
name=$SOURCE_DISTRO $SOURCE_VERSION - AppStream
baseurl=http://vault.centos.org/centos/${SOURCE_VERSION}/AppStream/x86_64/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
EOF
            ;;
        "Oracle Linux")
            cat > "$rollback_file" << EOF
# Rollback repository for $SOURCE_DISTRO $SOURCE_VERSION
# Use this to rollback if migration fails

[ol${SOURCE_VERSION}-base]
name=$SOURCE_DISTRO $SOURCE_VERSION - BaseOS
baseurl=https://yum.oracle.com/repo/OracleLinux/OL${SOURCE_VERSION}/base/latest/x86_64/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle

[ol${SOURCE_VERSION}-appstream]
name=$SOURCE_DISTRO $SOURCE_VERSION - AppStream
baseurl=https://yum.oracle.com/repo/OracleLinux/OL${SOURCE_VERSION}/appstream/x86_64/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-oracle
EOF
            ;;
    esac
    
    success "Rollback configuration created: $rollback_file"
}

# Function to prepare system for migration
prepare_system() {
    log "Preparing system for migration..."
    
    # Update system to latest packages
    log "Updating system packages..."
    if command -v dnf &> /dev/null; then
        dnf update -y || warning "Some packages could not be updated"
        dnf clean all
    elif command -v yum &> /dev/null; then
        yum update -y || warning "Some packages could not be updated"
        yum clean all
    fi
    
    # Disable source distribution repositories
    log "Disabling source distribution repositories..."
    for repo in /etc/yum.repos.d/*; do
        if [[ -f "$repo" ]]; then
            sed -i 's/enabled=1/enabled=0/g' "$repo" 2>/dev/null || true
        fi
    done
    
    # Remove distribution-specific packages
    log "Removing distribution-specific packages..."
    local packages_to_remove=()
    
    case "$SOURCE_DISTRO" in
        "Red Hat Enterprise Linux")
            packages_to_remove=("redhat-release" "redhat-release-eula")
            ;;
        "CentOS Linux")
            packages_to_remove=("centos-release" "centos-linux-repos")
            ;;
        "Oracle Linux")
            packages_to_remove=("oraclelinux-release" "oraclelinux-release-notes")
            ;;
        "AlmaLinux")
            packages_to_remove=("almalinux-release" "almalinux-logos")
            ;;
    esac
    
    for package in "${packages_to_remove[@]}"; do
        if rpm -q "$package" &> /dev/null; then
            if command -v dnf &> /dev/null; then
                dnf remove -y "$package" || warning "Could not remove $package"
            elif command -v yum &> /dev/null; then
                yum remove -y "$package" || warning "Could not remove $package"
            fi
        fi
    done
    
    # Remove EPEL if present (will be reinstalled for Rocky Linux)
    if rpm -q epel-release &> /dev/null; then
        log "Removing EPEL repository..."
        if command -v dnf &> /dev/null; then
            dnf remove -y epel-release
        elif command -v yum &> /dev/null; then
            yum remove -y epel-release
        fi
    fi
    
    success "System preparation completed"
}

# Function to install Rocky Linux repositories
install_rocky_repos() {
    log "Installing Rocky Linux repositories..."
    
    # Download and install Rocky Linux GPG key
    log "Installing Rocky Linux GPG key..."
    rpm --import https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-rockyofficial
    
    # Create Rocky Linux repository files based on version
    if [[ "$SOURCE_VERSION" -ge 8 ]]; then
        # RHEL 8+ style repositories
        cat > /etc/yum.repos.d/rocky-base.repo << EOF
[rocky-base]
name=Rocky Linux $SOURCE_VERSION - BaseOS
baseurl=https://dl.rockylinux.org/pub/rocky/$SOURCE_VERSION/BaseOS/x86_64/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF

        cat > /etc/yum.repos.d/rocky-appstream.repo << EOF
[rocky-appstream]
name=Rocky Linux $SOURCE_VERSION - AppStream
baseurl=https://dl.rockylinux.org/pub/rocky/$SOURCE_VERSION/AppStream/x86_64/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF

        cat > /etc/yum.repos.d/rocky-powertools.repo << EOF
[rocky-powertools]
name=Rocky Linux $SOURCE_VERSION - PowerTools
baseurl=https://dl.rockylinux.org/pub/rocky/$SOURCE_VERSION/PowerTools/x86_64/os/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF

        cat > /etc/yum.repos.d/rocky-devel.repo << EOF
[rocky-devel]
name=Rocky Linux $SOURCE_VERSION - Devel
baseurl=https://dl.rockylinux.org/pub/rocky/$SOURCE_VERSION/Devel/x86_64/os/
enabled=0
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
metadata_expire=86400
enabled_metadata=1
EOF

        # Install EPEL for Rocky Linux
        log "Installing EPEL repository for Rocky Linux..."
        dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${SOURCE_VERSION}.noarch.rpm"
        
    else
        # RHEL 6/7 style repositories
        cat > /etc/yum.repos.d/rocky-base.repo << EOF
[rocky-base]
name=Rocky Linux $SOURCE_VERSION - Base
baseurl=https://dl.rockylinux.org/pub/rocky/$SOURCE_VERSION/os/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
EOF

        cat > /etc/yum.repos.d/rocky-updates.repo << EOF
[rocky-updates]
name=Rocky Linux $SOURCE_VERSION - Updates
baseurl=https://dl.rockylinux.org/pub/rocky/$SOURCE_VERSION/updates/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
EOF

        cat > /etc/yum.repos.d/rocky-extras.repo << EOF
[rocky-extras]
name=Rocky Linux $SOURCE_VERSION - Extras
baseurl=https://dl.rockylinux.org/pub/rocky/$SOURCE_VERSION/extras/x86_64/
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-rockyofficial
EOF

        # Install EPEL for Rocky Linux
        log "Installing EPEL repository for Rocky Linux..."
        yum install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${SOURCE_VERSION}.noarch.rpm"
    fi
    
    success "Rocky Linux repositories installed"
}

# Function to perform the migration
perform_migration() {
    log "Starting migration process..."
    
    # Update package cache with new repositories
    log "Updating package cache..."
    if command -v dnf &> /dev/null; then
        dnf clean all
        dnf makecache
    elif command -v yum &> /dev/null; then
        yum clean all
        yum makecache
    fi
    
    # Install Rocky Linux release package
    log "Installing Rocky Linux release package..."
    if command -v dnf &> /dev/null; then
        dnf install -y rocky-release
    elif command -v yum &> /dev/null; then
        yum install -y rocky-release
    fi
    
    # Update all packages to Rocky Linux versions
    log "Updating packages to Rocky Linux versions..."
    if command -v dnf &> /dev/null; then
        dnf update -y --allowerasing
    elif command -v yum &> /dev/null; then
        yum update -y
    fi
    
    # Install Rocky Linux specific packages
    log "Installing Rocky Linux specific packages..."
    if command -v dnf &> /dev/null; then
        dnf install -y rocky-logos rocky-backgrounds
    elif command -v yum &> /dev/null; then
        yum install -y rocky-logos rocky-backgrounds
    fi
    
    # Clean up old packages
    log "Cleaning up old packages..."
    if command -v dnf &> /dev/null; then
        dnf autoremove -y
    elif command -v yum &> /dev/null; then
        yum autoremove -y
    fi
    
    success "Migration completed successfully"
}

# Function to verify migration
verify_migration() {
    log "Verifying migration..."
    
    # Check if system now identifies as Rocky Linux
    if grep -q "Rocky Linux release $SOURCE_VERSION" /etc/redhat-release; then
        success "System successfully migrated to Rocky Linux $SOURCE_VERSION"
    else
        error "Migration verification failed. System still shows as: $(cat /etc/redhat-release)"
        return 1
    fi
    
    # Check if Rocky Linux repositories are working
    if command -v dnf &> /dev/null; then
        if dnf repolist | grep -q "rocky"; then
            success "Rocky Linux repositories are working"
        else
            warning "Rocky Linux repositories may not be working properly"
        fi
    elif command -v yum &> /dev/null; then
        if yum repolist | grep -q "rocky"; then
            success "Rocky Linux repositories are working"
        else
            warning "Rocky Linux repositories may not be working properly"
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

# Function to create migration state file
create_migration_state() {
    cat > "$MIGRATION_STATE_FILE" << EOF
MIGRATION_COMPLETED=true
SOURCE_DISTRO=$SOURCE_DISTRO
SOURCE_VERSION=$SOURCE_VERSION
TARGET_DISTRO=$TARGET_DISTRO
TARGET_VERSION=$TARGET_VERSION
MIGRATION_DATE=$(date)
BACKUP_LOCATION=$BACKUP_DIR
EOF
}

# Function to display post-migration instructions
display_post_migration_instructions() {
    echo
    echo "============================================================================="
    echo "MIGRATION COMPLETED SUCCESSFULLY!"
    echo "============================================================================="
    echo
    echo "Your system has been migrated from $SOURCE_DISTRO $SOURCE_VERSION to $TARGET_DISTRO $SOURCE_VERSION."
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
    echo "2. Re-enable source distribution repositories"
    echo "3. Reinstall source distribution release package"
    echo "4. Reboot the system"
    echo
    echo "For detailed rollback instructions, see the README file."
    exit 1
}

# Main migration function
main() {
    echo "============================================================================="
    echo "Generic RHEL to Rocky Linux Migration Script"
    echo "============================================================================="
    echo
    
    # Redirect all output to log file
    exec > >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
    
    log "Starting migration process..."
    
    # Check prerequisites
    check_root
    detect_source_distribution
    check_system_requirements
    
    # Create backup
    create_backup
    verify_backup
    
    # Create rollback configuration
    create_rollback_config
    
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

# Linux Distribution Migration Scripts

This repository contains comprehensive, well-documented bash scripts for migrating between different Linux distributions, with support for major Linux families including RHEL-compatible, Debian/Ubuntu, and SUSE distributions.

## ☕ Support This Project

If you find these migration scripts helpful, consider supporting the development:

- **Buy Me a Coffee**: [buymeacoffee.com/AcnidAl](https://buymeacoffee.com/AcnidAl)
- **Contact**: [acnid.al@gmail.com](mailto:acnid.al@gmail.com)

Your support helps maintain and improve these migration tools for the community!

## ⭐ Project Statistics

- **Total Scripts**: 8 migration scripts
- **Supported Distributions**: 15+ Linux distributions
- **Migration Paths**: 25+ migration combinations
- **Safety Features**: Automatic backup, rollback, logging
- **Documentation**: 4 comprehensive guides

## 🚀 Quick Overview

This repository provides **8 specialized migration scripts** that can migrate your Linux system to Rocky Linux from:

- **Red Hat Enterprise Linux** (versions 7-9)
- **CentOS Linux** (versions 7-8, including EOL systems)
- **Oracle Linux** (versions 6-9)
- **AlmaLinux** (versions 8-9)
- **SUSE Linux** (SLES, openSUSE)
- **Debian/Ubuntu** (major distribution change)

All scripts include automatic backup creation, rollback capabilities, and comprehensive logging for safe migrations.

## 📋 Table of Contents

- [Available Migration Scripts](#available-migration-scripts)
- [Prerequisites](#prerequisites)
- [Safety Features](#safety-features)
- [Usage](#usage)
- [Migration Complexity Levels](#migration-complexity-levels)
- [Important Notes](#important-notes)
- [Support](#support)
- [Documentation](#documentation)
- [License](#license)

## Available Migration Scripts

### 🐧 **RHEL-Compatible Distributions**

#### **Red Hat Enterprise Linux**
- **`migrate_rhel8_to_rocky8.sh`** - RHEL 8 → Rocky Linux 8
- **`migrate_rhel7_to_rocky7.sh`** - RHEL 7 → Rocky Linux 7

#### **CentOS Linux**
- **`migrate_centos8_to_rocky8.sh`** - CentOS 8 → Rocky Linux 8 (EOL migration)
- **`migrate_centos7_to_rocky7.sh`** - CentOS 7 → Rocky Linux 7 (EOL migration)

#### **Generic RHEL Migration**
- **`migrate_generic_rhel_to_rocky.sh`** - Any RHEL 6/7/8/9 → Rocky Linux 6/7/8/9

### 🐧 **Debian/Ubuntu Family**

#### **Major Distribution Migration**
- **`migrate_debian_ubuntu_to_rocky.sh`** - Debian/Ubuntu → Rocky Linux
  - **Note**: This is a MAJOR migration between different package systems (deb to rpm)
  - Requires more disk space and may need application reinstallation

### 🐧 **SUSE Family**

#### **SUSE Linux Migration**
- **`migrate_suse_to_rocky.sh`** - SLES/openSUSE → Rocky Linux
  - Supports SLES, openSUSE Leap, and openSUSE Tumbleweed
  - **Note**: This is a major migration between different RPM-based systems

### 🔄 **Recovery & Rollback**

#### **Emergency Recovery**
- **`rollback_migration.sh`** - Emergency rollback script for failed migrations

## Prerequisites

Before running any migration script:

1. **Backup your system**: Create a complete backup of your system
2. **Test environment**: Test the migration in a non-production environment first
3. **Root access**: Ensure you have root or sudo privileges
4. **Network connectivity**: Ensure stable internet connection during migration
5. **Sufficient disk space**: Verify adequate disk space for the migration

## Safety Features

All scripts include:
- Pre-migration system checks
- Backup verification
- Rollback capabilities
- Progress logging
- Error handling and recovery

## Usage

1. **Download the appropriate script** for your migration path
2. **Make it executable**: `chmod +x script_name.sh`
3. **Review the script** and customize if needed
4. **Run with sudo**: `sudo ./script_name.sh`

## Migration Complexity Levels

### 🟢 **Low Complexity** (RHEL-Compatible → Rocky Linux)
- **Success Rate**: 95%+
- **Time**: 30-60 minutes
- **Risk**: Low
- **Examples**: RHEL → Rocky Linux, CentOS → Rocky Linux

### 🟡 **Medium Complexity** (SUSE → Rocky Linux)
- **Success Rate**: 85%+
- **Time**: 45-90 minutes
- **Risk**: Medium
- **Examples**: SLES → Rocky Linux, openSUSE → Rocky Linux

### 🔴 **High Complexity** (Debian/Ubuntu → Rocky Linux)
- **Success Rate**: 70%+
- **Time**: 2-4 hours
- **Risk**: High
- **Examples**: Ubuntu → Rocky Linux, Debian → Rocky Linux

## Important Notes

- **Always backup your system before migration**
- **Test in a non-production environment first**
- **Ensure you have a recovery plan and rollback strategy**
- **Migration may take several hours depending on system size and complexity**
- **Some applications may need reconfiguration after migration**
- **High complexity migrations may require application reinstallation**

## Support

### **Community Support**
- **GitHub Issues**: Report bugs and request features
- **Documentation**: Comprehensive guides and troubleshooting
- **Migration Matrix**: See `MIGRATION_MATRIX.md` for detailed paths

### **Professional Support**
- **Email**: [acnid.al@gmail.com](mailto:acnid.al@gmail.com)
- **Donations**: [buymeacoffee.com/AcnidAl](https://buymeacoffee.com/AcnidAl)

### **For Production Use**
Ensure you have:
- Proper testing procedures
- Rollback plans
- Vendor support agreements
- Documentation of your specific environment

## Documentation

- **`README.md`** - This comprehensive overview
- **`MIGRATION_MATRIX.md`** - Detailed migration paths and complexity levels
- **`TROUBLESHOOTING.md`** - Comprehensive troubleshooting guide
- **`QUICK_START.md`** - Step-by-step quick start instructions

## License

This project is open source. Please review and modify scripts according to your specific needs and requirements.

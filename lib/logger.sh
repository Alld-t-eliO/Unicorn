#!/usr/bin/env bash

LOG_DIR="${LOG_DIR:-/tmp/datas_finder}"
LOG_FILE=""
REMOTE_LOG_PATH=""
DEBUG_MODE="${DEBUG_MODE:-0}"  


init_logger() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    LOG_DIR="${LOG_DIR:-/tmp/datas_finder}"
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        echo "FATAL: Cannot create $LOG_DIR" >&2
        return 1
    }
    
    LOG_FILE="$LOG_DIR/main_$timestamp.log"
    
    REMOTE_LOG_PATH="${VPS_PATH:-/root/pentest_datas}/live.log"
    
    if [[ -n "${VPS_IP:-}" ]] && [[ -n "${VPS_USER:-}" ]] && [[ -n "${VPS_PORT:-}" ]]; then
        ssh -o ConnectTimeout=2 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -p "$VPS_PORT" "$VPS_USER@$VPS_IP" \
            "touch '$REMOTE_LOG_PATH'" 2>/dev/null || true
    fi
    
    return 0
}


LOG_LEVELS=("DEBUG" "INFO" "WARN" "ERROR" "OK" "DONE")


log_local() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    local valid=0
    for l in "${LOG_LEVELS[@]}"; do
        [[ "$l" == "$level" ]] && valid=1 && break
    done
    [[ $valid -eq 0 ]] && level="INFO"
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE" 2>/dev/null || true
    
    if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
        echo "[$timestamp] [$level] $message" >&2
    fi
}


log_remote() {
    local level="$1"
    local message="$2"
    
    log_local "$level" "$message"
    
    if [[ -n "${VPS_IP:-}" ]] && [[ -n "${VPS_USER:-}" ]] && [[ -n "${VPS_PORT:-}" ]] && [[ -n "${VPS_PATH:-}" ]]; then
        local temp_file="/tmp/log_$$_$(date +%s%N).tmp"
        
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $message" > "$temp_file"
        
        scp -o ConnectTimeout=2 \
            -o BatchMode=yes \
            -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -P "$VPS_PORT" \
            "$temp_file" "$VPS_USER@$VPS_IP:$REMOTE_LOG_PATH" 2>/dev/null || true
        
        rm -f "$temp_file"
    fi
}


log_info() { log_remote "INFO" "$1"; }
log_warn() { log_remote "WARN" "$1"; }
log_error() { log_remote "ERROR" "$1"; }
log_ok() { log_remote "OK" "$1"; }
log_done() { log_remote "DONE" "$1"; }
log_debug() { log_remote "DEBUG" "$1"; }
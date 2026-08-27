#!/usr/bin/env bash

SSH_OPTS=()

init_ssh() {
    SSH_OPTS=(
        -o ConnectTimeout="${SSH_TIMEOUT:-10}"
        -o BatchMode=yes
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
    )
    
    return 0
}


ssh_exec() {
    local cmd="$1"
    ssh "${SSH_OPTS[@]}" -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "$cmd" 2>/dev/null
}


ssh_exec_safe() {
    local cmd="$1"
    local output=""
    output=$(ssh_exec "$cmd")
    echo "$output"
}


scp_send() {
    local local_path="$1"
    local remote_path="${2:-$VPS_PATH}"
    local result=1
    
    scp "${SSH_OPTS[@]}" -P "$VPS_PORT" "$local_path" "$VPS_USER@$VPS_IP:$remote_path/" 2>/dev/null && result=0
    
    return $result
}


scp_send_file() {
    local local_file="$1"
    local remote_file="$2"
    local result=1
    
    scp "${SSH_OPTS[@]}" -P "$VPS_PORT" "$local_file" "$VPS_USER@$VPS_IP:$remote_file" 2>/dev/null && result=0
    
    return $result
}


test_connection() {
    local max_retries="${SSH_MAX_RETRIES:-5}"
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        if ssh_exec "exit" >/dev/null 2>&1; then
            return 0
        fi
        retry=$((retry + 1))
        sleep 2
    done
    
    return 1
}


ensure_remote_dir() {
    local remote_path="$1"
    local result=0
    
    ssh_exec "mkdir -p '$remote_path'" >/dev/null 2>&1 || result=1
    
    return $result
}
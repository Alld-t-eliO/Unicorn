#!/usr/bin/env bash

validate_key() {
    local key="$1"
    if [[ ! "$key" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
        return 1
    fi
    return 0
}


parse_env() {
    local env_file="${1:-.env}"
    
    if [[ ! -f "$env_file" ]]; then
        return 1
    fi
    
    local line_num=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))
        
        [[ -z "$line" ]] && continue
        
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [[ -z "$line" ]] && continue
        
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            key="$(echo "$key" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            
            if ! validate_key "$key"; then
                echo "WARNING: Invalid key name at line $line_num: '$key'" >&2
                continue
            fi
            
            value="${value#\"}"
            value="${value%\"}"
            value="${value#\'}"
            value="${value%\'}"
            

            declare -gx "$key=$value"
        fi
    done < "$env_file"
    
    return 0
}


load_config() {
    local env_file="${1:-.env}"
    
    if [[ ! -f "$env_file" ]]; then
        return 1
    fi
    
    if ! parse_env "$env_file"; then
        return 1
    fi
    
    if [[ -z "${VPS_IP:-}" ]] || [[ -z "${VPS_USER:-}" ]] || [[ -z "${VPS_PORT:-}" ]]; then
        echo "ERROR: Missing required VPS variables" >&2
        return 1
    fi
    
    VPS_PATH="${VPS_PATH:-/root/pentest_datas}"
    SSH_TIMEOUT="${SSH_TIMEOUT:-10}"
    SSH_MAX_RETRIES="${SSH_MAX_RETRIES:-5}"
    REAL_DELETE="${REAL_DELETE:-0}"
    
    return 0
}
#!/bin/bash
# auto_flow.sh - Gestion des connexions SSH

set -euo pipefail

# ============================================
# Configuration SSH
# ============================================
SSH_TIMEOUT=10
SSH_MAX_RETRIES=3
SSH_OPTS="-o ConnectTimeout=$SSH_TIMEOUT -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# ============================================
# Fonctions de logging (si non définies ailleurs)
# ============================================
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

section() {
    echo ""
    echo "========================================"
    echo "  $*"
    echo "========================================"
    echo ""
}

# ============================================
# Vérification des paramètres
# ============================================
validate_params() {
    local has_error=0
    
    # Vérifier IP
    if [[ -z "${IP:-}" ]]; then
        log "[ERR] IP not set"
        has_error=1
    elif ! [[ $IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log "[ERR] Invalid IP format: $IP"
        has_error=1
    fi
    
    # Vérifier NAME
    if [[ -z "${NAME:-}" ]]; then
        log "[ERR] NAME not set"
        has_error=1
    fi
    
    # Vérifier PORT
    if [[ -z "${PORT:-}" ]]; then
        log "[ERR] PORT not set"
        has_error=1
    elif ! [[ $PORT =~ ^[0-9]+$ ]] || [[ $PORT -lt 1 ]] || [[ $PORT -gt 65535 ]]; then
        log "[ERR] Invalid PORT: $PORT"
        has_error=1
    fi
    
    if [[ $has_error -eq 1 ]]; then
        echo ""
        echo "Usage: export IP=192.168.1.100 NAME=root PORT=22"
        return 1
    fi
    
    return 0
}

# ============================================
# Fonction principale d'auto-login
# ============================================
auto_login() {
    section "AUTO LOGIN"
    
    # Valider les paramètres
    validate_params || return 1
    
    log "[INFO] Attempting connection to $NAME@$IP:$PORT"
    
    # Test de connexion avec retry
    local retry=0
    local connected=0
    
    while [[ $retry -lt $SSH_MAX_RETRIES ]]; do
        log "[INFO] Attempt $((retry+1))/$SSH_MAX_RETRIES"
        
        if ssh $SSH_OPTS -p "$PORT" "$NAME@$IP" "exit" 2>/dev/null; then
            connected=1
            break
        fi
        
        retry=$((retry+1))
        sleep 1
    done
    
    if [[ $connected -eq 1 ]]; then
        log "[OK] Connection established successfully"
        
        # Option: exécuter des commandes préliminaires
        # ssh $SSH_OPTS -p "$PORT" "$NAME@$IP" "uname -a"
        
        # Session interactive (si demandé)
        if [[ "${INTERACTIVE:-0}" == "1" ]]; then
            log "[INFO] Opening interactive session..."
            ssh $SSH_OPTS -p "$PORT" "$NAME@$IP"
        fi
        
        return 0
    else
        log "[ERR] Connection failed after $SSH_MAX_RETRIES attempts"
        return 1
    fi
}

# ============================================
# Fonction pour exécuter des commandes à distance
# ============================================
remote_exec() {
    local cmd="$1"
    ssh $SSH_OPTS -p "$PORT" "$NAME@$IP" "$cmd" 2>/dev/null
}

# ============================================
# Fonction pour copier des fichiers vers le VPS
# ============================================
copy_to_vps() {
    local local_path="$1"
    local remote_path="${2:-/tmp/}"
    
    if [[ ! -f "$local_path" ]] && [[ ! -d "$local_path" ]]; then
        log "[ERR] Local path not found: $local_path"
        return 1
    fi
    
    log "[INFO] Copying $local_path to $NAME@$IP:$remote_path"
    
    scp $SSH_OPTS -P "$PORT" -r "$local_path" "$NAME@$IP:$remote_path" 2>/dev/null || {
        log "[ERR] Copy failed"
        return 1
    }
    
    log "[OK] Copy completed"
    return 0
}

# ============================================
# Fonction pour récupérer des fichiers du VPS
# ============================================
copy_from_vps() {
    local remote_path="$1"
    local local_path="${2:-./}"
    
    log "[INFO] Copying $NAME@$IP:$remote_path to $local_path"
    
    scp $SSH_OPTS -P "$PORT" -r "$NAME@$IP:$remote_path" "$local_path" 2>/dev/null || {
        log "[ERR] Copy failed"
        return 1
    }
    
    log "[OK] Copy completed"
    return 0
}

# ============================================
# Point d'entrée si exécuté directement
# ============================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main() {
        echo "=== AUTO FLOW SCRIPT ==="
        echo ""
        echo "Available functions:"
        echo "  auto_login          - Connect to remote host"
        echo "  remote_exec 'cmd'   - Execute command remotely"
        echo "  copy_to_vps src dst - Copy files to VPS"
        echo "  copy_from_vps src dst - Copy files from VPS"
        echo ""
        
        case "${1:-}" in
            auto_login|remote_exec|copy_to_vps|copy_from_vps)
                "$@"
                ;;
            *)
                echo "Usage: $0 [function] [args]"
                echo "Example: source $0 && auto_login"
                ;;
        esac
    }
    main "$@"
fi
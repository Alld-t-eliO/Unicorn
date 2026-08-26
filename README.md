# 🔍 Pentest Auto Data Finder

> **DESTRUCTIVE TOOL - AUTHORIZED USE ONLY**

---

## Overview

Automated penetration testing tool that performs **complete system compromise and destruction**:

1. **Connect** to attacker VPS
2. **Scan** for sensitive data (credentials, keys, configs)
3. **Exfiltrate** discovered data to VPS
4. **Destroy** entire system (irreversible)

> **This tool will completely erase the machine it runs on.**

---

##  CRITICAL WARNINGS
┌─────────────────────────────────────────────────────────────┐
│ │
│   SYSTEM DESTRUCTION - IRREVERSIBLE │
│ │
│ This tool will: │
│ • Delete ALL system files (/bin, /etc, /usr, /var, /home) │
│ • Destroy ALL user accounts │
│ • Wipe disk partitions │
│ • Remove boot files │
│ • Delete itself │
│ │
│ USE ONLY ON: │
│  Isolated Virtual Machines │
│  Systems with available snapshots │
│  Authorized testing environments │
│ │
│ NEVER USE ON: │
│  Production systems │
│  Personal computers │
│  Systems without authorization │
│ │
└─────────────────────────────────────────────────────────────┘

---

##  Quick Start

### 1. Configure VPS

```bash
export VPS_IP="your.vps.ip"
export VPS_USER="root"
export VPS_PORT="22"

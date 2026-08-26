#!/usr/bin/env python3

import os
from pathlib import Path

MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024
MAX_TOTAL_SIZE = 5 * 1024 * 1024  *1024
MAX_DEPTH = 10  
MAX_SCAN_FILES = 10000  

SENSITIVE_PATTERNS = {
    "Credentials": [
        "*.key", "*.pem", "*.crt", "*.p12", "*.pfx",
        "*.secret", "*.token", "*.api", "*.env",
        "id_rsa", "id_dsa", "id_ecdsa", "id_ed25519",
        ".ssh/*", "authorized_keys",
        ".aws/credentials", ".aws/config",
        ".azure/*", ".gcp/*",
        "*.kubeconfig", "*.kube/config",
        ".docker/config.json",
        ".npmrc", ".pypirc", ".netrc",
        "secrets.yml", "secrets.yaml",
        "*.keystore", "*.jks",
        "password*", "passwd*", "secret*",
    ],
    
    "Configuration": [
        "*.conf", "*.cfg", "*.config",
        "*.ini", "*.toml", "*.yaml", "*.yml",
        "*.xml", "*.json",
        "*.properties",
        "settings.py", "settings.js",
        "application.properties",
        "web.config", "app.config",
        "config.inc.php", "wp-config.php",
        "environment.yml", "environment.yaml",
    ],
    
    "Database": [
        "*.sql", "*.sqlite", "*.db",
        "*.dump", "*.backup",
        "*.mdb", "*.accdb",
        "*.myi", "*.myd", "*.frm",
        "dump.sql", "backup.sql",
        "mysql/*", "postgresql/*",
    ],
    
    "Logs": [
        "*.log", "*.logs",
        "*.out", "*.err",
        "audit.log", "access.log", "error.log",
        "*.history", "*.bash_history",
        "*.zsh_history", ".bash_history",
        "*.pcap", "*.pcapng",
    ],
    
    "Certificates": [
        "*.cer", "*.der", "*.csr",
        "*.jks", "*.keystore",
        "*.truststore",
        "*.gpg", "*.asc",
        "*.pgp", "*.sig",
    ],
    
    "SourceCode": [
        "*.py", "*.js", "*.ts", "*.go", "*.rs",
        "*.java", "*.class", "*.jar",
        "*.c", "*.cpp", "*.h", "*.hpp",
        "*.php", "*.rb", "*.pl",
        "*.sh", "*.bash", "*.zsh",
        "*.ps1", "*.bat", "*.cmd",
        "Dockerfile", "docker-compose.yml",
    ],
    
    "Documents": [
        "*.doc", "*.docx",
        "*.xls", "*.xlsx",
        "*.ppt", "*.pptx",
        "*.pdf",
        "*.odt", "*.ods", "*.odp",
        "*.rtf", "*.txt",
        "*.md", "*.markdown",
    ],
    
    "Web": [
        "*.html", "*.htm", "*.xhtml",
        "*.css", "*.scss", "*.sass",
        "*.vue", "*.jsx", "*.tsx",
        "*.jsp", "*.asp", "*.aspx",
        "*.do", "*.action",
        "*.jspf", "*.tag", "*.tld",
    ],
    
    # 🔧 Scripts & 
    "Scripts": [
        "*.pyc", "*.pyo",
        "*.so", "*.dylib", "*.dll",
        "*.bin", "*.exe",
        "*.o", "*.a", "*.lib",
        "*.sh", "*.bash",
        "*.pl", "*.pm",
        "*.rb", "*.erb",
    ],
    
    "Archives": [
        "*.zip", "*.tar", "*.gz", "*.bz2",
        "*.7z", "*.rar", "*.xz",
        "*.tgz", "*.tbz2",
        "*.war", "*.ear", "*.jar",
        "*.apk", "*.ipa",
        "*.iso", "*.img",
    ],
}

IGNORE_DIRS = [
    "/proc", "/sys", "/dev", "/run",
    "/tmp", "/var/tmp",
    "/.cache", "/.caches",
    "/snap", "/flatpak",
    "/node_modules", "/.git",
    "/venv", "/.venv", "/env", "/.env",
    "__pycache__",
    ".idea", ".vscode",
]

IGNORE_EXTENSIONS = [
    ".pyc", ".pyo", ".pyd",
    ".so", ".dylib", ".dll",
    ".o", ".a", ".lib",
    ".exe", ".dmg", ".msi",
    ".mp3", ".mp4", ".avi", ".mkv",
    ".jpg", ".jpeg", ".png", ".gif", ".bmp",
    ".ttf", ".otf", ".woff", ".woff2",
    ".iso", ".img", ".vmdk", ".vdi",
]

PRIORITY_SCAN_PATHS = [
    "/home", "/root", "/etc", "/var",
    "/opt", "/usr/local",
    "/mnt", "/media",
]

SCAN_PATHS = [
    "/",
]

SENSITIVE_CONTENT_PATTERNS = [
    r"password\s*[:=]\s*\S+",
    r"passwd\s*[:=]\s*\S+",
    r"secret\s*[:=]\s*\S+",
    r"token\s*[:=]\s*\S+",
    r"api[_-]?key\s*[:=]\s*\S+",
    r"auth[_-]?token\s*[:=]\s*\S+",
    r"private[_-]?key\s*[:=]\s*\S+",
    r"secret[_-]?key\s*[:=]\s*\S+",
    r"mongodb://[^/\s]+",
    r"mysql://[^/\s]+",
    r"postgresql://[^/\s]+",
    r"redis://[^/\s]+",
    r"aws[_-]?access[_-]?key[_-]?id\s*[:=]\s*\S+",
    r"aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*\S+",
    r"Bearer\s+[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+",  
    r"[A-Za-z0-9]{20,}", 
]
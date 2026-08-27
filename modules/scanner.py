#!/usr/bin/env python3
# modules/scanner.py - Data scanner (corrected)

import os
import sys
import re
import json
import hashlib
import shutil
import fnmatch
import logging
import argparse
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Tuple, Set

# ============================================
# CONFIGURATION
# ============================================

MAX_FILE_SIZE = 2 * 1024 * 1024 * 1024
MAX_TOTAL_BYTES = 5 * 1024 * 1024 * 1024
MAX_DEPTH = 10
MAX_SCAN_FILES = 10000

SCAN_PATHS = ["/"]

# Patterns (more precise)
PATTERNS = {
    "credentials": [
        # File extensions
        "*.key", "*.pem", "*.crt", "*.p12", "*.pfx",
        "*.secret", "*.token", "*.env",
        # SSH keys (must be in .ssh directory)
        "**/.ssh/id_rsa", "**/.ssh/id_dsa", "**/.ssh/id_ecdsa", "**/.ssh/id_ed25519",
        "**/.ssh/authorized_keys",
        # Cloud credentials
        "**/.aws/credentials", "**/.aws/config",
        "**/.azure/**", "**/.gcp/**",
        "**/.kube/config", "**/*.kubeconfig",
        "**/.docker/config.json",
        # Config files
        "**/secrets.yml", "**/secrets.yaml",
        "**/password*", "**/secret*",
        # Dotfiles
        ".netrc", ".npmrc", ".pypirc",
    ],
    "config": [
        "*.conf", "*.cfg", "*.config",
        "*.ini", "*.toml", "*.yaml", "*.yml",
        "*.xml", "*.json", "*.properties",
        "**/settings.py", "**/settings.js",
        "**/application.properties",
        "**/web.config", "**/app.config",
        "**/config.inc.php", "**/wp-config.php",
    ],
    "database": [
        "*.sql", "*.sqlite", "*.db",
        "*.dump", "*.backup",
        "**/dump.sql", "**/backup.sql",
        "**/mysql/**/*.frm", "**/mysql/**/*.ibd",
        "**/postgresql/**",
    ],
    "logs": [
        "*.log", "*.logs",
        "**/audit.log", "**/access.log", "**/error.log",
        "*.bash_history", "*.history", ".bash_history",
        "*.pcap", "*.pcapng",
    ],
    "certificates": [
        "*.cer", "*.der", "*.csr",
        "*.jks", "*.keystore", "*.truststore",
        "*.gpg", "*.asc", "*.pgp",
    ],
    "source": [
        "*.py", "*.js", "*.ts", "*.go", "*.rs",
        "*.java", "*.class", "*.jar",
        "*.c", "*.cpp", "*.h", "*.hpp",
        "*.php", "*.rb", "*.pl",
        "*.sh", "*.bash", "*.zsh",
        "**/Dockerfile", "**/docker-compose.yml",
    ],
}

# Directories to ignore
IGNORE_DIRS = {
    # Absolute paths
    "/proc", "/sys", "/dev", "/run",
    "/tmp", "/var/tmp",
    # Directory names (anywhere)
    ".git", "node_modules", "__pycache__",
    "venv", ".venv", "env", ".env",
    ".idea", ".vscode",
    # Cache directories
    ".cache", ".caches",
    "snap", "flatpak",
}

# Extensions to ignore
IGNORE_EXTENSIONS = {
    ".pyc", ".pyo", ".pyd",
    ".so", ".dylib", ".dll",
    ".o", ".a", ".lib",
    ".exe", ".dmg", ".msi",
    ".mp3", ".mp4", ".avi", ".mkv",
    ".jpg", ".jpeg", ".png", ".gif", ".bmp",
    ".ttf", ".otf", ".woff", ".woff2",
    ".iso", ".img", ".vmdk", ".vdi",
}

# Regex patterns for content
CONTENT_PATTERNS = [
    re.compile(r"password\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"secret\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"token\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"api[_-]?key\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"aws[_-]?access[_-]?key[_-]?id\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*\S+", re.IGNORECASE),
    re.compile(r"mongodb://[^/\s]+", re.IGNORECASE),
    re.compile(r"mysql://[^/\s]+", re.IGNORECASE),
    re.compile(r"postgresql://[^/\s]+", re.IGNORECASE),
    re.compile(r"redis://[^/\s]+", re.IGNORECASE),
    re.compile(r"Bearer\s+[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+\.[A-Za-z0-9\-_=]+"),
]

# ============================================
# SCANNER CLASS
# ============================================

class FileScanner:
    def __init__(self):
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.output_dir = Path(f"/tmp/datas_finder/{self.timestamp}")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.output_dir, 0o700)
        
        # Stats (clear naming)
        self.stats = {
            "visited_entries": 0,    # All items (files + dirs)
            "visited_files": 0,      # Files encountered
            "visited_bytes": 0,      # Total bytes of all files
            "analyzed_files": 0,     # Files after size/extension filtering
            "analyzed_bytes": 0,     # Bytes of analyzed files
            "retained_files": 0,     # Files that matched patterns
            "retained_bytes": 0,     # Bytes of retained files
            "copied_files": 0,       # Files successfully copied
            "copied_bytes": 0,       # Bytes successfully copied
        }
        
        self.results = []
    
    def should_ignore(self, path: Path) -> bool:
        """Check if path should be ignored"""
        path_str = str(path.resolve())
        path_parts = path.parts
        path_name = path.name
        
        for ignore in IGNORE_DIRS:
            # 1. Absolute path exact match
            if ignore.startswith('/'):
                if path_str == ignore or path_str.startswith(f"{ignore}/"):
                    return True
                continue
            
            # 2. Directory name (anywhere in path)
            if ignore in path_parts or path_name == ignore:
                return True
            
            # 3. Glob pattern
            if '**' in ignore and fnmatch.fnmatch(path_str, ignore):
                return True
        
        # 4. Special: .cache anywhere in path
        if ".cache" in path_parts:
            return True
        
        return False
    
    def match_pattern(self, filepath: str, pattern: str) -> bool:
        """Check if filepath matches a pattern"""
        path = Path(filepath).resolve()
        path_str = str(path)
        path_name = path.name
        
        # 1. Simple filename pattern (e.g., *.key)
        if pattern.startswith('*.'):
            return fnmatch.fnmatch(path_name, pattern)
        
        # 2. Path pattern with **/ (e.g., **/.ssh/id_rsa)
        if '**/' in pattern:
            # Extract the part after **/
            search_pattern = pattern.split('**/', 1)[-1]
            
            # If search pattern is a filename (e.g., id_rsa)
            if '/' not in search_pattern:
                # Check if filename matches and parent directory contains the context
                if not fnmatch.fnmatch(path_name, search_pattern):
                    return False
                # Verify it's in the right context (e.g., .ssh directory)
                context = pattern.split('**/', 1)[0]
                if context:
                    # Check if the path ends with the expected structure
                    return path_str.endswith(f"/{context}{search_pattern}") or f"/{context}{search_pattern}" in path_str
                return True
            
            # For path patterns (e.g., .ssh/id_rsa)
            return search_pattern in path_str
        
        # 3. Simple pattern in path (e.g., .aws/credentials)
        if '/' in pattern:
            # If pattern ends with /, it's a directory
            if pattern.endswith('/'):
                return pattern in path_str
            return pattern in path_str
        
        # 4. Simple filename or directory name
        return path_name == pattern or pattern in path_str
    
    def is_interesting(self, filepath: str) -> Tuple[bool, List[str], List[str]]:
        """Check if file is interesting"""
        reasons = []
        content_matches = []
        path_str = str(Path(filepath).resolve())
        
        # 1. Check patterns by category
        for category, patterns in PATTERNS.items():
            for pattern in patterns:
                if self.match_pattern(path_str, pattern):
                    reasons.append(category)
                    break
        
        # 2. Check content (always, for all files)
        if self.is_text_file(path_str):
            content_matches = self.scan_content(path_str)
            if content_matches:
                reasons.append("content")
        
        return bool(reasons), reasons, content_matches
    
    def is_text_file(self, filepath: str) -> bool:
        """Check if file is text"""
        try:
            with open(filepath, 'rb') as f:
                chunk = f.read(1024)
            if not chunk:
                return True
            if b'\x00' in chunk:
                return False
            printable = sum(1 for b in chunk if 32 <= b <= 126 or b in (9, 10, 13))
            return printable / len(chunk) > 0.70
        except Exception:
            return False
    
    def scan_content(self, filepath: str) -> List[str]:
        """Scan file content for sensitive patterns"""
        matches = []
        try:
            with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read(4096)
            for pattern in CONTENT_PATTERNS:
                if pattern.search(content):
                    matches.append(pattern.pattern)
        except Exception:
            pass
        return matches
    
    def compute_hash(self, filepath: str) -> Optional[str]:
        """Compute SHA256 hash"""
        try:
            sha256 = hashlib.sha256()
            with open(filepath, 'rb') as f:
                while chunk := f.read(1024 * 1024):
                    sha256.update(chunk)
            return sha256.hexdigest()
        except Exception:
            return None
    
    def copy_file(self, filepath: str, file_hash: str, reasons: List[str]) -> Optional[str]:
        """Copy file with proper organization"""
        try:
            source = Path(filepath).resolve()
            
            # Category-based directory
            category = reasons[0] if reasons else "other"
            dest_dir = self.output_dir / category
            dest_dir.mkdir(parents=True, exist_ok=True)
            
            # Use hash prefix for filename
            hash_prefix = file_hash[:8] if file_hash else "unknown"
            dest_name = f"{hash_prefix}_{source.name}"
            dest = dest_dir / dest_name
            
            # Handle collisions with counter
            counter = 1
            while dest.exists():
                dest = dest_dir / f"{hash_prefix}_{counter}_{source.name}"
                counter += 1
                if counter > 100:
                    dest = dest_dir / f"{hash_prefix}_{source.stem}_{datetime.now().strftime('%H%M%S')}{source.suffix}"
                    break
            
            shutil.copy2(source, dest)
            os.chmod(dest, 0o600)
            return str(dest)
            
        except Exception as e:
            return None
    
    def process_file(self, filepath: str):
        """Process a single file"""
        try:
            path = Path(filepath).resolve()
            
            # Update visited stats
            self.stats["visited_entries"] += 1
            self.stats["visited_files"] += 1
            size = path.stat().st_size
            self.stats["visited_bytes"] += size
            
            # Check limits (file size)
            if size > MAX_FILE_SIZE:
                return
            
            # Check limits (total bytes - check BEFORE adding)
            if self.stats["analyzed_bytes"] + size > MAX_TOTAL_BYTES:
                return
            
            # Check limits (max files)
            if self.stats["analyzed_files"] >= MAX_SCAN_FILES:
                return
            
            # Check extension
            if path.suffix.lower() in IGNORE_EXTENSIONS:
                return
            
            # Check if interesting
            is_interesting, reasons, content_matches = self.is_interesting(str(path))
            if not is_interesting:
                return
            
            # Update analyzed stats (after all filters)
            self.stats["analyzed_files"] += 1
            self.stats["analyzed_bytes"] += size
            
            # Update retained stats (matched files)
            self.stats["retained_files"] += 1
            self.stats["retained_bytes"] += size
            
            # Compute hash (once)
            file_hash = self.compute_hash(str(path))
            
            # Copy file
            copy_path = self.copy_file(str(path), file_hash, reasons)
            if copy_path:
                self.stats["copied_files"] += 1
                self.stats["copied_bytes"] += size
            
            # Store result
            self.results.append({
                "path": str(path),
                "size": size,
                "hash": file_hash,
                "reasons": reasons,
                "content_matches": content_matches,
                "copy_path": copy_path,
            })
            
        except Exception:
            pass
    
    def scan_directory(self, directory: str, depth: int = 0):
        """Scan directory recursively"""
        if depth > MAX_DEPTH:
            return
        
        try:
            dir_path = Path(directory).expanduser().resolve()
            if not dir_path.exists():
                return
            
            for item in dir_path.iterdir():
                if self.should_ignore(item):
                    continue
                
                if item.is_symlink():
                    continue
                
                if item.is_dir():
                    self.scan_directory(str(item), depth + 1)
                elif item.is_file():
                    self.process_file(str(item))
                    
        except (PermissionError, OSError):
            pass
        except Exception:
            pass
    
    def scan(self):
        """Run full scan"""
        for path in SCAN_PATHS:
            if os.path.exists(path):
                self.scan_directory(path)
        
        self.generate_report()
        return self.results
    
    def generate_report(self):
        """Generate JSON report"""
        report = {
            "timestamp": self.timestamp,
            "hostname": os.uname().nodename,
            "stats": self.stats,
            "files": self.results,
        }
        
        report_file = self.output_dir / "results.json"
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2, default=str)
        
        return str(report_file)

# ============================================
# MAIN
# ============================================

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output-file', help='Write output directory path')
    args = parser.parse_args()
    
    scanner = FileScanner()
    scanner.scan()
    
    if args.output_file:
        with open(args.output_file, 'w') as f:
            f.write(str(scanner.output_dir))

if __name__ == "__main__":
    main()
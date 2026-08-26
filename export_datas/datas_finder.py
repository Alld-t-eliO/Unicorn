#!/usr/bin/env python3

import hashlib
import os
import re
import json
import shutil
import threading
import logging
from pathlib import Path
from typing import List, Tuple, Optional, Dict, Set
from datetime import datetime
from dataclasses import dataclass, asdict
from collections import defaultdict

from config import (
    SENSITIVE_PATTERNS,
    SENSITIVE_CONTENT_PATTERNS,
    IGNORE_DIRS,
    IGNORE_EXTENSIONS,
    MAX_FILE_SIZE,
    MAX_TOTAL_SIZE,
    MAX_DEPTH,
    SCAN_PATHS,
    PRIORITY_SCAN_PATHS,
)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@dataclass
class FoundFile:
    path: str
    size: int
    sha256: str
    reasons: List[str]
    backup_path: Optional[str] = None
    content_matches: List[str] = None
    permissions: str = ""
    owner: str = ""
    modified_time: str = ""
    
    def to_dict(self):
        return asdict(self)

class FileScanner:
    def __init__(self, output_dir: str = "/tmp/datas_finder"):
        self.found_files: List[FoundFile] = []
        self.total_size = 0
        self.scanned_count = 0
        self.files_by_reason = defaultdict(int)
        self.lock = threading.Lock()
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.backup_dir = Path(output_dir) / timestamp
        self.backup_dir = self.backup_dir.expanduser().resolve()
        self._create_backup_directory()
        
        self.content_patterns = [
            re.compile(pattern, re.IGNORECASE) 
            for pattern in SENSITIVE_CONTENT_PATTERNS
        ]
        
        self.sensitive_patterns = SENSITIVE_PATTERNS
        self.ignore_dirs = set(IGNORE_DIRS)
        self.ignore_extensions = set(IGNORE_EXTENSIONS)
        
        self.results_file = self.backup_dir / "results.json"
        self.summary_file = self.backup_dir / "summary.txt"
    
    def _create_backup_directory(self):
        try:
            self.backup_dir.mkdir(parents=True, exist_ok=True)
            os.chmod(self.backup_dir, 0o700)
            logger.info(f"📁 Backup directory: {self.backup_dir}")
        except OSError as e:
            logger.error(f"Failed to create backup dir: {e}")
            raise
    
    def backup_file(self, filepath: str) -> Optional[str]:
        try:
            source = Path(filepath).expanduser().resolve()
            
            relative_path = Path(*source.parts[1:]) if len(source.parts) > 1 else source.name
            destination = self.backup_dir / relative_path
            
            destination.parent.mkdir(parents=True, exist_ok=True)
            os.chmod(destination.parent, 0o700)
            
            shutil.copy2(source, destination, follow_symlinks=False)
            os.chmod(destination, 0o600)
            
            logger.debug(f"✅ Datas: {filepath} -> {destination}")
            return str(destination)
            
        except Exception as e:
            logger.debug(f"⚠️ Datas failed for {filepath}: {e}")
            return None
    
    def get_file_info(self, filepath: str) -> Dict:
        try:
            stat = os.stat(filepath)
            return {
                'permissions': oct(stat.st_mode)[-3:],
                'owner': f"{stat.st_uid}:{stat.st_gid}",
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                'accessed': datetime.fromtimestamp(stat.st_atime).isoformat(),
                'created': datetime.fromtimestamp(stat.st_ctime).isoformat(),
            }
        except Exception:
            return {}
    
    def compute_hash(self, filepath: str) -> Optional[str]:
        sha256 = hashlib.sha256()
        try:
            with open(filepath, "rb") as f:
                while chunk := f.read(1024 * 1024):
                    sha256.update(chunk)
            return sha256.hexdigest()
        except Exception:
            return None
    
    def is_text_file(self, filepath: str) -> bool:
        try:
            with open(filepath, "rb") as f:
                chunk = f.read(1024)
            if not chunk:
                return True
            if b'\x00' in chunk:
                return False
            printable = sum(1 for b in chunk if 32 <= b <= 126 or b in (9, 10, 13))
            ratio = printable / len(chunk)
            return ratio > 0.70
        except Exception:
            return False
    
    def search_content(self, filepath: str) -> List[str]:
        matches = []
        try:
            with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read(4096)  

            for pattern in self.content_patterns:
                if pattern.search(content):
                    matches.append(pattern.pattern)
            
        except Exception:
            pass
        
        return matches
    
    def match_glob(self, filepath: str, pattern: str) -> bool:
        filepath_lower = filepath.lower()
        pattern_lower = pattern.lower()
        
        if pattern_lower.startswith("*."):
            return filepath_lower.endswith(pattern_lower[1:])
        elif pattern_lower.startswith("**/"):
            return pattern_lower[3:] in filepath_lower
        else:
            return pattern_lower in filepath_lower
    
    def is_interesting(self, filepath: str) -> Tuple[bool, List[str], List[str]]:
        reasons = []
        content_matches = []
        filepath_str = str(filepath)
        
        for category, patterns in self.sensitive_patterns.items():
            for pattern in patterns:
                if self.match_glob(filepath_str, pattern):
                    reasons.append(category)
                    break
        
        if reasons and self.is_text_file(filepath_str):
            content_matches = self.search_content(filepath_str)
            if content_matches:
                reasons.append("contains:sensitive_content")
        
        return bool(reasons), list(dict.fromkeys(reasons)), content_matches
    
    def process_file(self, filepath: str):
        try:
            if not os.path.exists(filepath):
                return
            
            size = os.path.getsize(filepath)
            if size > MAX_FILE_SIZE:
                return
            
            extension = os.path.splitext(filepath)[1].lower()
            if extension in self.ignore_extensions:
                return
            
            is_interesting, reasons, content_matches = self.is_interesting(filepath)
            
            if not is_interesting:
                return
            
            file_hash = self.compute_hash(filepath)
            file_info = self.get_file_info(filepath)
            backup_path = self.backup_file(filepath)
            
            found = FoundFile(
                path=filepath,
                size=size,
                sha256=file_hash or "",
                reasons=reasons,
                backup_path=backup_path,
                content_matches=content_matches,
                permissions=file_info.get('permissions', ''),
                owner=file_info.get('owner', ''),
                modified_time=file_info.get('modified', ''),
            )
            
            with self.lock:
                self.found_files.append(found)
                self.total_size += size
                self.scanned_count += 1
                for reason in reasons:
                    self.files_by_reason[reason] += 1
            
            self._print_found(found)
            
        except Exception as e:
            logger.debug(f"Error processing {filepath}: {e}")
    
    def _print_found(self, found: FoundFile):
        """Affiche les résultats"""
        print(f"\n🔍 {found.path}")
        print(f"   📦 Size: {found.size:,} bytes")
        print(f"   🏷️  Reasons: {', '.join(found.reasons)}")
        if found.content_matches:
            print(f"   📝 Content matches: {len(found.content_matches)}")
        if found.backup_path:
            print(f"   💾 Backup: {found.backup_path}")
    
    def scan_directory(self, directory: str, depth: int = 0):
        """Scanne un répertoire"""
        if depth > MAX_DEPTH:
            return
        
        try:
            dir_path = Path(directory).expanduser()
            
            if not dir_path.exists():
                return
            
            for item in dir_path.iterdir():
                try:
                    # Ignorer les liens symboliques vers des dossiers ignorés
                    if item.is_symlink():
                        try:
                            real_path = item.resolve()
                            if any(ignored in str(real_path) for ignored in self.ignore_dirs):
                                continue
                        except Exception:
                            continue
                    
                    # Vérifier les dossiers à ignorer
                    if any(ignored in str(item) for ignored in self.ignore_dirs):
                        continue
                    
                    if item.is_dir():
                        self.scan_directory(str(item), depth + 1)
                    elif item.is_file():
                        self.process_file(str(item))
                    
                except (PermissionError, OSError):
                    continue
                except Exception as e:
                    logger.debug(f"Item error {item}: {e}")
                    
        except PermissionError:
            pass
        except Exception as e:
            logger.error(f"Scan error {directory}: {e}")
    
    def scan(self):
        """Lance le scan"""
        print("\n" + "="*60)
        print("🔍 DATA FINDER - Sensitive Files Scanner")
        print("="*60)
        
        # Scan des dossiers prioritaires d'abord
        for directory in PRIORITY_SCAN_PATHS:
            if os.path.exists(directory):
                print(f"\n📁 [PRIORITY] Scanning: {directory}")
                self.scan_directory(directory)
        
        # Scan des autres dossiers
        for directory in SCAN_PATHS:
            if directory not in PRIORITY_SCAN_PATHS and os.path.exists(directory):
                print(f"\n📁 Scanning: {directory}")
                self.scan_directory(directory)
        
        # Génération des rapports
        self._generate_reports()
        
        print("\n" + "="*60)
        print("✅ SCAN COMPLETE")
        print("="*60)
        print(f"📊 Files scanned: {self.scanned_count:,}")
        print(f"🔍 Interesting files: {len(self.found_files):,}")
        print(f"📦 Total size: {self.total_size:,} bytes")
        print(f"📁 Results: {self.backup_dir}")
        self._print_summary()
        
        return self.found_files
    
    def _generate_reports(self):
        """Génère les rapports"""
        # Rapport JSON
        results = {
            'timestamp': datetime.now().isoformat(),
            'total_files_scanned': self.scanned_count,
            'interesting_files': len(self.found_files),
            'total_size': self.total_size,
            'files_by_reason': dict(self.files_by_reason),
            'files': [f.to_dict() for f in self.found_files]
        }
        
        with open(self.results_file, 'w') as f:
            json.dump(results, f, indent=2, default=str)
        
        # Rapport texte
        with open(self.summary_file, 'w') as f:
            f.write("="*60 + "\n")
            f.write("DATA FINDER - RESULTS\n")
            f.write("="*60 + "\n\n")
            f.write(f"Timestamp: {datetime.now().isoformat()}\n")
            f.write(f"Files scanned: {self.scanned_count:,}\n")
            f.write(f"Interesting files: {len(self.found_files):,}\n")
            f.write(f"Total size: {self.total_size:,} bytes\n\n")
            
            f.write("FILES BY CATEGORY:\n")
            for reason, count in sorted(self.files_by_reason.items(), key=lambda x: x[1], reverse=True):
                f.write(f"  - {reason}: {count}\n")
            
            f.write("\nDETAILED LIST:\n")
            for i, found in enumerate(self.found_files, 1):
                f.write(f"\n{i}. {found.path}\n")
                f.write(f"   Size: {found.size:,} bytes\n")
                f.write(f"   SHA256: {found.sha256}\n")
                f.write(f"   Reasons: {', '.join(found.reasons)}\n")
                if found.content_matches:
                    f.write(f"   Content matches: {len(found.content_matches)}\n")
                if found.backup_path:
                    f.write(f"   Backup: {found.backup_path}\n")
    
    def _print_summary(self):
        print("\n📊 SUMMARY BY CATEGORY:")
        for reason, count in sorted(self.files_by_reason.items(), key=lambda x: x[1], reverse=True):
            print(f"   {reason}: {count} files")
        
        print(f"\n📁 Results saved to: {self.backup_dir}")
        print(f"   - results.json")
        print(f"   - summary.txt")

def main():
    scanner = FileScanner()
    scanner.scan()

if __name__ == "__main__":
    main()
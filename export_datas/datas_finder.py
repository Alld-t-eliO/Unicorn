#!/usr/bin/env python3

import os
import sys
import json
import hashlib
import shutil
import logging
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional, Tuple

from config import (
    SENSITIVE_PATTERNS,
    IGNORE_DIRS,
    IGNORE_EXTENSIONS,
    MAX_FILE_SIZE,
    SCAN_PATHS,
)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class DataFinder:
    def __init__(self):
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.output_dir = Path(f"/tmp/datas_finder/{self.timestamp}")
        self.found_files = []
        self.scanned_count = 0
        self.total_size = 0
        
        self._create_output_dir()
        self.sensitive_patterns = SENSITIVE_PATTERNS
        self.ignore_dirs = set(IGNORE_DIRS)
        self.ignore_extensions = set(IGNORE_EXTENSIONS)
    
    def _create_output_dir(self):
        self.output_dir.mkdir(parents=True, exist_ok=True)
        os.chmod(self.output_dir, 0o700)
        logger.info(f"- Output directory: {self.output_dir}")
    
    def _is_interesting(self, filepath: str) -> Tuple[bool, List[str]]:
        filepath_str = str(filepath)
        reasons = []
        
        for category, patterns in self.sensitive_patterns.items():
            for pattern in patterns:
                if self._match_glob(filepath_str, pattern):
                    reasons.append(category)
                    break
        
        return bool(reasons), list(dict.fromkeys(reasons))
    
    def _match_glob(self, filepath: str, pattern: str) -> bool:
        filepath_lower = filepath.lower()
        pattern_lower = pattern.lower()
        
        if pattern_lower.startswith("*."):
            return filepath_lower.endswith(pattern_lower[1:])
        elif pattern_lower.startswith("**/"):
            return pattern_lower[3:] in filepath_lower
        else:
            return pattern_lower in filepath_lower
    
    def _compute_hash(self, filepath: str) -> Optional[str]:
        try:
            sha256 = hashlib.sha256()
            with open(filepath, "rb") as f:
                while chunk := f.read(1024 * 1024):
                    sha256.update(chunk)
            return sha256.hexdigest()
        except Exception:
            return None
    
    def _get_file_info(self, filepath: str) -> Dict:
        try:
            stat = os.stat(filepath)
            return {
                'size': stat.st_size,
                'permissions': oct(stat.st_mode)[-3:],
                'owner': f"{stat.st_uid}:{stat.st_gid}",
                'modified': datetime.fromtimestamp(stat.st_mtime).isoformat(),
            }
        except Exception:
            return {}
    
    def _copy_file(self, filepath: str) -> Optional[str]:
        try:
            source = Path(filepath)
            dest = self.output_dir / source.name
            
            if dest.exists():
                dest = self.output_dir / f"{source.stem}_{self.timestamp}{source.suffix}"
            
            shutil.copy2(source, dest)
            os.chmod(dest, 0o600)
            return str(dest)
        except Exception as e:
            logger.debug(f"Copy failed for {filepath}: {e}")
            return None
    
    def _scan_directory(self, directory: str, depth: int = 0, max_depth: int = 10):
        if depth > max_depth:
            return
        
        try:
            dir_path = Path(directory).expanduser()
            
            if not dir_path.exists():
                return
            
            for item in dir_path.iterdir():
                try:
                    if any(ignored in str(item) for ignored in self.ignore_dirs):
                        continue
                    
                    if item.is_symlink():
                        continue
                    
                    if item.is_dir():
                        self._scan_directory(str(item), depth + 1, max_depth)
                    
                    elif item.is_file():
                        self._process_file(str(item))
                    
                except (PermissionError, OSError):
                    continue
                except Exception as e:
                    logger.debug(f"Item error {item}: {e}")
                    
        except (PermissionError, OSError):
            pass
        except Exception as e:
            logger.error(f"Scan error {directory}: {e}")
    
    def _process_file(self, filepath: str):
        try:
            size = os.path.getsize(filepath)
            if size > MAX_FILE_SIZE:
                return
            
            ext = os.path.splitext(filepath)[1].lower()
            if ext in self.ignore_extensions:
                return
            
            is_interesting, reasons = self._is_interesting(filepath)
            if not is_interesting:
                return
            
            file_hash = self._compute_hash(filepath)
            file_info = self._get_file_info(filepath)
            copy_path = self._copy_file(filepath)
            
            result = {
                'path': filepath,
                'reasons': reasons,
                'hash': file_hash,
                'info': file_info,
                'copy': copy_path,
            }
            
            self.found_files.append(result)
            self.scanned_count += 1
            self.total_size += size
            
            logger.info(f"- {filepath} - {', '.join(reasons)}")
            
        except Exception as e:
            logger.debug(f"[ERR] {filepath}: {e}")
    
    def scan(self):
        logger.info("+ Starting scan...")
        
        for path in SCAN_PATHS:
            if os.path.exists(path):
                logger.info(f"- Scanning: {path}")
                self._scan_directory(path)
        
        self._generate_report()
        self._print_summary()
        
        return self.found_files
    
    def _generate_report(self):
        report = {
            'timestamp': self.timestamp,
            'hostname': os.uname().nodename,
            'total_scanned': self.scanned_count,
            'total_found': len(self.found_files),
            'total_size': self.total_size,
            'files': self.found_files,
        }
        
        report_file = self.output_dir / 'results.json'
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2, default=str)
        
        logger.info(f"+ Report: {report_file}")
    
    def _print_summary(self):
        print("\n" + "="*60)
        print(" SCAN COMPLETE")
        print("="*60)
        print(f"Files scanned: {self.scanned_count:,}")
        print(f"Files found: {len(self.found_files):,}")
        print(f"Total size: {self.total_size:,} bytes")
        print(f"Output: {self.output_dir}")
        print("="*60)

def main():
    finder = DataFinder()
    finder.scan()

if __name__ == "__main__":
    main()
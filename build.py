#!/usr/bin/env python3
"""
FS25_NPCFavor — Cross-Platform Build & Deploy

Creates a properly structured FS25_NPCFavor.zip ready for Farming Simulator 25.
The zip contains mod files at the root (no wrapper folder), exactly as FS25 expects.

Usage:
    python build.py              Build zip in the repo root directory
    python build.py --deploy     Build zip and copy it to the FS25 mods folder
    python build.py -d           Short form of --deploy

Deploy auto-detects the FS25 mods folder by checking common locations:
    Windows:  %USERPROFILE%\\Documents\\My Games\\FarmingSimulator2025\\mods
              %USERPROFILE%\\OneDrive\\Documents\\My Games\\FarmingSimulator2025\\mods
    macOS:    ~/Library/Application Support/FarmingSimulator2025/mods
    Linux:    ~/.local/share/FarmingSimulator2025/mods

Override auto-detection with:
    set FS25_MODS_DIR=C:\\your\\custom\\path\\mods   (Windows)
    export FS25_MODS_DIR="/your/custom/path/mods"    (macOS/Linux)
"""

import argparse
import os
import platform
import shutil
import sys
import zipfile
from pathlib import Path

ZIP_NAME = "FS25_NPCFavor.zip"

# Exclusion lists — keep in sync with build.sh
EXCLUDE_DIRS = {".git", ".claude", ".vscode", ".idea", "node_modules", "tools"}
EXCLUDE_FILES = {
    "build.sh", "build.py",
    "find_unused_code.sh", "find_unused_code.py",
    "lang_sync.js", "lang_sync.py",
    "CLAUDE.md", "Thumbs.db", ".DS_Store", ".gitignore", "nul",
}
EXCLUDE_EXTS = {".zip", ".swp", ".swo"}


def build_zip(source_dir: Path, output_path: Path) -> int:
    """Walk source_dir, apply exclusions, write zip with forward-slash paths."""
    file_count = 0
    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(source_dir):
            # Prune excluded directories in-place so os.walk skips them
            dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]

            for filename in files:
                if filename in EXCLUDE_FILES:
                    continue
                if Path(filename).suffix in EXCLUDE_EXTS:
                    continue
                # Skip backup files ending with ~
                if filename.endswith("~"):
                    continue

                filepath = Path(root) / filename
                # Archive path: relative to source_dir, always forward slashes
                arcname = filepath.relative_to(source_dir).as_posix()
                zf.write(filepath, arcname)
                file_count += 1

    return file_count


def find_mods_folder() -> Path | None:
    """Auto-detect the FS25 mods folder, checking env var then standard locations."""
    env_dir = os.environ.get("FS25_MODS_DIR")
    if env_dir:
        p = Path(env_dir)
        if p.is_dir():
            return p

    system = platform.system()
    candidates = []

    if system == "Windows":
        home = Path(os.environ.get("USERPROFILE", ""))
        candidates = [
            home / "OneDrive" / "Documents" / "My Games" / "FarmingSimulator2025" / "mods",
            home / "Documents" / "My Games" / "FarmingSimulator2025" / "mods",
            home / "My Documents" / "My Games" / "FarmingSimulator2025" / "mods",
        ]
    elif system == "Darwin":
        home = Path.home()
        candidates = [
            home / "Library" / "Application Support" / "FarmingSimulator2025" / "mods",
            home / "Library" / "Containers" / "com.focus-home.farmingsimulator2025"
                 / "Data" / "Documents" / "FarmingSimulator2025" / "mods",
        ]
    else:  # Linux and others
        home = Path.home()
        candidates = [
            home / ".local" / "share" / "FarmingSimulator2025" / "mods",
            home / "Documents" / "My Games" / "FarmingSimulator2025" / "mods",
        ]

    for p in candidates:
        if p.is_dir():
            return p

    return None


def main():
    parser = argparse.ArgumentParser(description="Build FS25_NPCFavor.zip for Farming Simulator 25")
    parser.add_argument("--deploy", "-d", action="store_true",
                        help="Copy zip to FS25 mods folder after building")
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    output_path = script_dir / ZIP_NAME

    # Remove old zip if present
    if output_path.exists():
        output_path.unlink()

    # Build
    file_count = build_zip(script_dir, output_path)

    if not output_path.exists() or file_count == 0:
        print("ERROR: zip not created", file=sys.stderr)
        sys.exit(1)

    size = output_path.stat().st_size
    print(f"Built: {ZIP_NAME} ({size:,} bytes, {file_count} files)")

    # Deploy
    if args.deploy:
        mods_folder = find_mods_folder()
        if not mods_folder:
            print("WARNING: FS25 mods folder not found at any standard location.", file=sys.stderr)
            print(file=sys.stderr)
            print("  Set it manually and re-run:", file=sys.stderr)
            if platform.system() == "Windows":
                print('    set FS25_MODS_DIR=C:\\path\\to\\FarmingSimulator2025\\mods', file=sys.stderr)
                print("    python build.py --deploy", file=sys.stderr)
            else:
                print('    export FS25_MODS_DIR="/path/to/FarmingSimulator2025/mods"', file=sys.stderr)
                print("    python build.py --deploy", file=sys.stderr)
            sys.exit(1)

        dest = mods_folder / ZIP_NAME
        shutil.copy2(output_path, dest)
        print(f"Deployed: {dest}")


if __name__ == "__main__":
    main()

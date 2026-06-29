#!/usr/bin/env python3
"""Build bootstrap.dat and a distributable blockchain archive for InfiniteRicks.

Creates:
  - bootstrap.dat (concatenated blk*.dat block files)
  - MANIFEST.json (metadata for publishers)
  - README.txt (end-user import instructions)
  - .tar.gz package and SHA256 checksum files

Example:
  ./contrib/make_bootstrap.py
  ./contrib/make_bootstrap.py --datadir ~/.InfiniteRicks --full
  ./contrib/make_bootstrap.py --testnet --output-dir /tmp/bootstrap-out
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import tarfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable, List, Optional

MAGIC_MAINNET = bytes((0xC9, 0x09, 0x6E, 0x5A))
MAGIC_TESTNET = bytes((0x70, 0x6E, 0x7D, 0x0A))
MAX_BLOCK_SIZE = 16 * 1024 * 1024


def default_datadir(testnet: bool) -> Path:
    home = Path.home()
    if sys.platform == "win32":
        appdata = os.environ.get("APPDATA")
        base = Path(appdata) if appdata else home / "AppData" / "Roaming"
        path = base / "InfiniteRicks"
    elif sys.platform == "darwin":
        path = home / "Library" / "Application Support" / "InfiniteRicks"
    else:
        path = home / ".InfiniteRicks"
    if testnet:
        path /= "testnet"
    return path


def list_blk_files(datadir: Path) -> List[Path]:
    files = sorted(datadir.glob("blk*.dat"))
    return files


def daemon_maybe_running(datadir: Path) -> bool:
    for name in (".lock", "db.log.lock"):
        if (datadir / name).exists():
            return True
    try:
        out = subprocess.check_output(["pgrep", "-f", "InfiniteRicks"], stderr=subprocess.DEVNULL)
        return bool(out.strip())
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False


def count_blocks(path: Path, magic: bytes) -> int:
    data = path.read_bytes()
    count = 0
    pos = 0
    while pos < len(data):
        idx = data.find(magic, pos)
        if idx == -1:
            break
        if idx + 8 > len(data):
            break
        (nsize,) = struct.unpack_from("<I", data, idx + 4)
        if nsize == 0 or nsize > MAX_BLOCK_SIZE:
            pos = idx + 1
            continue
        end = idx + 8 + nsize
        if end > len(data):
            break
        count += 1
        pos = end
    return count


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def human_size(num_bytes: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    size = float(num_bytes)
    for unit in units:
        if size < 1024.0 or unit == units[-1]:
            return f"{size:.2f} {unit}"
        size /= 1024.0
    return f"{num_bytes} B"


def rpc_block_height(url: str, user: str, password: str) -> Optional[int]:
    import base64
    import json
    import urllib.request

    payload = json.dumps(
        {"jsonrpc": "1.0", "id": "bootstrap", "method": "getblockcount", "params": []}
    ).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method="POST")
    req.add_header("Content-Type", "application/json")
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("ascii")
    req.add_header("Authorization", f"Basic {token}")
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.loads(resp.read().decode("utf-8"))
        if body.get("error"):
            return None
        return int(body["result"])
    except Exception:
        return None


def write_readme(path: Path, network: str, package_name: str) -> None:
    path.write_text(
        f"""InfiniteRicks blockchain bootstrap package
============================================

Network: {network}
Package: {package_name}

IMPORT (bootstrap.dat only)
---------------------------
1. Close InfiniteRicks / InfiniteRicks-qt completely.
2. Open the wallet data directory:
   - Linux:   ~/.InfiniteRicks{'/testnet' if network == 'testnet' else ''}
   - macOS:   ~/Library/Application Support/InfiniteRicks{'/testnet' if network == 'testnet' else ''}
   - Windows: %APPDATA%\\InfiniteRicks{'\\testnet' if network == 'testnet' else ''}
3. Copy bootstrap.dat into that folder (replace if prompted).
4. Start the wallet. It imports automatically and renames the file to bootstrap.dat.old.
5. Wait for import and verification to finish, then let the wallet sync remaining blocks.

IMPORT (full snapshot with txleveldb/)
--------------------------------------
1. Close the wallet completely.
2. Back up your existing data directory.
3. Extract blk*.dat into the data directory and replace the txleveldb/ folder from this archive.
4. Start the wallet. Sync should be much faster than importing bootstrap.dat alone.

SECURITY
--------
- Verify SHA256 checksums before extracting.
- Never copy wallet.dat from someone else.
- Download bootstrap files only from trusted official sources.
""",
        encoding="utf-8",
    )


def build_bootstrap(datadir: Path, output_dir: Path, force: bool) -> Path:
    blk_files = list_blk_files(datadir)
    if not blk_files:
        raise SystemExit(f"No blk*.dat files found in {datadir}")

    output_dir.mkdir(parents=True, exist_ok=True)
    bootstrap_path = output_dir / "bootstrap.dat"
    if bootstrap_path.exists() and not force:
        raise SystemExit(f"Refusing to overwrite existing file: {bootstrap_path} (use --force)")

    tmp_path = bootstrap_path.with_suffix(".dat.tmp")
    with tmp_path.open("wb") as out:
        for blk in blk_files:
            with blk.open("rb") as src:
                shutil.copyfileobj(src, out, length=1024 * 1024)
    tmp_path.replace(bootstrap_path)
    return bootstrap_path


def create_archive(
    staging_dir: Path,
    archive_path: Path,
    items: Iterable[Path],
    force: bool,
) -> None:
    if archive_path.exists():
        if not force:
            raise SystemExit(f"Refusing to overwrite archive: {archive_path} (use --force)")
        archive_path.unlink()

    with tarfile.open(archive_path, "w:gz") as tar:
        for item in items:
            tar.add(item, arcname=item.name)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--datadir", type=Path, help="InfiniteRicks data directory")
    parser.add_argument("--testnet", action="store_true", help="Use testnet data directory")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("bootstrap-release"),
        help="Directory for generated files (default: ./bootstrap-release)",
    )
    parser.add_argument(
        "--full",
        action="store_true",
        help="Also package txleveldb/ for faster restore (requires wallet stopped)",
    )
    parser.add_argument("--force", action="store_true", help="Overwrite existing outputs")
    parser.add_argument("--name", help="Archive base name (default: infinitericks-bootstrap-YYYYMMDD)")
    parser.add_argument("--rpc-url", help="JSON-RPC URL (default: mainnet 31648, testnet 41648)")
    parser.add_argument("--rpc-user", default="rpcuser")
    parser.add_argument("--rpc-password", default="rpcpassword")
    parser.add_argument(
        "--allow-running",
        action="store_true",
        help="Do not abort when the wallet daemon appears to be running",
    )
    args = parser.parse_args()

    datadir = args.datadir or default_datadir(args.testnet)
    datadir = datadir.expanduser().resolve()
    if not datadir.is_dir():
        raise SystemExit(f"Data directory not found: {datadir}")

    rpc_url = args.rpc_url or (
        "http://127.0.0.1:41648" if args.testnet else "http://127.0.0.1:31648"
    )

    if not args.allow_running and daemon_maybe_running(datadir):
        raise SystemExit(
            "InfiniteRicks appears to be running. Stop the daemon/GUI before building "
            "a bootstrap package, or pass --allow-running if you know the files are idle."
        )

    network = "testnet" if args.testnet else "mainnet"
    magic = MAGIC_TESTNET if args.testnet else MAGIC_MAINNET
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d")
    package_name = args.name or f"infinitericks-{network}-bootstrap-{stamp}"

    output_dir = args.output_dir.expanduser().resolve()
    staging_dir = output_dir / package_name
    if staging_dir.exists():
        if not args.force:
            raise SystemExit(f"Refusing to overwrite staging dir: {staging_dir} (use --force)")
        shutil.rmtree(staging_dir)
    staging_dir.mkdir(parents=True, exist_ok=True)

    blk_files = list_blk_files(datadir)
    print(f"Using data directory: {datadir}")
    print(f"Found {len(blk_files)} block file(s)")

    bootstrap_path = build_bootstrap(datadir, staging_dir, force=True)
    block_count = count_blocks(bootstrap_path, magic)
    bootstrap_size = bootstrap_path.stat().st_size
    print(f"Created {bootstrap_path} ({human_size(bootstrap_size)}, ~{block_count} blocks)")

    packaged_items = [bootstrap_path]
    txleveldb_src = datadir / "txleveldb"
    if args.full:
        if not txleveldb_src.is_dir():
            raise SystemExit(f"--full requested but txleveldb/ not found in {datadir}")
        txleveldb_dst = staging_dir / "txleveldb"
        shutil.copytree(txleveldb_src, txleveldb_dst)
        packaged_items.append(txleveldb_dst)
        for blk in blk_files:
            dst = staging_dir / blk.name
            shutil.copy2(blk, dst)
            packaged_items.append(dst)
        print(f"Included txleveldb/ and {len(blk_files)} blk*.dat file(s) for full snapshot")

    chain_height = rpc_block_height(rpc_url, args.rpc_user, args.rpc_password)
    manifest = {
        "coin": "InfiniteRicks",
        "network": network,
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "source_datadir": str(datadir),
        "package_name": package_name,
        "bootstrap": {
            "path": "bootstrap.dat",
            "size_bytes": bootstrap_size,
            "sha256": sha256_file(bootstrap_path),
            "estimated_blocks": block_count,
        },
        "blk_files": [p.name for p in blk_files],
        "includes_txleveldb": bool(args.full),
        "chain_height_rpc": chain_height,
    }
    manifest_path = staging_dir / "MANIFEST.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    write_readme(staging_dir / "README.txt", network, package_name)
    packaged_items.extend([manifest_path, staging_dir / "README.txt"])

    archive_path = output_dir / f"{package_name}.tar.gz"
    create_archive(staging_dir, archive_path, packaged_items, force=args.force)
    archive_hash = sha256_file(archive_path)

    checksums_path = output_dir / "checksums.sha256"
    checksum_lines = [
        f"{archive_hash}  {archive_path.name}",
        f"{manifest['bootstrap']['sha256']}  {package_name}/bootstrap.dat",
    ]
    checksums_path.write_text("\n".join(checksum_lines) + "\n", encoding="utf-8")

    archive_checksum_path = output_dir / f"{archive_path.name}.sha256"
    archive_checksum_path.write_text(f"{archive_hash}  {archive_path.name}\n", encoding="utf-8")

    print("")
    print("Package ready:")
    print(f"  Archive:    {archive_path} ({human_size(archive_path.stat().st_size)})")
    print(f"  SHA256:     {archive_hash}")
    print(f"  Checksums:  {checksums_path}")
    print(f"  Manifest:   {manifest_path}")
    if chain_height is not None:
        print(f"  RPC height: {chain_height}")
    else:
        print("  RPC height: unavailable (optional)")
    print("")
    print("Publish the .tar.gz and .sha256 files together.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Print hardened checkpoint lines for src/checkpoints.cpp from a synced node.

Usage:
  ./contrib/dump_checkpoints.py --height 1500000
  ./contrib/dump_checkpoints.py --interval 100000 --max-height 1500000

Requires JSON-RPC (default: http://127.0.0.1:31648).
"""

import argparse
import json
import sys
import urllib.request


def rpc(url, user, password, method, params=None):
    payload = {
        "jsonrpc": "1.0",
        "id": "dump-checkpoints",
        "method": method,
        "params": params or [],
    }
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(url, data=data, method="POST")
    req.add_header("Content-Type", "application/json")
    auth = f"{user}:{password}".encode("utf-8")
    import base64

    req.add_header("Authorization", "Basic " + base64.b64encode(auth).decode("ascii"))
    with urllib.request.urlopen(req, timeout=30) as resp:
        body = json.loads(resp.read().decode("utf-8"))
    if body.get("error"):
        raise RuntimeError(body["error"])
    return body["result"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rpc-url", default="http://127.0.0.1:31648")
    parser.add_argument("--rpc-user", default="rpcuser")
    parser.add_argument("--rpc-password", default="rpcpassword")
    parser.add_argument("--height", type=int, action="append", help="Explicit block height")
    parser.add_argument("--interval", type=int, default=0, help="Generate every N blocks")
    parser.add_argument("--max-height", type=int, default=0, help="Tip or cap when using --interval")
    args = parser.parse_args()

    tip = args.max_height or int(rpc(args.rpc_url, args.rpc_user, args.rpc_password, "getblockcount"))
    heights = set(args.height or [])
    if args.interval > 0:
        h = args.interval
        while h <= tip:
            heights.add(h)
            h += args.interval
    if not heights:
        heights.add(tip)

    print("        // Paste into mapCheckpoints in src/checkpoints.cpp")
    for height in sorted(heights):
        block_hash = rpc(args.rpc_url, args.rpc_user, args.rpc_password, "getblockhash", [height])
        print(f'        ( {height}, uint256("{block_hash}") ),')
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)

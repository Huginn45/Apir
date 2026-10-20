#!/usr/bin/env python3
"""
End-to-End Verification Client for Apir Desktop Server (`server.py`).
Simulates the mobile QR pairing handshake and exercises the full WebSocket protocol.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from websockets.asyncio.client import connect


async def run_verification(uri: str, token: str) -> None:
    print(f"[1/4] Connecting to Apir Server at {uri} ...")
    async with connect(uri) as ws:
        # Step 1: Test rejection of invalid PIN token
        print("[2/4] Verifying token security (sending invalid PIN '0000' if token != '0000')...")
        bad_token = "9999" if token != "9999" else "0000"
        await ws.send(json.dumps({"type": "handshake", "token": bad_token}))
        bad_resp = json.loads(await ws.recv())
        print(f"      -> Invalid token response: {bad_resp}")
        assert bad_resp.get("status") == "error", "Expected error status for invalid token"

        # Step 2: Send valid QR Handshake token
        print(f"[3/4] Sending valid Apir Handshake with PIN token '{token}'...")
        await ws.send(json.dumps({"type": "handshake", "token": token}))
        ack_resp = json.loads(await ws.recv())
        print(f"      -> Handshake response: {ack_resp}")
        assert ack_resp.get("type") == "handshake_ack" and ack_resp.get("status") == "ok", (
            f"Handshake failed: {ack_resp}"
        )
        print(f"      -> Paired with host: {ack_resp.get('host')} (QR popup auto-closed!)")

        # Step 3: Exercise all remote control event types
        test_events = [
            {"type": "move", "dx": 15.0, "dy": -10.0, "ack": True},
            {"type": "move", "dx": -15.0, "dy": 10.0, "ack": True},
            {"type": "laser", "active": True, "dx": 5.0, "dy": 5.0, "ack": True},
            {"type": "move", "dx": -5.0, "dy": -5.0, "ack": True},
            {"type": "laser", "active": False, "dx": 0.0, "dy": 0.0, "ack": True},
            {"type": "scroll", "dy": -1.0, "ack": True},
            {"type": "scroll", "dy": 1.0, "ack": True},
            {"type": "slide", "dir": "next", "ack": True},
            {"type": "slide", "dir": "prev", "ack": True},
            {"type": "volume", "action": "up", "ack": True},
            {"type": "volume", "action": "down", "ack": True},
            {"type": "text", "value": "A", "ack": True},
            {"type": "text", "value": "Backspace", "ack": True},
            {"type": "dnd", "active": True, "ack": True},
            {"type": "dnd", "active": False, "ack": True},
        ]

        print(f"[4/4] Dispatching {len(test_events)} presenter control events...")
        for idx, event in enumerate(test_events, start=1):
            await ws.send(json.dumps(event))
            resp = json.loads(await ws.recv())
            assert resp.get("status") == "ok", f"Command {event} failed: {resp}"
            print(f"      ({idx}/{len(test_events)}) Verified '{event['type']}' -> {resp}")
            await asyncio.sleep(0.08)

    print("\nSUCCESS: All Apir QR Handshake and presenter input events verified cleanly!")


def main() -> None:
    parser = argparse.ArgumentParser(description="Apir E2E Test Client")
    parser.add_argument("--uri", type=str, default="ws://127.0.0.1:8765", help="Server WebSocket URI")
    parser.add_argument("--token", type=str, required=True, help="4-digit session PIN")
    args = parser.parse_args()

    try:
        asyncio.run(run_verification(args.uri, args.token))
    except Exception as exc:
        print(f"ERROR: Verification failed: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

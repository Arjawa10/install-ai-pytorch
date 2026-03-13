#!/usr/bin/env python3
"""
test_connection.py — Ollama Connectivity Test
==============================================
Quickly verify that Ollama is reachable and the vision model is working.
Useful for debugging from JupyterLab or inside Docker containers.

Usage:
    python3 test_connection.py
    python3 test_connection.py --ollama-url http://172.17.0.1:11434
"""

import argparse
import base64
import io
import json
import struct
import sys
import time
import zlib

import requests

# Candidate Ollama hosts tried when no URL is specified
CANDIDATE_HOSTS = [
    "http://localhost:11434",
    "http://127.0.0.1:11434",
    "http://172.17.0.1:11434",    # Docker default gateway
    "http://172.18.0.1:11434",
    "http://172.19.0.1:11434",
    "http://host.docker.internal:11434",
]

DEFAULT_VISION_MODEL = "qwen2.5vl:72b"


def _png_chunk(tag: bytes, data: bytes) -> bytes:
    """Build a PNG chunk: length (4 bytes) + tag + data + CRC32 (4 bytes)."""
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


# ─── Tiny dummy PNG (64×64 solid blue square) ─────────────────────────────────

def make_test_image_b64() -> str:
    """Create a small PNG image in memory and return its base64 encoding."""
    try:
        from PIL import Image

        buf = io.BytesIO()
        Image.new("RGB", (64, 64), color=(70, 130, 180)).save(buf, format="PNG")
        return base64.b64encode(buf.getvalue()).decode()
    except ImportError:
        pass

    # Fallback: minimal 1×1 white PNG (pure bytes, no libraries needed)
    import struct
    import zlib

    png = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(b"\x00\xff\xff\xff"))
        + _png_chunk(b"IEND", b"")
    )
    return base64.b64encode(png).decode()


# ─── Test functions ───────────────────────────────────────────────────────────

def test_connectivity(host: str) -> bool:
    """Check if Ollama is reachable at *host* and print the result."""
    try:
        r = requests.get(f"{host}/api/tags", timeout=3)
        if r.status_code == 200:
            print(f"  ✅ {host}  →  reachable (HTTP {r.status_code})")
            return True
        else:
            print(f"  ⚠  {host}  →  HTTP {r.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print(f"  ❌ {host}  →  connection refused")
    except requests.exceptions.Timeout:
        print(f"  ❌ {host}  →  timed out")
    except Exception as e:
        print(f"  ❌ {host}  →  {e}")
    return False


def list_models(base_url: str) -> list:
    """Return a list of model names available in Ollama."""
    try:
        r = requests.get(f"{base_url}/api/tags", timeout=5)
        r.raise_for_status()
        return [m["name"] for m in r.json().get("models", [])]
    except Exception as e:
        print(f"  ⚠  Could not list models: {e}")
        return []


def test_vision(base_url: str, model: str) -> bool:
    """Send a dummy image to the vision model and print a short response."""
    img_b64 = make_test_image_b64()
    print(f"  Sending test image to model '{model}' …", end=" ", flush=True)
    t0 = time.time()
    try:
        r = requests.post(
            f"{base_url}/api/generate",
            json={
                "model": model,
                "prompt": "Describe this image in one short sentence.",
                "images": [img_b64],
                "stream": False,
                "options": {"temperature": 0.1, "num_predict": 60},
            },
            timeout=120,
        )
        r.raise_for_status()
        response = r.json().get("response", "").strip()
        elapsed = time.time() - t0
        if response:
            print(f"✅ ({elapsed:.1f}s)")
            print(f"  Model says: \"{response[:150]}\"")
            return True
        else:
            print(f"⚠  ({elapsed:.1f}s) Empty response")
            return False
    except requests.exceptions.Timeout:
        print(f"❌ Timed out after {time.time() - t0:.0f}s")
    except Exception as e:
        print(f"❌ {e}")
    return False


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Test Ollama connectivity and vision model",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--ollama-url",
        default="",
        help="Ollama base URL (e.g. http://172.17.0.1:11434). "
             "If omitted, all candidates are tested.",
    )
    parser.add_argument(
        "--model",
        default=DEFAULT_VISION_MODEL,
        help=f"Vision model to test (default: {DEFAULT_VISION_MODEL})",
    )
    parser.add_argument(
        "--skip-vision",
        action="store_true",
        help="Skip the vision model test (only test connectivity)",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("  Ollama Connectivity Test")
    print("=" * 60)

    # ── Step 1: connectivity ──────────────────────────────────────────────────
    print("\n[1/3] Testing connectivity:")

    if args.ollama_url:
        candidates = [args.ollama_url.rstrip("/")]
    else:
        candidates = CANDIDATE_HOSTS

    working_url = ""
    for host in candidates:
        if test_connectivity(host):
            if not working_url:
                working_url = host

    if not working_url:
        print("\n❌ Could not reach Ollama at any tested URL.")
        print("   Troubleshooting tips:")
        print("   • On the VPS host: sudo systemctl status ollama")
        print("   • Check binding:   ss -tlnp | grep 11434")
        print("   • Re-run setup:    bash setup.sh")
        sys.exit(1)

    print(f"\n  ➡ Using: {working_url}")

    # ── Step 2: list models ───────────────────────────────────────────────────
    print("\n[2/3] Available models:")
    models = list_models(working_url)
    if models:
        for m in models:
            print(f"  • {m}")
    else:
        print("  (no models found or could not list)")

    # ── Step 3: vision test ───────────────────────────────────────────────────
    if args.skip_vision:
        print("\n[3/3] Vision test: skipped (--skip-vision)")
    else:
        print(f"\n[3/3] Testing vision model ({args.model}):")
        model_base = args.model.split(":")[0]
        if models and not any(model_base in m for m in models):
            print(f"  ⚠  Model '{args.model}' not found. Pull it with:")
            print(f"     ollama pull {args.model}")
            print("  Skipping vision test.")
        else:
            vision_ok = test_vision(working_url, args.model)
            if not vision_ok:
                print("  Tip: the model may still be loading — wait a moment and retry.")

    # ── Summary ───────────────────────────────────────────────────────────────
    print("\n" + "=" * 60)
    print(f"  Ollama URL for your scripts: {working_url}")
    print("=" * 60)
    print("\nExample Python usage:")
    print(f'  OLLAMA_URL = "{working_url}"')
    print('  requests.get(f"{OLLAMA_URL}/api/tags")')


if __name__ == "__main__":
    main()

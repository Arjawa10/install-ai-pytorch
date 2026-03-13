#!/usr/bin/env python3
"""
vlm_metadata_export.py — Vision LLM Image Metadata Export
==========================================================
Sends images from a folder to an Ollama vision model and exports
metadata (title, description, keywords, category, mood, colors) to CSV.

Usage:
    python3 vlm_metadata_export.py
    python3 vlm_metadata_export.py --folder /path/to/images
    python3 vlm_metadata_export.py --folder /path/to/images --output results.csv
    python3 vlm_metadata_export.py --folder /path/to/images --model qwen2.5vl:72b
    python3 vlm_metadata_export.py --ollama-url http://172.17.0.1:11434

Configuration:
    Edit the variables in the CONFIG section below, or pass CLI arguments.
"""

import argparse
import base64
import csv
import json
import os
import re
import sys
import time
from pathlib import Path

import requests

# =============================================================================
# CONFIG — edit these defaults as needed
# =============================================================================

FOLDER_PATH = "./images"           # Folder containing images to process
OUTPUT_CSV  = "metadata_vlm.csv"  # Output CSV file path
OLLAMA_URL  = ""                   # Leave empty for auto-detection
MODEL_NAME  = "llama3.2-vision:11b"

# Candidate Ollama hosts (tried in order during auto-detection)
OLLAMA_HOST_CANDIDATES = [
    "http://localhost:11434",
    "http://127.0.0.1:11434",
    "http://172.17.0.1:11434",    # Docker default gateway
    "http://172.18.0.1:11434",
    "http://172.19.0.1:11434",
    "http://host.docker.internal:11434",
]

SUPPORTED_EXTENSIONS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif"}

PROMPT = """Analyze this image and return metadata as valid JSON only, with exactly these fields:
{
  "title": "concise descriptive title (5-12 words)",
  "description": "detailed description of the image (2-3 sentences)",
  "keywords": ["10 to 15 relevant keywords"],
  "category": "one of: nature/food/architecture/people/animal/technology/vehicle/art/fashion/sport/travel/other",
  "mood": "overall mood or atmosphere of the image",
  "colors": ["top 3-5 dominant colors"]
}
Return ONLY valid JSON. No extra text, no markdown, no code blocks."""

# =============================================================================
# Helpers
# =============================================================================


def detect_ollama_url() -> str:
    """Try candidate Ollama hosts in order and return the first that responds."""
    for host in OLLAMA_HOST_CANDIDATES:
        try:
            r = requests.get(f"{host}/api/tags", timeout=3)
            if r.status_code == 200:
                print(f"✅ Ollama detected at: {host}")
                return host
        except requests.exceptions.RequestException:
            pass
    return ""


def list_models(base_url: str) -> list:
    """Return a list of model names available in Ollama."""
    try:
        r = requests.get(f"{base_url}/api/tags", timeout=5)
        r.raise_for_status()
        return [m["name"] for m in r.json().get("models", [])]
    except Exception:
        return []


def encode_image(image_path: str) -> str:
    """Base64-encode an image file."""
    with open(image_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")


def parse_json_response(text: str) -> dict:
    """
    Try to parse the model response as JSON.
    Falls back to regex extraction if the model wraps JSON in markdown.
    """
    # Direct parse
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass

    # Strip markdown code fences
    stripped = re.sub(r"```(?:json)?", "", text).strip()
    try:
        return json.loads(stripped)
    except json.JSONDecodeError:
        pass

    # Extract first {...} block
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass

    return {}


def analyze_image(image_path: str, base_url: str, model: str, timeout: int = 300) -> dict:
    """
    Send an image to Ollama and return parsed metadata dict.
    Raises requests.exceptions.RequestException on network errors.
    """
    img_b64 = encode_image(image_path)
    payload = {
        "model": model,
        "prompt": PROMPT,
        "images": [img_b64],
        "stream": False,
        "options": {"temperature": 0.1},
    }
    r = requests.post(f"{base_url}/api/generate", json=payload, timeout=timeout)
    r.raise_for_status()
    raw_text = r.json().get("response", "")
    return parse_json_response(raw_text), raw_text


def flatten_list_field(value) -> str:
    """Convert a list to a comma-separated string, or return the value as-is."""
    if isinstance(value, list):
        return ", ".join(str(v) for v in value)
    return str(value) if value is not None else ""


# =============================================================================
# Main
# =============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Export image metadata to CSV using Ollama Vision LLM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--folder",     default=FOLDER_PATH, help="Folder containing images")
    parser.add_argument("--output",     default=OUTPUT_CSV,  help="Output CSV file path")
    parser.add_argument("--model",      default=MODEL_NAME,  help="Ollama model name")
    parser.add_argument("--ollama-url", default=OLLAMA_URL,  help="Ollama base URL (auto-detected if empty)")
    args = parser.parse_args()

    folder   = Path(args.folder).expanduser().resolve()
    out_csv  = Path(args.output).expanduser().resolve()
    model    = args.model
    base_url = args.ollama_url.rstrip("/") if args.ollama_url else ""

    print("=" * 60)
    print("  Vision LLM Metadata Export")
    print("=" * 60)

    # ── Ollama connectivity ──────────────────────────────────────────────────
    if not base_url:
        print("🔍 Auto-detecting Ollama URL...")
        base_url = detect_ollama_url()
        if not base_url:
            print(
                "❌ Could not connect to Ollama at any of the candidate URLs:\n"
                + "\n".join(f"  {u}" for u in OLLAMA_HOST_CANDIDATES)
                + "\nMake sure Ollama is running. See README.md for troubleshooting.",
                file=sys.stderr,
            )
            sys.exit(1)
    else:
        # Verify provided URL
        try:
            r = requests.get(f"{base_url}/api/tags", timeout=5)
            r.raise_for_status()
            print(f"✅ Connected to Ollama at: {base_url}")
        except Exception as e:
            print(f"❌ Cannot reach Ollama at {base_url}: {e}", file=sys.stderr)
            sys.exit(1)

    # ── Model check ──────────────────────────────────────────────────────────
    available_models = list_models(base_url)
    model_base = model.split(":")[0]
    if available_models and not any(model_base in m for m in available_models):
        print(f"⚠ Model '{model}' not found in Ollama. Available: {available_models}")
        print(f"  Pull it with: ollama pull {model}")
        sys.exit(1)
    print(f"🤖 Model : {model}")

    # ── Image discovery ──────────────────────────────────────────────────────
    if not folder.exists():
        print(f"❌ Folder not found: {folder}", file=sys.stderr)
        sys.exit(1)

    image_files = sorted(
        p for p in folder.iterdir()
        if p.is_file() and p.suffix.lower() in SUPPORTED_EXTENSIONS
    )

    if not image_files:
        print(f"⚠ No supported images found in: {folder}")
        print(f"  Supported extensions: {', '.join(sorted(SUPPORTED_EXTENSIONS))}")
        sys.exit(0)

    print(f"📁 Folder : {folder}")
    print(f"📄 Output : {out_csv}")
    print(f"🖼  Images : {len(image_files)} found")
    print("=" * 60)

    # ── Process images ───────────────────────────────────────────────────────
    CSV_FIELDS = ["Filename", "Title", "Description", "Keywords", "Category", "Mood", "Colors", "Error"]
    results = []
    errors  = 0

    for idx, img_path in enumerate(image_files, start=1):
        prefix = f"[{idx}/{len(image_files)}]"
        print(f"{prefix} 🔍 {img_path.name} ...", end=" ", flush=True)
        t0 = time.time()

        try:
            meta, _ = analyze_image(str(img_path), base_url, model)
            elapsed = time.time() - t0

            row = {
                "Filename":    img_path.name,
                "Title":       meta.get("title", ""),
                "Description": meta.get("description", ""),
                "Keywords":    flatten_list_field(meta.get("keywords", "")),
                "Category":    meta.get("category", ""),
                "Mood":        meta.get("mood", ""),
                "Colors":      flatten_list_field(meta.get("colors", "")),
                "Error":       "",
            }

            title_preview = row["Title"][:60] + "…" if len(row["Title"]) > 60 else row["Title"]
            print(f"✅ ({elapsed:.1f}s) {title_preview}")

        except Exception as e:
            elapsed = time.time() - t0
            err_msg = str(e)
            print(f"❌ ({elapsed:.1f}s) {err_msg[:80]}")
            errors += 1
            row = {
                "Filename": img_path.name,
                "Title": "", "Description": "", "Keywords": "",
                "Category": "", "Mood": "", "Colors": "",
                "Error": err_msg,
            }

        results.append(row)

    # ── Write CSV ─────────────────────────────────────────────────────────────
    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(results)

    # ── Summary ───────────────────────────────────────────────────────────────
    print("=" * 60)
    print(f"🎉 Done!")
    print(f"   Processed : {len(results)} images")
    print(f"   Succeeded : {len(results) - errors}")
    print(f"   Errors    : {errors}")
    print(f"   CSV saved : {out_csv}")
    print("=" * 60)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
# ============================================================================
# test_predict.py — Pruebas /health y /predict con todos los sample*.json
# Autor: John Gómez
# Fecha: 2025-09-25
# Descripción:
#   Script de prueba que consulta /health y luego recorre todos los JSON
#   ubicados en tests/data/sample*.json, enviando cada uno a /predict.
#   Compatible con requests (si está instalado) o urllib por defecto.
#
# Uso local:
#   python tests/test_predict.py
#
# Uso con API remota:
#   python tests/test_predict.py --base-url http://localhost:5000
#
# Variables de entorno:
#   API_URL → URL base de la API (ej: http://127.0.0.1:5000)
# ============================================================================

from __future__ import annotations
import os, sys, json, argparse
from pathlib import Path

# requests es opcional; si no está, se usa urllib
try:
    import requests  # type: ignore
except Exception:  # pragma: no cover
    requests = None


def http_get(url: str) -> dict:
    if requests is not None:
        r = requests.get(url, timeout=10)
        r.raise_for_status()
        return r.json()
    import urllib.request as ur
    with ur.urlopen(url, timeout=10) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_post(url: str, payload: dict) -> dict:
    if requests is not None:
        r = requests.post(url, json=payload, timeout=15)
        r.raise_for_status()
        return r.json()
    import urllib.request as ur, urllib.error as ue
    data = json.dumps(payload).encode("utf-8")
    req = ur.Request(url, data=data, headers={"Content-Type": "application/json"})
    try:
        with ur.urlopen(req, timeout=15) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except ue.HTTPError as e:  # pragma: no cover
        body = e.read().decode("utf-8")
        raise RuntimeError(f"HTTP {e.code}: {body}") from e


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--base-url",
        default=os.getenv("API_URL", "http://127.0.0.1:5000"),
        help="URL base de la API (ej: http://127.0.0.1:5000)",
    )
    args = ap.parse_args()
    base = args.base_url.rstrip("/")

    # 1) /health
    print(f"→ Probando HEALTH: {base}/health")
    h = http_get(f"{base}/health")
    print(json.dumps(h, indent=2, ensure_ascii=False))
    if not h.get("model_loaded", False):
        print("[ADVERTENCIA] El modelo no está cargado.", file=sys.stderr)

    # 2) samples
    data_dir = Path("tests") / "data"
    samples = sorted(data_dir.glob("sample*.json"))
    if not samples:
        print(f"[ERROR] No se encontraron samples en {data_dir}", file=sys.stderr)
        sys.exit(2)

    for p in samples:
        print(f"\n→ Probando PREDICT con {p.name}")
        payload = json.loads(p.read_text(encoding="utf-8"))
        r = http_post(f"{base}/predict", payload)
        print(json.dumps(r, indent=2, ensure_ascii=False))

    print("\n✓ Pruebas completadas correctamente.")


if __name__ == "__main__":
    main()




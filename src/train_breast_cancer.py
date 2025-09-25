# ============================================================================
# train_breast_cancer.py — Entrenamiento modelo Breast Cancer (Evaluación Modular)
# Autor: John Gómez
# Fecha: 2025-09-25
# Descripción:
#   Entrena un clasificador RandomForest sobre el dataset Breast Cancer Wisconsin,
#   normaliza las features con StandardScaler y guarda el artefacto como joblib.
#
# Artefacto:
#   src/model/modelo_breast.pkl (dict con {"model": pipeline, "meta": {...}})
#
# Meta-información guardada:
#   - n_features: número de características
#   - class_names: nombres de las clases
#   - test_accuracy: exactitud en test
#   - dataset: nombre del dataset
#
# Uso local:
#   python src/train_breast_cancer.py
#
# Uso con Makefile:
#   make train
# ============================================================================

from __future__ import annotations
import os, json, joblib
from pathlib import Path
from sklearn.datasets import load_breast_cancer
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score

# -------- Configuración --------
# Ruta del artefacto (configurable por env, por defecto: src/model/modelo_breast.pkl)
DEFAULT_PATH = Path(__file__).resolve().parent / "model" / "modelo_breast.pkl"
MODEL_PATH = Path(os.getenv("MODEL_PATH", str(DEFAULT_PATH)))

def main():
    data = load_breast_cancer()
    X, y = data.data, data.target

    # Split train/test
    Xtr, Xte, ytr, yte = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    # Pipeline: escalado + RandomForest
    pipe = Pipeline([
        ("scaler", StandardScaler()),
        ("rf", RandomForestClassifier(n_estimators=200, random_state=42))
    ])
    pipe.fit(Xtr, ytr)

    # Evaluación rápida
    acc = accuracy_score(yte, pipe.predict(Xte))

    # Meta-información
    meta = {
        "status": "ok",
        "n_features": X.shape[1],
        "class_names": list(data.target_names),
        "test_accuracy": round(float(acc), 4),
        "dataset": "breast_cancer_wisconsin"
    }

    # Crear carpeta destino si no existe
    MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)

    # Guardar artefacto
    joblib.dump({"model": pipe, "meta": meta}, MODEL_PATH)

    # Log en JSON
    print(json.dumps({"saved": str(MODEL_PATH), **meta}, ensure_ascii=False, indent=2))

if __name__ == "__main__":
    main()


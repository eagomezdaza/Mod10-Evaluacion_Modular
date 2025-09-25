# ============================================================================
# app.py — API Flask para clasificación Breast Cancer (Evaluación Modular)
# Autor: John Gómez
# Fecha: 2025-09-25
# Descripción:
#   API REST con validación (Pydantic), logs JSON con request_id por petición,
#   métricas Prometheus en /metrics y CORS habilitado.
#
# Endpoints:
#   - GET  /          → info del servicio
#   - GET  /health    → estado del modelo
#   - POST /predict   → predicción a partir de 30 características
#   - GET  /metrics   → métricas Prometheus (latencia, conteos)
#
# Uso local (dev):
#   export PORT=5000 MODEL_PATH=src/model/modelo_breast.pkl
#   python -m flask --app src.app:app run  # si defines app global
#   # o:
#   python src/app.py                       # ejecutable directo (create_app)
#
# Producción (Gunicorn):
#   gunicorn -w 2 -b 0.0.0.0:${PORT} 'src.app:create_app()'
# ============================================================================

from __future__ import annotations
import os, json, time, uuid, logging
from typing import List, Optional, Annotated

import joblib
import numpy as np
from flask import Flask, request, jsonify, g, Response
from flask_cors import CORS
from flask import has_request_context, g
from pydantic import BaseModel, Field, ValidationError
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST


# -------- Config por entorno (con defaults seguros para local) --------
APP_PORT = int(os.getenv("PORT", 5000))
# Para desarrollo local el modelo suele estar en src/model/...
# En Docker, el Dockerfile define MODEL_PATH=/app/src/model/modelo_breast.pkl
ARTIFACT_PATH = os.getenv("MODEL_PATH", "src/model/modelo_breast.pkl")

# ======== Métricas Prometheus ========
REQ_COUNT = Counter(
    "api_requests_total",
    "Total de requests",
    ["endpoint", "method", "status"]
)
REQ_LATENCY = Histogram(
    "api_request_latency_seconds",
    "Latencia por endpoint",
    ["endpoint", "method"]
)

# ======== Esquema de entrada con Pydantic (v2) ========
class PredictInput(BaseModel):
    # Lista de 30 floats exactos
    features: Annotated[List[float], Field(min_length=30, max_length=30)]

# ======== Utilidades de modelo ========
def load_artifact(path: str):
    """
    Se espera un joblib con un dict:
      {"model": <clf>, "meta": {"n_features": 30, "class_names": [...]}}
    """
    obj = joblib.load(path)
    model = obj["model"]
    meta = obj.get("meta", {})
    return model, meta

def n_features_expected(meta: dict) -> int:
    try:
        return int(meta.get("n_features", 30))
    except Exception:
        return 30

# ======== Logging JSON con request_id ========
class JsonFormatter(logging.Formatter):
    def format(self, record):
        base = {
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
        }
        # Solo intenta leer g.request_id si estamos dentro de un request
        if has_request_context():
            rid = getattr(g, "request_id", None)
            if rid:
                base["request_id"] = rid
        return json.dumps(base, ensure_ascii=False)

def configure_logging(app: Flask):
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    app.logger.handlers.clear()
    app.logger.addHandler(handler)
    app.logger.setLevel(logging.INFO)

def create_app() -> Flask:
    app = Flask(__name__)
    CORS(app)
    configure_logging(app)

    # Carga perezosa del modelo (al iniciar el proceso)
    app.model = None
    app.meta = {}
    app.load_error: Optional[str] = None
    try:
        app.model, app.meta = load_artifact(ARTIFACT_PATH)
        app.logger.info(f"Modelo cargado desde: {ARTIFACT_PATH}")
    except Exception as e:
        app.load_error = str(e)
        app.logger.error(f"Error cargando modelo: {app.load_error}")

    # ====== middleware: request_id + métricas ======
    @app.before_request
    def before():
        g.t0 = time.time()
        g.request_id = request.headers.get("X-Request-Id", str(uuid.uuid4()))

    @app.after_request
    def after(resp):
        endpoint = request.endpoint or "unknown"
        method = request.method
        # Importante: labels de Prometheus son strings
        REQ_COUNT.labels(endpoint, method, str(resp.status_code)).inc()
        REQ_LATENCY.labels(endpoint, method).observe(time.time() - g.get("t0", time.time()))
        resp.headers["X-Request-Id"] = g.request_id
        return resp

    # -------- Endpoints --------
    @app.get("/")
    def root():
        return jsonify({
            "status": "success",
            "message": "API ML Evaluación Modular",
            "model_path": ARTIFACT_PATH,
            "meta": app.meta,
            "load_error": app.load_error
        })

    @app.get("/health")
    def health():
        ok = (app.model is not None) and (app.load_error is None)
        return jsonify({
            "status": "ok" if ok else "error",
            "model_loaded": ok,
            "n_features": n_features_expected(app.meta),
            "meta": app.meta,
            "error": app.load_error
        }), (200 if ok else 500)

    @app.post("/predict")
    def predict():
        if app.model is None:
            return jsonify({
                "status": "error",
                "message": "Modelo no cargado",
                "error": app.load_error
            }), 500
        try:
            data = request.get_json(force=True, silent=False)
            payload = PredictInput(**data)
            X = np.array(payload.features, dtype=float).reshape(1, -1)

            proba = app.model.predict_proba(X)[0].tolist() if hasattr(app.model, "predict_proba") else None
            pred_idx = int(app.model.predict(X)[0])

            class_names = app.meta.get("class_names")
            pred_name = (class_names[pred_idx] if class_names else pred_idx)

            app.logger.info(f"Predicción OK: idx={pred_idx}, name={pred_name}")
            return jsonify({
                "status": "success",
                "prediction_index": pred_idx,
                "prediction": pred_name,
                "proba": proba,
                "request_id": g.request_id
            })
        except ValidationError as ve:
            app.logger.warning(f"Payload inválido: {ve.errors()}")
            return jsonify({"status":"error","message":"Payload inválido","details": ve.errors()}), 400
        except Exception as e:
            app.logger.exception("Error en /predict")
            return jsonify({"status":"error","message":str(e)}), 500

    @app.get("/metrics")
    def metrics():
        return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

    return app

# Ejecutable directamente (dev)
# Permite: python src/app.py
if __name__ == "__main__":
    app = create_app()
    app.run(host="0.0.0.0", port=APP_PORT)

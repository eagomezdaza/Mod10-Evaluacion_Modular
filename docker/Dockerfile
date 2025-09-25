# ============================================================================
# Dockerfile — API Flask (Breast Cancer) — Estructura Estandarizada
# Autor: John Gómez
# Fecha: 2025-09-25
#
# Descripción:
#   Imagen ligera basada en python:3.11-slim. Instala dependencias, copia el
#   código bajo /app/src, fija el PYTHONPATH y expone la API vía Gunicorn.
#
# Endpoints:
#   - GET  /              (pong opcional)
#   - GET  /health
#   - POST /predict
#
# Variables de entorno (puedes sobreescribir en runtime):
#   - PORT        → puerto de escucha (por defecto 5000)
#   - MODEL_PATH  → ruta absoluta del modelo dentro del contenedor
#   - PYTHONPATH  → /app/src para importaciones estilo "src.*"
#
# Uso local (con Makefile recomendado):
#   make docker-build
#   make docker-run
#
# Uso local (sin Makefile):
#   docker build -t em-api:v1 -f docker/Dockerfile .
#   docker run --rm -p 5000:5000 \
#     -e PORT=5000 \
#     -e MODEL_PATH=/app/src/model/modelo_breast.pkl \
#     em-api:v1
#
# Despliegue (Azure Container Apps):
#   - Empuja la imagen a ACR y actualiza la Container App (ver Makefile: push/update-aca)
# ============================================================================

FROM python:3.11-slim

# Ajustes Python
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Config por defecto (ajustable en runtime)
ENV PORT=5000
ENV MODEL_PATH=/app/src/model/modelo_breast.pkl
ENV PYTHONPATH=/app/src

# Dependencias mínimas (curl para healthcheck)
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 1) Instalar dependencias primero (mejor cache)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 2) Copiar el código (incluye app, utils, training y modelo)
COPY src/ ./src/

# Usuario no-root
RUN useradd -m appuser
USER appuser

# Healthcheck interno
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD curl -fsS http://127.0.0.1:${PORT}/health || exit 1

EXPOSE 5000

# Gunicorn producción
# - Si usas factory, cambia a: "src.app:create_app()"
CMD ["gunicorn", "-w", "2", "-b", "0.0.0.0:5000", "src.app:create_app()"]


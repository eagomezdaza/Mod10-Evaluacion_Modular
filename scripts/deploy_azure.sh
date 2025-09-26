#!/usr/bin/env bash
# ============================================================================
# deploy_azure.sh — Despliegue a Azure Container Apps (ACA) con ACR
# Autor: John Gómez
# Fecha: 2025-09-25
# Descripción:
#   Script idempotente para crear/actualizar:
#   - Resource Group
#   - Azure Container Registry (ACR)
#   - Azure Container Apps Environment (ACA env)
#   - Azure Container App (API Flask + ML)
#
#   Admite flags para reutilizar ACR existente y saltar el build/push
#   cuando la imagen ya fue publicada (p. ej., por CI).
#
#   Variables de entorno configurables:
#     LOCATION, RG, ACR, IMAGE, TAG, APP, ENV_NAME, PORT, MODEL_PATH
#     SKIP_BUILD (si=1, omite docker build/tag/push)
#     DOCKERFILE (ruta al Dockerfile; por defecto docker/Dockerfile)
# ============================================================================
set -euo pipefail

# -----------------------------
# Configuración (valores por defecto)
# -----------------------------
LOCATION="${LOCATION:-eastus}"
RG="${RG:-rg-evalmod-aca}"
ACR="${ACR:-acrevalmod$RANDOM}"          # Si no fijas ACR, crea uno único
IMAGE="${IMAGE:-em-api}"
TAG="${TAG:-v1}"
APP="${APP:-evalmod-api}"
ENV_NAME="${ENV_NAME:-env-evalmod}"
PORT="${PORT:-5002}"
MODEL_PATH="${MODEL_PATH:-src/model/modelo_breast.pkl}"
DOCKERFILE="${DOCKERFILE:-docker/Dockerfile}"

# Si vienes desde CI con una imagen ya publicada, evita rebuild
SKIP_BUILD="${SKIP_BUILD:-0}"

echo "=== Azure account ==="
az account show -o table || true
echo

# -----------------------------
# Recurso: Resource Group + ACR
# -----------------------------
echo "=== Crear RG y ACR (si no existen) ==="
az group create -n "$RG" -l "$LOCATION" 1>/dev/null

# Intenta crear ACR; si existe, continúa
az acr create -n "$ACR" -g "$RG" --sku Basic 1>/dev/null || true
ACR_LOGIN="$(az acr show -n "$ACR" --query loginServer -o tsv)"
echo "ACR: $ACR_LOGIN"

# -----------------------------
# Build y Push (opcional)
# -----------------------------
if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "=== Build & Push (local) ==="
  docker build -f "$DOCKERFILE" -t "$IMAGE:$TAG" .
  docker tag "$IMAGE:$TAG" "$ACR_LOGIN/$IMAGE:$TAG"
  az acr login -n "$ACR" 1>/dev/null
  docker push "$ACR_LOGIN/$IMAGE:$TAG"
else
  echo "=== SKIP_BUILD=1 :: se omite build/tag/push (imagen debe existir en ACR) ==="
fi

# -----------------------------
# Extensiones y providers
# -----------------------------
echo "=== Habilitar Container Apps ==="
az extension add --name containerapp --upgrade -y 1>/dev/null || true
az provider register --namespace Microsoft.App 1>/dev/null || true
az provider register --namespace Microsoft.OperationalInsights 1>/dev/null || true

# -----------------------------
# Entorno ACA
# -----------------------------
echo "=== Crear entorno ACA (si no existe) ==="
az containerapp env create \
  -g "$RG" -n "$ENV_NAME" -l "$LOCATION" 1>/dev/null || true

# Credenciales de ACR
ACR_USER="$(az acr credential show -n "$ACR" --query username -o tsv)"
ACR_PASS="$(az acr credential show -n "$ACR" --query passwords[0].value -o tsv)"

# -----------------------------
# App ACA (create/update)
# -----------------------------
echo "=== Crear/Actualizar Container App ==="
if ! az containerapp show -g "$RG" -n "$APP" 1>/dev/null 2>&1; then
  az containerapp create \
    -g "$RG" -n "$APP" \
    --environment "$ENV_NAME" \
    --image "$ACR_LOGIN/$IMAGE:$TAG" \
    --target-port "$PORT" \
    --ingress external \
    --env-vars PORT="$PORT" MODEL_PATH="$MODEL_PATH" \
    --registry-server "$ACR_LOGIN" \
    --registry-username "$ACR_USER" \
    --registry-password "$ACR_PASS" 1>/dev/null
else
  az containerapp update \
    -g "$RG" -n "$APP" \
    --image "$ACR_LOGIN/$IMAGE:$TAG" \
    --set-env-vars PORT="$PORT" MODEL_PATH="$MODEL_PATH" 1>/dev/null
fi

FQDN="$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)"
echo "URL pública: https://$FQDN"

# -----------------------------
# Pruebas rápidas
# -----------------------------
echo "=== Probar /health ==="
curl -s "https://$FQDN/health" || true; echo
echo "=== Probar /predict (recuerda enviar 30 features reales) ==="
curl -s -X POST "https://$FQDN/predict" \
     -H "Content-Type: application/json" \
     -d '{"features":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}' || true; echo

echo "Listo."


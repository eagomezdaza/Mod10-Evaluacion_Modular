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

# -----------------------------------
# Config por entorno (con defaults)
# -----------------------------------
LOCATION="${LOCATION:-eastus}"
RG="${RG:-rg-evalmod}"                # <- usa tu RG real
ENV_NAME="${ENV_NAME:-env-evalmod}"
APP="${APP:-evalmod-api}"

# Imagen
IMAGE="${IMAGE:-em-api}"
TAG="${TAG:-v1}"

# Puerto y modelo
PORT="${PORT:-5000}"                  # <- 5000 por defecto
MODEL_PATH="${MODEL_PATH:-src/model/modelo_breast.pkl}"

# Registry
ACR="${ACR:-}"                        # nombre del ACR (ej: acrevalmod16233) opcional si pasas ACR_LOGIN_SERVER
ACR_LOGIN="${ACR_LOGIN_SERVER:-}"     # login server (ej: acrevalmod16233.azurecr.io)
ACR_USERNAME="${ACR_USERNAME:-}"      # opcional - recomendado pasar por secrets
ACR_PASSWORD="${ACR_PASSWORD:-}"      # opcional - recomendado pasar por secrets

# Build (si ya hiciste build+push en el workflow, pon SKIP_BUILD=1)
SKIP_BUILD="${SKIP_BUILD:-0}"
DOCKERFILE="${DOCKERFILE:-docker/Dockerfile}"

echo "=== Contexto Azure ==="
az account show -o table || true
echo

# -----------------------------------
# Resolver ACR_LOGIN_SERVER
# -----------------------------------
if [[ -z "$ACR_LOGIN" ]]; then
  if [[ -n "$ACR" ]]; then
    ACR_LOGIN="$(az acr show -n "$ACR" --query loginServer -o tsv)"
  else
    echo "❌ Debes exportar ACR o ACR_LOGIN_SERVER"
    exit 1
  fi
fi
ACR_NAME_FROM_LOGIN="${ACR_LOGIN%%.*}"  # ej: acrevalmod16233

# -----------------------------------
# Asegurar RG
# -----------------------------------
echo "=== Crear RG si no existe ==="
az group create -n "$RG" -l "$LOCATION" 1>/dev/null

# -----------------------------------
# Build & Push (opcional)
# -----------------------------------
if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "=== Build & Push a ACR ==="
  az acr login -n "${ACR:-$ACR_NAME_FROM_LOGIN}" 1>/dev/null
  docker build -f "$DOCKERFILE" -t "$IMAGE:$TAG" .
  docker tag "$IMAGE:$TAG" "$ACR_LOGIN/$IMAGE:$TAG"
  docker push "$ACR_LOGIN/$IMAGE:$TAG"
else
  echo "=== SKIP_BUILD=1 :: omitiendo build/tag/push (la imagen ya debe existir en ACR) ==="
fi

# -----------------------------------
# Extensión y providers (solo check)
# -----------------------------------
echo "=== Verificando extensión y providers ==="
az extension add --name containerapp --upgrade -y 1>/dev/null || true
for NS in Microsoft.App Microsoft.OperationalInsights; do
  STATE="$(az provider show -n "$NS" --query registrationState -o tsv || echo "Unknown")"
  echo "$NS: $STATE"
  if [[ "$STATE" != "Registered" ]]; then
    echo "❌ Provider $NS no está 'Registered' en la suscripción."
    echo "   Regístralo fuera del pipeline: az provider register --namespace $NS"
    exit 1
  fi
done

# -----------------------------------
# Entorno de Container Apps
# -----------------------------------
echo "=== Crear entorno ACA si no existe ==="
if ! az containerapp env show -g "$RG" -n "$ENV_NAME" >/dev/null 2>&1; then
  az containerapp env create -g "$RG" -n "$ENV_NAME" -l "$LOCATION"
fi

# -----------------------------------
# Credenciales del registry
# -----------------------------------
REG_ARGS=""
if [[ -n "$ACR_USERNAME" && -n "$ACR_PASSWORD" ]]; then
  REG_ARGS="--registry-server $ACR_LOGIN --registry-username $ACR_USERNAME --registry-password $ACR_PASSWORD"
else
  echo "ℹ️ No llegaron ACR_USERNAME/ACR_PASSWORD; intentando obtener del ACR..."
  ACR_USER="$(az acr credential show -n "${ACR:-$ACR_NAME_FROM_LOGIN}" --query username -o tsv || true)"
  ACR_PASS="$(az acr credential show -n "${ACR:-$ACR_NAME_FROM_LOGIN}" --query passwords[0].value -o tsv || true)"
  if [[ -n "$ACR_USER" && -n "$ACR_PASS" ]]; then
    REG_ARGS="--registry-server $ACR_LOGIN --registry-username $ACR_USER --registry-password $ACR_PASS"
  else
    echo "❌ No se pudieron obtener credenciales del ACR. Pasa ACR_USERNAME y ACR_PASSWORD en el entorno."
    exit 1
  fi
fi

# -----------------------------------
# Crear/Actualizar la Container App
# -----------------------------------
IMAGE_URI="$ACR_LOGIN/$IMAGE:$TAG"
echo "=== Desplegando imagen: $IMAGE_URI ==="

if ! az containerapp show -g "$RG" -n "$APP" >/dev/null 2>&1; then
  az containerapp create \
    -g "$RG" -n "$APP" \
    --environment "$ENV_NAME" \
    --image "$IMAGE_URI" \
    --target-port "$PORT" \
    --ingress external \
    --env-vars PORT="$PORT" MODEL_PATH="$MODEL_PATH" \
    $REG_ARGS
else
  az containerapp update \
    -g "$RG" -n "$APP" \
    --image "$IMAGE_URI" \
    --set-env-vars PORT="$PORT" MODEL_PATH="$MODEL_PATH" \
    $REG_ARGS
fi

FQDN="$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)"
echo "URL pública: https://$FQDN"

# -----------------------------------
# Pruebas rápidas (no bloqueantes)
# -----------------------------------
echo "=== Probar /health ==="
curl -fsS "https://$FQDN/health" || true; echo
echo "=== Probar /predict (dummy 30 features) ==="
curl -fsS -X POST "https://$FQDN/predict" \
     -H "Content-Type: application/json" \
     -d '{"features":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}' || true; echo

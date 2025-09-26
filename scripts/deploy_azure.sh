#!/usr/bin/env bash
---
# deploy_azure.sh — Despliegue a Azure Container Apps (ACA) con ACR (cross-RG)
# Autor: John Gómez (ajustes por chat)
# Descripción:
#   - Reusa un ACA Environment existente (no intenta registrar providers).
#   - Actualiza la Container App si ya existe en ese environment, sin importar el RG.
#   - Crea la app sólo si NO existe en ese environment.
#
# Vars esperadas (con defaults razonables):
#   SUBS (opcional)
#   RG_ENV       = RG del ACA Environment (ej: rg-evalmod-aca2)
#   ENV_NAME     = nombre del ACA Environment (ej: env-evalmod2)
#   LOCATION     = región (ej: eastus)
#   RG_APP       = RG donde quieres/está la app (ej: rg-evalmod)
#   APP          = nombre de la app (ej: evalmod-api)
#   IMAGE        = repo de imagen (ej: em-api)
#   TAG          = tag (ej: $GITHUB_SHA)
#   PORT         = 5000
#   MODEL_PATH   = src/model/modelo_breast.pkl
#   ACR_LOGIN_SERVER (ej: acrevalmod16233.azurecr.io)  <-- recomendado
#   ACR_USERNAME / ACR_PASSWORD (recomendado, via secrets)
#   ACR          (opcional, si no pasas LOGIN_SERVER; ej: acrevalmod16233)
#   SKIP_BUILD   = 1 para omitir build/push (si lo hace el job anterior)
#   DOCKERFILE   = docker/Dockerfile
---

set -euo pipefail

# -------- Config esperada desde el workflow (con defaults) --------
SUBS="${SUBS:-}"
LOCATION="${LOCATION:-eastus}"

# Environment EXISTENTE (NO se crea aquí)
RG_ENV="${RG_ENV:-rg-evalmod-aca2}"
ENV_NAME="${ENV_NAME:-env-evalmod2}"

# App (en su RG)
RG_APP="${RG_APP:-rg-evalmod}"
APP="${APP:-evalmod-api}"

# Imagen
IMAGE="${IMAGE:-em-api}"
TAG="${TAG:-v1}"

# App config
PORT="${PORT:-5000}"
MODEL_PATH="${MODEL_PATH:-src/model/modelo_breast.pkl}"

# Registry
ACR_LOGIN="${ACR_LOGIN_SERVER:-}"
ACR="${ACR:-}"               # nombre si no pasas LOGIN_SERVER
ACR_USERNAME="${ACR_USERNAME:-}"
ACR_PASSWORD="${ACR_PASSWORD:-}"

# Build
SKIP_BUILD="${SKIP_BUILD:-0}"
DOCKERFILE="${DOCKERFILE:-docker/Dockerfile}"

echo "=== Contexto Azure ==="
az account show -o table || true
echo

# -------- Resolver ACR_LOGIN_SERVER --------
if [[ -z "$ACR_LOGIN" ]]; then
  if [[ -n "$ACR" ]]; then
    ACR_LOGIN="$(az acr show -n "$ACR" --query loginServer -o tsv)"
  else
    echo "❌ Debes exportar ACR_LOGIN_SERVER o ACR"; exit 1
  fi
fi
ACR_NAME_FROM_LOGIN="${ACR_LOGIN%%.*}"

# -------- Build & Push opcional --------
if [[ "$SKIP_BUILD" != "1" ]]; then
  echo "=== Build & Push a ACR ==="
  az acr login -n "${ACR:-$ACR_NAME_FROM_LOGIN}" 1>/dev/null
  docker build -f "$DOCKERFILE" -t "$IMAGE:$TAG" .
  docker tag "$IMAGE:$TAG" "$ACR_LOGIN/$IMAGE:$TAG"
  docker push "$ACR_LOGIN/$IMAGE:$TAG"
else
  echo "=== SKIP_BUILD=1 :: omitiendo build/tag/push (la imagen ya debe existir en ACR) ==="
fi

# -------- Extensión y providers (solo check) --------
echo "=== Verificando extensión y providers ==="
az extension add --name containerapp --upgrade -y 1>/dev/null || true
for NS in Microsoft.App Microsoft.OperationalInsights; do
  STATE="$(az provider show -n "$NS" --query registrationState -o tsv || echo Unknown)"
  echo "$NS: $STATE"
  if [[ "$STATE" != "Registered" ]]; then
    echo "❌ Provider $NS no está 'Registered'. Regístralo fuera del pipeline: az provider register --namespace $NS"
    exit 1
  fi
done

# -------- Verificar ENV existente (no crear) --------
echo "=== Comprobando ACA Environment existente ==="
ENV_ID="$(az containerapp env show -g "$RG_ENV" -n "$ENV_NAME" --query id -o tsv 2>/dev/null || true)"
if [[ -z "${ENV_ID:-}" ]]; then
  echo "❌ El ACA Environment '$ENV_NAME' no existe en RG '$RG_ENV'."
  echo "   Ajusta RG_ENV/ENV_NAME o crea el env manualmente en otra región."
  exit 1
fi
echo "ENV_ID: $ENV_ID"

# -------- Credenciales del registry --------
REG_ARGS=""
if [[ -n "${ACR_USERNAME:-}" && -n "${ACR_PASSWORD:-}" ]]; then
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

# -------- Crear / Actualizar la Container App --------
IMAGE_URI="$ACR_LOGIN/$IMAGE:$TAG"
echo "=== Despliegue de imagen: $IMAGE_URI ==="

if az containerapp show -g "$RG_APP" -n "$APP" >/dev/null 2>&1; then
  echo "🔁 Actualizando app existente: $APP (RG: $RG_APP)"
  az containerapp update \
    -g "$RG_APP" -n "$APP" \
    --image "$IMAGE_URI" \
    --set-env-vars PORT="$PORT" MODEL_PATH="$MODEL_PATH" \
    $REG_ARGS
else
  echo "🆕 Creando app: $APP (RG: $RG_APP) usando environment '$ENV_NAME'"
  az containerapp create \
    -g "$RG_APP" -n "$APP" \
    --environment "$ENV_ID" \
    --image "$IMAGE_URI" \
    --target-port "$PORT" \
    --ingress external \
    --env-vars PORT="$PORT" MODEL_PATH="$MODEL_PATH" \
    $REG_ARGS
fi

FQDN="$(az containerapp show -g "$RG_APP" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)"
echo "URL pública: https://$FQDN"

# -------- Smoke tests (no bloqueantes) --------
echo "=== Probar /health ==="
curl -fsS "https://$FQDN/health" || true; echo
echo "=== Probar /predict (dummy 30 features) ==="
curl -fsS -X POST "https://$FQDN/predict" \
     -H "Content-Type: application/json" \
     -d '{"features":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}' || true; echo
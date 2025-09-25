#!/usr/bin/env bash
set -euo pipefail

# Configuración (puedes exportar estas vars antes de ejecutar)
LOCATION="${LOCATION:-eastus}"
RG="${RG:-rg-evalmod-aca}"
ACR="${ACR:-acrevalmod$RANDOM}"   # debe ser único
IMAGE="${IMAGE:-em-api}"
TAG="${TAG:-v1}"
APP="${APP:-evalmod-api}"
ENV_NAME="${ENV_NAME:-env-evalmod}"
PORT="${PORT:-5002}"

echo "=== Azure account ==="
az account show -o table || true
echo

echo "=== Crear RG y ACR ==="
az group create -n "$RG" -l "$LOCATION" 1>/dev/null
az acr create -n "$ACR" -g "$RG" --sku Basic 1>/dev/null || true
ACR_LOGIN="$(az acr show -n "$ACR" --query loginServer -o tsv)"
echo "ACR: $ACR_LOGIN"

echo "=== Build & Push ==="
docker build -t "$IMAGE:$TAG" .
docker tag "$IMAGE:$TAG" "$ACR_LOGIN/$IMAGE:$TAG"
az acr login -n "$ACR" 1>/dev/null
docker push "$ACR_LOGIN/$IMAGE:$TAG"

echo "=== Habilitar Container Apps ==="
az extension add --name containerapp --upgrade -y 1>/dev/null || true
az provider register --namespace Microsoft.App 1>/dev/null || true
az provider register --namespace Microsoft.OperationalInsights 1>/dev/null || true

echo "=== Crear entorno ACA ==="
az containerapp env create -g "$RG" -n "$ENV_NAME" -l "$LOCATION" 1>/dev/null || true

ACR_USER="$(az acr credential show -n "$ACR" --query username -o tsv)"
ACR_PASS="$(az acr credential show -n "$ACR" --query passwords[0].value -o tsv)"

echo "=== Crear/Actualizar Container App ==="
if ! az containerapp show -g "$RG" -n "$APP" 1>/dev/null 2>&1; then
  az containerapp create     -g "$RG" -n "$APP"     --environment "$ENV_NAME"     --image "$ACR_LOGIN/$IMAGE:$TAG"     --target-port "$PORT"     --ingress external     --env-vars PORT="$PORT" MODEL_PATH="modelo_breast.pkl"     --registry-server "$ACR_LOGIN"     --registry-username "$ACR_USER"     --registry-password "$ACR_PASS" 1>/dev/null
else
  az containerapp update     -g "$RG" -n "$APP"     --image "$ACR_LOGIN/$IMAGE:$TAG"     --set-env-vars PORT="$PORT" MODEL_PATH="modelo_breast.pkl" 1>/dev/null
fi

FQDN="$(az containerapp show -g "$RG" -n "$APP" --query properties.configuration.ingress.fqdn -o tsv)"
echo "URL pública: https://$FQDN"

echo "=== Probar /health ==="
curl -s "https://$FQDN/health" || true; echo
echo "=== Probar /predict (recuerda enviar 30 features reales) ==="
curl -s -X POST "https://$FQDN/predict" -H "Content-Type: application/json" -d '{"features":[0]*30}' || true; echo

echo "Listo."

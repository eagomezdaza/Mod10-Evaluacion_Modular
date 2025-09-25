# ============================================================================
# DEPLOY_AZURE.md — Despliegue en Azure Container Apps
# Autor: John Gómez
# Fecha: 2025-09-25
# Descripción:
#   Despliega la API Flask (Breast Cancer) contenarizada en Azure Container Apps.
#   Imagen Docker basada en python:3.11-slim, expone puerto 5000 y carga
#   el modelo desde /app/src/model/modelo_breast.pkl.
# ============================================================================

**Descripción:**  
Guía para desplegar la API Flask (Breast Cancer) contenarizada en **Azure Container Apps**.  
La imagen Docker está basada en `python:3.11-slim`, expone el puerto **5000** y carga el modelo desde `/app/src/model/modelo_breast.pkl`.  

---

## 1️⃣ Prerrequisitos
- **Azure CLI** instalado y autenticado:
  ```bash
  az login
  ```
- **Docker** en funcionamiento.  
- Proyecto con estructura estándar:
  ```
  EVALUACION_MODULAR/
  ├─ src/ (app.py, train_breast_cancer.py, model/modelo_breast.pkl)
  ├─ docker/Dockerfile
  ├─ Makefile
  ├─ scripts/deploy_azure.sh
  └─ docs/DEPLOY_AZURE.md
  ```

---

## 2️⃣ Build y test local (recomendado)
Entrena el modelo y valida la API localmente antes de desplegar:
```bash
make train
make run
curl -s http://127.0.0.1:5000/health | jq .
python tests/test_predict.py
```

---

## 3️⃣ Docker local
Construcción y prueba del contenedor:
```bash
make docker-build
make docker-run
curl -s http://127.0.0.1:5000/health | jq .
python tests/test_predict.py --base-url http://127.0.0.1:5000
```

📌 **Notas:**
- El `Dockerfile` ya define las variables:
  - `PORT=5000`
  - `MODEL_PATH=/app/src/model/modelo_breast.pkl`
- No es necesario pasar variables extra en `docker run`.

---

## 4️⃣ Publicar imagen en Azure Container Registry (ACR)
Ejemplo de variables (ajusta con tus nombres):
- Resource Group: `rg-evalmod`
- ACR name: `acrevalmod123` (debe ser único en Azure)

```bash
make push RG=rg-evalmod ACR=acrevalmod123
```

Este comando:
1. Resuelve el `loginServer` del ACR.  
2. Ejecuta `docker tag` + `az acr login` + `docker push`.  

---

## 5️⃣ Actualizar Azure Container Apps

### Si ya tienes creada la Container App:
```bash
make update-aca RG=rg-evalmod ACR=acrevalmod123 APP_NAME=em-api
```

### Si aún **no** existe:
```bash
chmod +x scripts/deploy_azure.sh
./scripts/deploy_azure.sh rg-evalmod acrevalmod123 em-api v1
```

El script:
- Crea el Resource Group (si no existe).  
- Crea el ACR (si no existe).  
- Crea el **Container Apps Environment**.  
- Despliega la **Container App** pública en el puerto **5000**.  
- Configura variables por defecto:
  - `PORT=5000`  
  - `MODEL_PATH=/app/src/model/modelo_breast.pkl`  
- Imprime la **URL pública** y prueba el endpoint `/health`.  

---

## 6️⃣ Verificación post-despliegue
```bash
API_URL="https://<tu-app>.<region>.azurecontainerapps.io"
curl -s "$API_URL/health" | jq .
curl -s -X POST "$API_URL/predict"   -H "Content-Type: application/json"   -d @tests/data/sample.json | jq .
```

---

## 7️⃣ Monitoreo
- Logs en vivo:
  ```bash
  az containerapp logs show -n em-api -g rg-evalmod --follow
  ```
- Métricas Prometheus disponibles en `/metrics`.  
- Integración opcional con **Azure Monitor** y **Application Insights**.  

---

## 8️⃣ Troubleshooting
- `model_loaded: false` → Ejecuta `make train` y `make docker-build` antes del push.  
- **Error 404 en la URL pública** → Revisa que `ingress` esté habilitado y el puerto esté en **5000**.  
- **Timeout en `/predict`** → Verifica que el payload tenga exactamente **30 floats** y revisa los logs (`az containerapp logs show`).  
- **Error de permisos al hacer pull de la imagen** → Asegúrate de habilitar `--admin-enabled true` en el ACR o asignar el rol `AcrPull` a la Container App.  

---

## 9️⃣ Conclusión  
Este documento detalla el proceso completo para entrenar, contenerizar y desplegar la API de predicción de cáncer de mama en **Azure Container Apps**, incluyendo los pasos de verificación posteriores al despliegue, así como lineamientos para monitoreo y resolución de incidencias.  


# ============================================================================
# README.md — Proyecto Evaluación Modular (API ML Breast Cancer)
# Autor: John Gómez
# Fecha: 2025-09-25
# Descripción:
#   API REST en Flask que expone un modelo de clasificación de cáncer de mama
#   (dataset Breast Cancer Wisconsin). Incluye entrenamiento, pruebas,
#   contenedor Docker y despliegue en Azure Container Apps.
# ============================================================================

## 🚀 Introducción
Este proyecto implementa una **API de Machine Learning** para predecir cáncer de mama utilizando el dataset **Breast Cancer Wisconsin**.  
El flujo cubre todo el ciclo: **entrenamiento → pruebas → contenedor Docker → despliegue en Azure Container Apps**, con evidencias documentadas en la carpeta `docs/`.  

---

## 📌 Características principales
- Entrenamiento reproducible con **scikit-learn**.  
- API REST con **Flask**, validación con **Pydantic**.  
- **Logs estructurados en JSON** con `request_id`.  
- Métricas en `/metrics` compatibles con **Prometheus**.  
- Pruebas automáticas con `pytest` y datos de ejemplo.  
- Dockerfile optimizado para despliegue en producción.  
- Scripts (`Makefile`, `deploy_azure.sh`) que automatizan tareas clave.  
- Documentación y capturas del despliegue en Azure (`docs/`).  

---

## ⚙️ Requisitos previos
- **Python 3.11+**  
- **Docker**  
- **Azure CLI**  
- Cuenta activa en **Azure** con permisos sobre Resource Groups y Container Apps  

Instalación de dependencias:
```bash
pip install -r requirements.txt
```

---

## 🧑‍💻 Uso local

### 1. Entrenar modelo
```bash
make train
```

### 2. Levantar API
```bash
make run
```
API accesible en `http://127.0.0.1:5000`

### 3. Endpoints disponibles
- `/health` → estado del modelo y metadatos.  
- `/predict` → recibe un JSON con 30 features y devuelve predicción.  
- `/metrics` → métricas Prometheus.  

Ejemplo de predicción:
```bash
curl -X POST http://127.0.0.1:5000/predict   -H "Content-Type: application/json"   -d @tests/data/sample.json
```

---

## 🧪 Pruebas
Ejecución de pruebas unitarias:
```bash
pytest tests/
```
Valida respuestas correctas del endpoint `/predict` usando los JSON de `tests/data/`.  

---

## 🐳 Docker

Construir imagen:
```bash
make build
```

Correr contenedor:
```bash
make run-docker
```

Probar API en `http://127.0.0.1:5000`.  

---

## ☁️ Despliegue en Azure
1. Crear y configurar **Azure Container Registry (ACR)**.  
2. Hacer push de la imagen:  
   ```bash
   make push RG=rg-evalmod ACR=acrevalmod
   ```
3. Crear o actualizar la **Azure Container App**:  
   ```bash
   make update-aca RG=rg-evalmod ACR=acrevalmod
   ```
4. Verificar URL pública (`.azurecontainerapps.io`) en el portal de Azure.  

👉 Guía detallada en [`docs/DEPLOY_AZURE.md`](docs/DEPLOY_AZURE.md).  

---

## 📊 Monitoreo y logs
- Logs en formato JSON accesibles vía CLI:  
  ```bash
  az containerapp logs show -g rg-evalmod -n evalmod-api --follow
  ```
- Integración con **Log Analytics Workspace** en Azure.  
- Métricas de rendimiento disponibles en `/metrics`.  

---

## 📂 Estructura del proyecto
```
EVALUACION_MODULAR/
├── src/                # Código fuente (API + entrenamiento + utils)
├── tests/              # Pruebas automáticas y datos de ejemplo
├── docker/             # Dockerfile
├── docs/               # Documentación y capturas
├── scripts/            # Scripts de despliegue
├── ci/                 # Configuración CI/CD
├── requirements.txt
├── Makefile
└── venv/               # Entorno virtual local
```

---

## ✅ Estado del proyecto
- [x] Modelo entrenado y serializado (`modelo_breast.pkl`)  
- [x] API Flask funcional  
- [x] Imagen Docker publicada en ACR  
- [x] Despliegue en Azure Container Apps  
- [x] Evidencias en `docs/capturas`  
- [ ] CI/CD (en progreso, carpeta `ci/`)  

---
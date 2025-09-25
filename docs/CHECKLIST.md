# ============================================================================
# CHECKLIST.md — Evidencias Evaluación Modular (Versión Pública)
# Autor: John Gómez
# Fecha: 2025-09-25
# Descripción:
#   Lista de verificación de evidencias requeridas para la entrega final.
#   *Nota:* La URL pública de Azure se deja como placeholder para publicación.
# ============================================================================

- [x] **Entrenamiento local** — salida con `test_accuracy` ≈ 0.95 y archivo `src/model/modelo_breast.pkl`.
- [x] **Pruebas locales** — `curl http://127.0.0.1:5000/health` OK; `POST /predict` OK.
- [x] **Imagen Docker** — `make docker-build` y `make docker-run` OK.
- [x] **Despliegue Azure** — URL pública: https://<app-name>.<region>.azurecontainerapps.io
- [x] **Pruebas en la nube** — `curl https://<app-name>.<region>.azurecontainerapps.io/health` y `POST /predict` OK.
- [x] **Logs** — captura de `az containerapp logs show -g rg-evalmod -n em-api --follow`.
- [x] **Documentación** — README de entrega con pasos y comandos.
- [x] **ZIP final** — código + README + capturas.

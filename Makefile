# ============================================================================
# Makefile — Proyecto Evaluación Modular (API ML + Docker + Azure)
# Autor: John Gómez
# Descripción:
#   Tareas para entrenar, ejecutar local, probar, construir imagen Docker,
#   publicar en Azure Container Registry y actualizar Azure Container Apps.
# Uso rápido:
#   make train            # genera src/model/modelo_breast.pkl
#   make run              # levanta la API local (Gunicorn) en :5000
#   make predict FILE=tests/data/sample.json
#   make docker-build     # docker build (imagen: em-api:v1)
#   make docker-run       # docker run -p 5000:5000 em-api:v1
#   make package          # crea entrega_paquete.zip
#   make help             # muestra ayuda
# ============================================================================

# -------- Variables principales --------
APP_NAME ?= em-api
TAG      ?= v1
IMAGE    ?= $(APP_NAME):$(TAG)

# Puertos
PORT           ?= 5000
CONTAINER_PORT ?= 5000
# Normaliza (evita espacios invisibles en -p 5000:5000)
override PORT := $(strip $(PORT))
override CONTAINER_PORT := $(strip $(CONTAINER_PORT))

# Rutas del modelo
MODEL_PATH_LOCAL  ?= src/model/modelo_breast.pkl
MODEL_PATH_DOCKER ?= /app/src/model/modelo_breast.pkl

# WSGI (factory pattern)
APP_MODULE ?= src.app:create_app()

# Python
PYTHON ?= python
PIP    ?= pip

# Sample por defecto
SAMPLE_JSON ?= tests/data/sample.json

# -------- Utilidad para títulos en consola --------
define bold
	@tput bold 2>/dev/null || true; printf "%s\n" $(1); tput sgr0 2>/dev/null || true
endef

.PHONY: help setup freeze train run health predict test lint fmt \
        docker-build docker-run docker-stop docker-logs \
        docker-export docker-import \
        push update-aca scale-warm package clean

help:
	$(call bold,"Comandos disponibles:")
	@echo "  make setup           # crear venv e instalar dependencias"
	@echo "  make freeze          # fijar versiones en requirements.txt"
	@echo "  make train           # entrenar y guardar modelo ($(MODEL_PATH_LOCAL))"
	@echo "  make run             # levantar API con Gunicorn (puerto $(PORT))"
	@echo "  make health          # curl GET /health"
	@echo "  make predict FILE=$(SAMPLE_JSON)  # POST /predict"
	@echo "  make test            # tests (mínimo)"
	@echo "  make docker-build    # construir imagen ($(IMAGE))"
	@echo "  make docker-run      # ejecutar contenedor (mapea $(PORT):$(CONTAINER_PORT))"
	@echo "  make docker-export   # exportar imagen a .tar (para compartir)"
	@echo "  make docker-import FILE=em-api_v1.tar  # importar imagen desde .tar"
	@echo "  make package         # zip con src, docker, docs, etc."
	@echo "  make clean           # limpiar artefactos locales"

# -------- Entorno local --------
setup:
	$(PYTHON) -m venv .venv && . .venv/bin/activate && $(PIP) install -r requirements.txt

freeze:
	$(PIP) freeze > requirements.txt

train:
	PYTHONPATH=src $(PYTHON) src/train_breast_cancer.py

run:
	# Gunicorn con 2 workers (factory pattern).
	gunicorn -w 2 -b 0.0.0.0:$(PORT) "$(APP_MODULE)"

health:
	@curl -s http://127.0.0.1:$(PORT)/health | jq . || curl -s http://127.0.0.1:$(PORT)/health

predict:
	@test -n "$(FILE)" || (echo "Usa: make predict FILE=$(SAMPLE_JSON)"; exit 1)
	@curl -s -X POST http://127.0.0.1:$(PORT)/predict \
	  -H "Content-Type: application/json" \
	  -d @$(FILE) | jq . || true

test:
	# Test mínimo: verifica que exista el sample principal
	@python - <<'PY'
	from pathlib import Path
	p=Path("$(SAMPLE_JSON)")
	assert p.exists(), f"No existe {p}"
	print("OK: existe", p)
	PY

lint:
	@echo "(Opcional) Agrega ruff/flake8 y black si quieres lint/format automático"

fmt:
	@echo "(Opcional) Ejecuta black/isort aquí"

# -------- Docker --------
docker-build:
	docker build -t $(IMAGE) -f docker/Dockerfile .

docker-run: docker-stop
	docker run --rm --name $(APP_NAME) \
	  -p $(PORT):$(CONTAINER_PORT) \
	  -e PORT=$(CONTAINER_PORT) \
	  -e MODEL_PATH=$(MODEL_PATH_DOCKER) \
	  $(IMAGE)

docker-stop:
	-@docker stop $(APP_NAME) >/dev/null 2>&1 || true

docker-logs:
	@docker logs -n 100 -f $(APP_NAME)

docker-export:
	docker save -o $(APP_NAME)_$(TAG).tar $(IMAGE)
	@echo "Imagen exportada en: $(APP_NAME)_$(TAG).tar"
	@echo "Para cargarla en otra máquina:"
	@echo "  docker load -i $(APP_NAME)_$(TAG).tar"
	@echo "  docker run --rm -p 5000:5000 $(IMAGE)"

docker-import:
	@test -n "$(FILE)" || (echo "Usa: make docker-import FILE=$(APP_NAME)_$(TAG).tar"; exit 1)
	docker load -i $(FILE)
	@echo "Imagen cargada. Ejecuta:"
	@echo "  docker run --rm -p 5000:5000 $(IMAGE)"

# -------- Azure --------
RG ?=
ACR ?=
ACR_LOGIN := $(shell az acr show -n $(ACR) -g $(RG) --query loginServer -o tsv 2>/dev/null)

push:
	@test -n "$(RG)" -a -n "$(ACR)" || (echo "Falta RG o ACR. Ej: make push RG=rg-evalmod ACR=acrevalmod123"; exit 1)
	@test -n "$(ACR_LOGIN)" || (echo "No se pudo resolver ACR_LOGIN. Revisa RG/ACR."; exit 1)
	docker tag $(IMAGE) $(ACR_LOGIN)/$(APP_NAME):$(TAG)
	az acr login -n $(ACR)
	docker push $(ACR_LOGIN)/$(APP_NAME):$(TAG)

update-aca:
	@test -n "$(RG)" || (echo "Falta RG. Ej: make update-aca RG=rg-evalmod ACR=acrevalmod123"; exit 1)
	@test -n "$(ACR_LOGIN)" || (echo "Define ACR y RG si vas a cambiar imagen desde ACR."; exit 1)
	az containerapp update -g $(RG) -n $(APP_NAME) \
	  --image $(ACR_LOGIN)/$(APP_NAME):$(TAG)

scale-warm:
	@test -n "$(RG)" || (echo "Falta RG. Ej: make scale-warm RG=rg-evalmod"; exit 1)
	az containerapp update -g $(RG) -n $(APP_NAME) --min-replicas 1 --max-replicas 2

# -------- Empaquetado de entrega --------
package:
	zip -r entrega_paquete.zip \
	  src docker docs tests requirements.txt Makefile .dockerignore .gitignore

clean:
	rm -rf __pycache__ **/__pycache__ *.pyc *.pyo entrega_paquete_zip *.tar




IMAGE_NAME := flox/farm-health-api
IMAGE_TAG := 0.1.0
CONTAINER_NAME := farm-health-api
KIND_CLUSTER := flox-farm

.PHONY: help setup teardown build run stop test health clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

setup: ## Build, create Kind cluster, deploy, verify
	@echo "Building Docker image..."
	@docker build -t $(IMAGE_NAME):$(IMAGE_TAG) -t $(IMAGE_NAME):latest . -q
	@echo "Creating Kind cluster..."
	@kind get clusters 2>/dev/null | grep -q $(KIND_CLUSTER) || \
		kind create cluster --config kind-config.yaml 2>&1 | tail -1
	@echo "Loading image into Kind..."
	@kind load docker-image $(IMAGE_NAME):$(IMAGE_TAG) --name $(KIND_CLUSTER) 2>&1 | tail -1
	@echo "Deploying to Kubernetes..."
	@kubectl apply -f k8s/namespace.yaml
	@sleep 2
	@kubectl apply -f k8s/configmap.yaml -f k8s/deployment.yaml -f k8s/service.yaml -f k8s/hpa.yaml
	@echo "Waiting for pods..."
	@kubectl wait --for=condition=ready pod -l app=farm-health-api \
		-n flox-farm --timeout=90s 2>/dev/null || \
		echo "Pods still starting - run: kubectl get pods -n flox-farm"
	@echo ""
	@echo "Done. API available at http://localhost:8080"

teardown: ## Delete Kind cluster
	@kind delete cluster --name $(KIND_CLUSTER) 2>/dev/null || true

build: ## Build Docker image
	docker build -t $(IMAGE_NAME):$(IMAGE_TAG) -t $(IMAGE_NAME):latest .

run: build ## Run container locally on port 8000
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	docker run -d -p 8000:8000 --name $(CONTAINER_NAME) $(IMAGE_NAME):$(IMAGE_TAG)
	@echo "Running at http://localhost:8000"

stop: ## Stop local container
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true

test: build ## Smoke test against a temporary container
	@docker rm -f $(CONTAINER_NAME)-test 2>/dev/null || true
	@docker run -d -p 8888:8000 --name $(CONTAINER_NAME)-test $(IMAGE_NAME):$(IMAGE_TAG)
	@sleep 3
	@RESPONSE=$$(curl -sf http://localhost:8888/health 2>&1); \
	if echo "$$RESPONSE" | grep -q '"status":"healthy"'; then \
		echo "PASS - /health"; \
	else \
		echo "FAIL - /health"; docker rm -f $(CONTAINER_NAME)-test; exit 1; \
	fi
	@RESPONSE=$$(curl -sf http://localhost:8888/ready 2>&1); \
	if echo "$$RESPONSE" | grep -q '"ready":true'; then \
		echo "PASS - /ready"; \
	else \
		echo "FAIL - /ready"; docker rm -f $(CONTAINER_NAME)-test; exit 1; \
	fi
	@docker rm -f $(CONTAINER_NAME)-test 2>/dev/null

health: ## Run health check against deployed service
	@if curl -sf http://localhost:8080/health >/dev/null 2>&1; then \
		./healthcheck.sh http://localhost:8080; \
	elif curl -sf http://localhost:8000/health >/dev/null 2>&1; then \
		./healthcheck.sh http://localhost:8000; \
	else \
		echo "No service running. Run 'make setup' or 'make run' first."; exit 1; \
	fi

clean: ## Remove Docker images
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true
	@docker rmi $(IMAGE_NAME):$(IMAGE_TAG) $(IMAGE_NAME):latest 2>/dev/null || true
	
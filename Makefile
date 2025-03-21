# =============================================================================
# Advanced Makefile for Watsonx Code Assistant
# Supports automatic building, testing, repair, and deployment
# =============================================================================

# Configuration
SHELL := /bin/bash
.SHELLFLAGS := -ec
.ONESHELL:

# Detect operating system
ifeq ($(OS),Windows_NT)
    DETECTED_OS := Windows
    RM := del /Q /F
    RMDIR := rmdir /Q /S
    MKDIR := mkdir
    SEP := \\
else
    DETECTED_OS := $(shell uname -s)
    RM := rm -f
    RMDIR := rm -rf
    MKDIR := mkdir -p
    SEP := /
endif

# Directories
BUILD_DIR := build
DIST_DIR := dist
CMAKE_BUILD_DIR := $(BUILD_DIR)/cmake
VENV_DIR := venv
LOG_DIR := logs
COVERAGE_DIR := coverage
SCRIPT_DIR := scripts

# Environment detection
PYTHON := python3
PIP := $(PYTHON) -m pip
CMAKE := cmake
GIT := git
DOCKER := docker
DOCKER_COMPOSE := docker-compose
NUM_CORES := $(shell nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)

# CMake and Ninja configuration
CMAKE_GENERATOR := Ninja
CMAKE_CONFIG := Release
CMAKE_OPTIONS := -DCMAKE_BUILD_TYPE=$(CMAKE_CONFIG) \
                -DBUILD_SHARED_LIBS=OFF \
                -DENABLE_TESTING=ON \
                -DCODE_COVERAGE=OFF

# Docker configuration
DOCKER_TAG := latest
REGISTRY := ghcr.io/ibm
IMAGE_NAME := watsonx-code-assistant

# Colors and formatting
BLUE := \033[34m
GREEN := \033[32m
RED := \033[31m
YELLOW := \033[33m
BOLD := \033[1m
RESET := \033[0m

# ==============================================================================
# Main targets
# ==============================================================================

.PHONY: all clean test lint fix debug docker deploy package docs help

# Default target
all: build

# Show help information
help:
	@echo -e "$(BLUE)$(BOLD)Watsonx Code Assistant Build System$(RESET)"
	@echo -e "$(BLUE)=======================================$(RESET)"
	@echo -e "$(BOLD)Usage:$(RESET)"
	@echo "  make [target]"
	@echo ""
	@echo -e "$(BOLD)Main Targets:$(RESET)"
	@echo "  all           - Build everything (default)"
	@echo "  clean         - Remove all build artifacts"
	@echo "  test          - Run all tests"
	@echo "  lint          - Run code linting"
	@echo "  fix           - Auto-fix code issues"
	@echo "  debug         - Build with debug symbols"
	@echo ""
	@echo -e "$(BOLD)Build Targets:$(RESET)"
	@echo "  build         - Build the project"
	@echo "  rebuild       - Clean and rebuild"
	@echo "  package       - Create distributable packages"
	@echo ""
	@echo -e "$(BOLD)Docker Targets:$(RESET)"
	@echo "  docker-build  - Build Docker image"
	@echo "  docker-run    - Run Docker container"
	@echo "  docker-push   - Push to registry"
	@echo ""
	@echo -e "$(BOLD)Deployment Targets:$(RESET)"
	@echo "  deploy        - Deploy to production"
	@echo "  deploy-dev    - Deploy to development"
	@echo "  deploy-swarm  - Deploy to Docker Swarm"
	@echo "  deploy-k8s    - Deploy to Kubernetes"
	@echo ""
	@echo -e "$(BOLD)Advanced Targets:$(RESET)"
	@echo "  scan          - Scan code for issues"
	@echo "  repair        - Repair code issues"
	@echo "  docs          - Generate documentation"
	@echo "  ci            - Run CI checks"
	@echo "  check-env     - Validate environment"

# ==============================================================================
# Setup targets
# ==============================================================================

# Ensure build directory exists
$(BUILD_DIR):
	@echo -e "$(BLUE)Creating build directory...$(RESET)"
	@$(MKDIR) $(BUILD_DIR)

# Ensure dist directory exists
$(DIST_DIR):
	@echo -e "$(BLUE)Creating dist directory...$(RESET)"
	@$(MKDIR) $(DIST_DIR)

# Ensure log directory exists
$(LOG_DIR):
	@echo -e "$(BLUE)Creating log directory...$(RESET)"
	@$(MKDIR) $(LOG_DIR)

# Virtual environment setup
$(VENV_DIR):
	@echo -e "$(BLUE)Creating virtual environment...$(RESET)"
	@$(PYTHON) -m venv $(VENV_DIR)
	@. $(VENV_DIR)/bin/activate && \
	$(PIP) install --upgrade pip && \
	$(PIP) install -r requirements.txt
	@echo -e "$(GREEN)Virtual environment created$(RESET)"

# Initialize CMake build system
$(CMAKE_BUILD_DIR): $(BUILD_DIR)
	@echo -e "$(BLUE)Initializing CMake build system...$(RESET)"
	@$(MKDIR) $(CMAKE_BUILD_DIR)
	@cd $(CMAKE_BUILD_DIR) && $(CMAKE) -G $(CMAKE_GENERATOR) $(CMAKE_OPTIONS) ../..
	@echo -e "$(GREEN)CMake build system initialized$(RESET)"

# Check environment
check-env:
	@echo -e "$(BLUE)Checking environment...$(RESET)"
	@echo -e "$(BOLD)Detected OS:$(RESET) $(DETECTED_OS)"
	@echo -e "$(BOLD)Python version:$(RESET) $$($(PYTHON) --version 2>&1)"
	@echo -e "$(BOLD)Pip version:$(RESET) $$($(PIP) --version 2>&1 | cut -d' ' -f1-2)"
	@echo -e "$(BOLD)CMake version:$(RESET) $$($(CMAKE) --version | head -n 1)"
	@echo -e "$(BOLD)Docker version:$(RESET) $$($(DOCKER) --version 2>/dev/null || echo 'Not installed')"
	@echo -e "$(BOLD)Number of CPU cores:$(RESET) $(NUM_CORES)"
	@echo -e "$(BOLD)Git version:$(RESET) $$($(GIT) --version 2>/dev/null || echo 'Not installed')"
	@command -v ninja >/dev/null 2>&1 && echo -e "$(BOLD)Ninja version:$(RESET) $$(ninja --version 2>/dev/null)" || echo -e "$(YELLOW)Ninja not found$(RESET)"
	@docker info >/dev/null 2>&1 && echo -e "$(GREEN)Docker daemon running$(RESET)" || echo -e "$(YELLOW)Docker daemon not running$(RESET)"

# ==============================================================================
# Build targets
# ==============================================================================

# Build the project
build: $(VENV_DIR) $(CMAKE_BUILD_DIR)
	@echo -e "$(BLUE)Building project...$(RESET)"
	@cd $(CMAKE_BUILD_DIR) && $(CMAKE) --build . --config $(CMAKE_CONFIG) -j $(NUM_CORES)
	@echo -e "$(GREEN)Build completed$(RESET)"

# Rebuild the project
rebuild: clean build

# Clean build artifacts
clean:
	@echo -e "$(BLUE)Cleaning build artifacts...$(RESET)"
	@if [ -d "$(BUILD_DIR)" ]; then $(RMDIR) $(BUILD_DIR); fi
	@if [ -d "$(DIST_DIR)" ]; then $(RMDIR) $(DIST_DIR); fi
	@if [ -d "$(COVERAGE_DIR)" ]; then $(RMDIR) $(COVERAGE_DIR); fi
	@find . -type d -name "__pycache__" -exec $(RMDIR) {} +
	@find . -type f -name "*.pyc" -delete
	@find . -type f -name ".coverage" -delete
	@find . -type d -name "*.egg-info" -exec $(RMDIR) {} +
	@echo -e "$(GREEN)Clean completed$(RESET)"

# Package the application
package: build $(DIST_DIR)
	@echo -e "$(BLUE)Creating packages...$(RESET)"
	@cd $(CMAKE_BUILD_DIR) && $(CMAKE) --build . --config $(CMAKE_CONFIG) --target package -j $(NUM_CORES)
	@echo -e "$(GREEN)Packaging completed$(RESET)"

# ==============================================================================
# Test targets
# ==============================================================================

# Run all tests
test: $(VENV_DIR)
	@echo -e "$(BLUE)Running tests...$(RESET)"
	@. $(VENV_DIR)/bin/activate && \
	PYTHONPATH=. pytest tests/ -v
	@echo -e "$(GREEN)Tests completed$(RESET)"

# Run tests with coverage
coverage: $(VENV_DIR)
	@echo -e "$(BLUE)Running tests with coverage...$(RESET)"
	@$(MKDIR) $(COVERAGE_DIR)
	@. $(VENV_DIR)/bin/activate && \
	PYTHONPATH=. pytest tests/ -v --cov=. --cov-report=xml:$(COVERAGE_DIR)/coverage.xml --cov-report=html:$(COVERAGE_DIR)/html
	@echo -e "$(GREEN)Coverage report generated in $(COVERAGE_DIR)$(RESET)"

# ==============================================================================
# Analysis and repair targets
# ==============================================================================

# Lint the code
lint: $(VENV_DIR)
	@echo -e "$(BLUE)Linting code...$(RESET)"
	@. $(VENV_DIR)/bin/activate && \
	flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics && \
	black --check . && \
	isort --check-only --profile black .
	@echo -e "$(GREEN)Linting completed$(RESET)"

# Fix code issues automatically
fix: $(VENV_DIR)
	@echo -e "$(BLUE)Auto-fixing code issues...$(RESET)"
	@. $(VENV_DIR)/bin/activate && \
	black . && \
	isort --profile black .
	@echo -e "$(GREEN)Code formatting fixed$(RESET)"

# Scan code for issues
scan: $(VENV_DIR)
	@echo -e "$(BLUE)Scanning code for issues...$(RESET)"
	@. $(VENV_DIR)/bin/activate && \
	bandit -r . -c .bandit.yaml -ll || true
	@python $(SCRIPT_DIR)/scan-code.py
	@echo -e "$(GREEN)Code scan completed$(RESET)"

# Repair code issues
repair: scan $(VENV_DIR)
	@echo -e "$(BLUE)Repairing code issues...$(RESET)"
	@. $(VENV_DIR)/bin/activate && \
	python $(SCRIPT_DIR)/repair-code.py
	@make fix
	@echo -e "$(GREEN)Code repair completed$(RESET)"

# ==============================================================================
# Debug targets
# ==============================================================================

# Build with debug symbols
debug: CMAKE_CONFIG=Debug
debug: CMAKE_OPTIONS+= -DDEBUG=ON -DCODE_COVERAGE=ON
debug: clean build
	@echo -e "$(GREEN)Debug build completed$(RESET)"

# ==============================================================================
# Documentation targets
# ==============================================================================

# Generate documentation
docs: $(VENV_DIR)
	@echo -e "$(BLUE)Generating documentation...$(RESET)"
	@. $(VENV_DIR)/bin/activate && \
	sphinx-build -b html docs/source docs/build/html
	@echo -e "$(GREEN)Documentation generated$(RESET)"

# ==============================================================================
# Docker targets
# ==============================================================================

# Build Docker image
docker-build:
	@echo -e "$(BLUE)Building Docker image...$(RESET)"
	@$(DOCKER) build -t $(REGISTRY)/$(IMAGE_NAME):$(DOCKER_TAG) .
	@echo -e "$(GREEN)Docker image built$(RESET)"

# Run Docker container
docker-run: docker-build
	@echo -e "$(BLUE)Running Docker container...$(RESET)"
	@$(DOCKER_COMPOSE) up -d
	@echo -e "$(GREEN)Docker container running$(RESET)"

# Push Docker image to registry
docker-push: docker-build
	@echo -e "$(BLUE)Pushing Docker image to registry...$(RESET)"
	@$(DOCKER) push $(REGISTRY)/$(IMAGE_NAME):$(DOCKER_TAG)
	@echo -e "$(GREEN)Docker image pushed$(RESET)"

# ==============================================================================
# Deployment targets
# ==============================================================================

# Deploy to production
deploy:
	@echo -e "$(BLUE)Deploying to production...$(RESET)"
	@./scripts/deployment-controller.sh
	@echo -e "$(GREEN)Deployment process initiated$(RESET)"

# Deploy to development
deploy-dev:
	@echo -e "$(BLUE)Deploying to development...$(RESET)"
	@ENVIRONMENT=development ./scripts/deployment-controller.sh
	@echo -e "$(GREEN)Deployment process initiated$(RESET)"

# Deploy to Docker Swarm
deploy-swarm:
	@echo -e "$(BLUE)Deploying to Docker Swarm...$(RESET)"
	@SWARM_MODE=true ./scripts/deployment-controller.sh
	@echo -e "$(GREEN)Deployment process initiated$(RESET)"

# Deploy to Kubernetes
deploy-k8s:
	@echo -e "$(BLUE)Deploying to Kubernetes...$(RESET)"
	@DEPLOY_TARGET=kubernetes ./scripts/deployment-controller.sh
	@echo -e "$(GREEN)Deployment process initiated$(RESET)"

# ==============================================================================
# CI targets
# ==============================================================================

# Run CI checks
ci: check-env lint test
	@echo -e "$(GREEN)CI checks completed$(RESET)"

# Run full CI pipeline with build
ci-complete: check-env lint test build coverage docker-build
	@echo -e "$(GREEN)Complete CI pipeline finished$(RESET)"

# ==============================================================================
# Ninja Team targets
# ==============================================================================

# Deploy ninja build team
deploy-ninjas:
	@echo -e "$(BLUE)$(BOLD)Deploying ninja build team...$(RESET)"
	@if [ "$(OS)" = "Windows_NT" ]; then \
		cmd.exe /c deploy-ninjas.cmd; \
	else \
		bash ./deploy-ninjas.sh; \
	fi
	@echo -e "$(GREEN)Ninja team deployment completed$(RESET)"

# Deploy full recursive ninja team with advanced features
deploy-ninjas-full:
	@echo -e "$(BLUE)$(BOLD)Deploying full recursive ninja team...$(RESET)"
	@if [ "$(OS)" = "Windows_NT" ]; then \
		echo "Full deployment not supported on Windows. Please use WSL."; \
	else \
		bash ./deploy-ninjas.sh --full; \
	fi
	@echo -e "$(GREEN)Full ninja team deployment completed$(RESET)"

# Clean ninja build cache
ninja-clean:
	@echo -e "$(BLUE)Cleaning ninja build cache...$(RESET)"
	@if [ "$(OS)" = "Windows_NT" ]; then \
		if exist .ninja_cache rmdir /S /Q .ninja_cache; \
	else \
		rm -rf .ninja_cache; \
	fi
	@echo -e "$(GREEN)Ninja cache cleaned$(RESET)"

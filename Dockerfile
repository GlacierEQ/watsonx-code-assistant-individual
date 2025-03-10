# Multi-stage build for optimized production image

# Build stage
FROM nvidia/cuda:11.8.0-devel-ubuntu22.04 AS builder

WORKDIR /build

# Install build dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    build-essential \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create and activate Python environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy requirements and install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir wheel && \
    pip install --no-cache-dir -r requirements.txt

# Install PyTorch with CUDA support
RUN pip install --no-cache-dir torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Final stage
FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

# Set labels for better maintainability
LABEL maintainer="IBM Watsonx Team" \
      description="Watsonx Code Assistant - Enterprise AI coding platform" \
      version="1.0.0"

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-distutils \
    curl \
    wget \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama
RUN curl -fsSL https://ollama.ai/install.sh | sh

# Configure Ollama for better performance
RUN mkdir -p /root/.ollama && \
    echo '{ "gpu_layers": -1, "tensorrt": true, "numa": true, "debug": false }' > /root/.ollama/config.json

# Copy Python virtual environment from builder
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application files
COPY . .

# Create non-root user to run the application
RUN groupadd -g 10001 watsonx && \
    useradd -u 10000 -g watsonx -s /sbin/nologin -c "Watsonx Application User" watsonx && \
    mkdir -p /data/models && \
    chown -R watsonx:watsonx /data

# Create health check script
COPY healthcheck.sh /usr/local/bin/healthcheck.sh
RUN chmod +x /usr/local/bin/healthcheck.sh

# Set up entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Set necessary environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH" \
    PORT=5000 \
    OLLAMA_HOST=localhost \
    OLLAMA_PORT=11434 \
    MODEL_CACHE_DIR=/data/models

# Expose ports
EXPOSE 5000 11434

# Add health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# Switch to non-root user for most operations
USER watsonx

# Define volumes for persistence
VOLUME ["/data/models", "/app/data"]

# Set the entry point
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Multi-stage build for optimized production image

# Build stage
FROM python:3.9-slim-buster AS builder

WORKDIR /app

# Create a Python virtual environment
RUN python -m venv /opt/venv
# Activate the virtual environment
ENV PATH="/opt/venv/bin:$PATH"

# Copy the requirements file into the container at /app
COPY requirements.txt .

# Install any needed packages specified in requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
EXPOSE 80

# Run app.py when the container launches
CMD ["python", "app.py"]

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
    nginx \
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

# Create nginx directory and config file directly
RUN mkdir -p /etc/nginx && echo 'server { \
    listen 80; \
    server_name localhost; \
    location / { \
        proxy_pass http://localhost:5000; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
    } \
    location /api { \
        proxy_pass http://localhost:11434; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
    } \
}' > /etc/nginx/nginx.conf

# Expose ports
EXPOSE 80 443 5000 11434

# Add health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD ["/usr/local/bin/healthcheck.sh"]

# Switch to non-root user for most operations
USER watsonx

# Define volumes for persistence
VOLUME ["/data/models", "/app/data"]

# Start the application and nginx using a single command
CMD /usr/local/bin/docker-entrypoint.sh

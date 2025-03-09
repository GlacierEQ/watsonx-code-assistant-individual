#!/bin/bash
# Docker container health check script
# Verifies that both the UI and Ollama services are running properly

set -e

# Get environment variables or use defaults
PORT=${PORT:-5000}
OLLAMA_HOST=${OLLAMA_HOST:-localhost}
OLLAMA_PORT=${OLLAMA_PORT:-11434}

# Check UI server health
UI_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:${PORT}/api/health || echo "failed")
if [ "$UI_HEALTH" != "200" ]; then
    echo "UI health check failed with status: $UI_HEALTH"
    exit 1
fi

# Check Ollama API health
OLLAMA_HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/version || echo "failed")
if [ "$OLLAMA_HEALTH" != "200" ]; then
    echo "Ollama health check failed with status: $OLLAMA_HEALTH"
    exit 1
fi

# Check for minimum required disk space (10GB)
DISK_SPACE=$(df -BG /data | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "$DISK_SPACE" -lt 10 ]; then
    echo "Warning: Low disk space - $DISK_SPACE GB available"
    # Don't fail on low disk, just warn
fi

# Check for minimum required memory (2GB free)
FREE_MEM=$(free -m | awk '/^Mem:/ {print $4}')
if [ "$FREE_MEM" -lt 2048 ]; then
    echo "Warning: Low memory - $FREE_MEM MB free"
    # Don't fail on low memory, just warn
fi

# All checks passed
echo "Health check passed: UI and Ollama services running correctly"
exit 0

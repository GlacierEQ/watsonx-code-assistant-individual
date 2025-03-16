#!/bin/bash
# Docker entrypoint for Watsonx Code Assistant
# Manages startup sequence and handles signals properly

set -e

# Function to handle SIGTERM and SIGINT for graceful shutdown
handle_shutdown() {
    echo "[$(date -Iseconds)] Received shutdown signal, gracefully stopping services..."
    
    # Stop Flask server if running
    if [ -n "${FLASK_PID}" ]; then
        echo "[$(date -Iseconds)] Stopping Flask server (PID: ${FLASK_PID})..."
        kill -TERM "${FLASK_PID}" 2>/dev/null || true
    fi
    
    # Stop Ollama if running
    if [ -n "${OLLAMA_PID}" ]; then
        echo "[$(date -Iseconds)] Stopping Ollama (PID: ${OLLAMA_PID})..."
        kill -TERM "${OLLAMA_PID}" 2>/dev/null || true
    fi
    
    echo "[$(date -Iseconds)] Shutdown complete"
    exit 0
}

# Set up signal handling
trap handle_shutdown SIGTERM SIGINT

# Set default environment variables if not provided
PORT=${PORT:-5000}
OLLAMA_HOST=${OLLAMA_HOST:-localhost}
OLLAMA_PORT=${OLLAMA_PORT:-11434}

# Print startup information
echo "[$(date -Iseconds)] Starting Watsonx Code Assistant"
echo "[$(date -Iseconds)] ================================"
echo "[$(date -Iseconds)] UI will be available at: http://localhost:${PORT}"
echo "[$(date -Iseconds)] Ollama API will be available at: http://${OLLAMA_HOST}:${OLLAMA_PORT}"
echo "[$(date -Iseconds)] Using model cache directory: ${MODEL_CACHE_DIR}"

# Check for GPU
if command -v nvidia-smi &> /dev/null; then
    echo "[$(date -Iseconds)] NVIDIA GPU detected:"
    nvidia-smi --query-gpu=name,utilization.gpu,memory.total,memory.free --format=csv,noheader
    export CUDA_VISIBLE_DEVICES=0
    export TF_GPU_ALLOCATOR=cuda_malloc_async
    export TF_XLA_FLAGS="--tf_xla_auto_jit=2"
    echo "[$(date -Iseconds)] GPU acceleration enabled"
else
    echo "[$(date -Iseconds)] No NVIDIA GPU detected, running in CPU-only mode"
fi

# Start Ollama in background with proper permissions
echo "[$(date -Iseconds)] Starting Ollama service..."
sudo -u root ollama serve &
OLLAMA_PID=$!

# Wait for Ollama to initialize
echo "[$(date -Iseconds)] Waiting for Ollama to initialize..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s "http://${OLLAMA_HOST}:${OLLAMA_PORT}/api/version" &> /dev/null; then
        echo "[$(date -Iseconds)] Ollama is ready"
        break
    fi
    
    echo "[$(date -Iseconds)] Waiting for Ollama to start (attempt $((attempt+1))/${max_attempts})..."
    sleep 2
    attempt=$((attempt+1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "[$(date -Iseconds)] ERROR: Ollama failed to start within the expected time"
    exit 1
fi

# Run any GPU optimization if needed
if [ -f ./optimize_gpu.py ]; then
    echo "[$(date -Iseconds)] Running GPU optimization..."
    python ./optimize_gpu.py
fi

# Start nginx
echo "Starting nginx..."
nginx -g 'daemon off;' &

# Start the Watsonx application
echo "Starting Watsonx application..."
python app.py

# Start the UI server
echo "[$(date -Iseconds)] Starting Watsonx Code Assistant UI..."
python start_ui_server.py --host 0.0.0.0 --port $PORT &
FLASK_PID=$!

# Wait for all processes to finish
wait $FLASK_PID

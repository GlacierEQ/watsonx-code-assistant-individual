FROM nvidia/cuda:11.8.0-runtime-ubuntu22.04

# Prevent interactive prompts during build
ENV DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    curl \
    wget \
    git \
    nodejs \
    npm \
    libffi-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Install Ollama
RUN curl -fsSL https://ollama.ai/install.sh | sh

# Configure Ollama for better performance
RUN mkdir -p /root/.ollama && \
    echo '{ "gpu_layers": -1, "tensorrt": true, "numa": true, "threads": 4, "debug": false }' > /root/.ollama/config.json

# Create and activate Python environment
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Install PyTorch with CUDA support
RUN pip install --no-cache-dir torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu118

# Install TensorFlow with GPU optimizations
RUN pip install --no-cache-dir tensorflow-gpu

# Install additional dependencies
RUN pip install --no-cache-dir nvidia-ml-py3 psutil py3nvml flask

# Copy application files
COPY . .

# Make scripts executable
RUN chmod +x ./optimize_gpu.py ./launch-watsonx.sh

# Expose ports
EXPOSE 5000 11434

# Set up entrypoint script
RUN echo '#!/bin/bash\n\
# Start Ollama server in the background\n\
ollama serve &\n\
sleep 2\n\
\n\
# Start the UI server\n\
python3 start_ui_server.py\n' > /app/entrypoint.sh && \
    chmod +x /app/entrypoint.sh

# Set the entry point
ENTRYPOINT ["/app/entrypoint.sh"]

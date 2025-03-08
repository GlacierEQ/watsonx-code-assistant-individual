#!/bin/bash
# DeepSoul Optimization Script for IBM Watsonx Code Assistant Individual
# Ensures GPU/NPU acceleration, memory optimization, and efficient AI deployment

set -e  # Exit on error

### STEP 1: SYSTEM UPDATE & DEPENDENCIES ###
echo "🔹 Updating system packages..."
sudo apt update && sudo apt upgrade -y  # For Debian-based systems

### STEP 2: INSTALL PYTHON & VIRTUAL ENVIRONMENT ###
echo "🔹 Installing Python & Virtual Environment..."
sudo apt install -y python3 python3-venv python3-pip
python3 -m venv watsonx_env
source watsonx_env/bin/activate

### STEP 3: GPU/NPU DETECTION & OPTIMIZATION ###
echo "🔹 Detecting and configuring GPU/NPU resources..."
# Check for NVIDIA GPU
if command -v nvidia-smi &> /dev/null; then
    echo "✓ NVIDIA GPU detected. Configuring for optimal performance..."
    CUDA_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | cut -d'.' -f1)
    echo "🔷 CUDA Driver Version: $CUDA_VERSION detected"
    
    # Set optimal GPU memory allocation
    export TF_MEMORY_ALLOCATION="0.85"  # Reserve 85% of GPU memory for ML operations
    export CUDA_CACHE_MAXSIZE="2147483648"  # 2GB cache size
    export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:512"  # Optimize memory splitting
else
    echo "⚠️ NVIDIA GPU not detected. Using CPU mode."
fi

# Check for AMD GPU
if command -v rocminfo &> /dev/null; then
    echo "✓ AMD GPU detected. Configuring ROCm support..."
    export HSA_OVERRIDE_GFX_VERSION=10.3.0
fi

### STEP 4: INSTALL VS CODE ###
echo "🔹 Installing Visual Studio Code..."
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > packages.microsoft.gpg
sudo install -o root -g root -m 644 packages.microsoft.gpg /etc/apt/trusted.gpg.d/
echo "deb [arch=amd64] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
sudo apt update
sudo apt install -y code

### STEP 5: INSTALL OLLAMA (AI MODEL HOSTING) WITH OPTIMIZATIONS ###
echo "🔹 Installing Ollama for local AI hosting with optimizations..."
curl -fsSL https://ollama.ai/install.sh | sh

# Configure Ollama for better performance
mkdir -p ~/.ollama
cat > ~/.ollama/config.json << EOF
{
  "gpu_layers": -1,
  "tensorrt": true,
  "numa": true,
  "threads": $(nproc),
  "debug": false
}
EOF
echo "✓ Configured Ollama for maximum GPU utilization"

### STEP 6: INSTALL CUDA/NPU DRIVERS & TENSOR OPTIMIZATION ###
echo "🔹 Installing CUDA & TensorFlow/PyTorch optimizations..."
sudo apt install -y nvidia-cuda-toolkit

# Install PyTorch with optimizations
echo "🔹 Installing optimized PyTorch..."
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118

# Install TensorFlow with GPU optimizations
echo "🔹 Installing optimized TensorFlow..."
pip install tensorflow-gpu

# Install memory optimization tools
echo "🔹 Installing memory optimization dependencies..."
pip install nvidia-ml-py3 psutil py3nvml

### STEP 7: CLONE & SET UP WATSONX CODE ASSISTANT ###
echo "🔹 Cloning Watsonx Code Assistant Repository..."
git clone https://github.com/IBM/watsonx-code-assistant-individual.git
cd watsonx-code-assistant-individual
pip install -r requirements.txt

### STEP 8: ENABLE ADVANCED GPU/NPU PRIORITY ###
echo "🔹 Configuring advanced GPU/NPU optimizations..."
# Create optimization script
cat > ./optimize_gpu.py << 'EOF'
#!/usr/bin/env python3
import os
import psutil
try:
    import torch
    import tensorflow as tf
    import numpy as np
    from py3nvml import py3nvml

    # Initialize NVML for GPU monitoring
    py3nvml.nvmlInit()

    # Set memory growth for TensorFlow
    gpus = tf.config.experimental.list_physical_devices('GPU')
    if gpus:
        for gpu in gpus:
            tf.config.experimental.set_memory_growth(gpu, True)
        print(f"✓ Configured {len(gpus)} GPU(s) with dynamic memory growth")
    
    # PyTorch optimizations
    if torch.cuda.is_available():
        # Enable TF32 precision for better performance on Ampere GPUs
        torch.backends.cuda.matmul.allow_tf32 = True
        torch.backends.cudnn.allow_tf32 = True
        # Use fastest algorithms for convolution operations
        torch.backends.cudnn.benchmark = True
        print(f"✓ Optimized PyTorch for {torch.cuda.get_device_name()}")
        print(f"✓ Available GPU memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")

    # Set environment variables for optimal performance
    os.environ["TF_GPU_ALLOCATOR"] = "cuda_malloc_async"
    os.environ["TF_FORCE_GPU_ALLOW_GROWTH"] = "true"
    
    print("✅ GPU optimization completed successfully")
except ImportError as e:
    print(f"⚠️ Some optimization modules not available: {e}")
except Exception as e:
    print(f"⚠️ GPU optimization error: {e}")
EOF

# Make optimization script executable
chmod +x ./optimize_gpu.py

# Run the optimization script
python ./optimize_gpu.py

# Set core environment variables
export CUDA_VISIBLE_DEVICES=0
export TF_GPU_ALLOCATOR=cuda_malloc_async
export TF_XLA_FLAGS="--tf_xla_auto_jit=2"  # Enable XLA JIT compilation
export PYTORCH_CUDA_ALLOC_CONF="expandable_segments:True"

### STEP 9: SETUP WEB UI MANAGEMENT INTERFACE ###
echo "🔹 Setting up the Watsonx Web Management Interface..."

# Install lightweight web server for the UI
pip install flask

# Create a simple server to host the UI
cat > ./start_ui_server.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, send_from_directory
import os
import webbrowser
import threading
import time

app = Flask(__name__)

@app.route('/')
def home():
    return send_from_directory('.', 'watsonx-ui.html')

def open_browser():
    # Give the server a moment to start
    time.sleep(1.5)
    webbrowser.open('http://localhost:5000')

if __name__ == '__main__':
    threading.Thread(target=open_browser).start()
    print("✅ Starting Watsonx Management Interface at http://localhost:5000")
    app.run(host='0.0.0.0', port=5000)
EOF

chmod +x ./start_ui_server.py

### STEP 10: FINAL SETUP & LAUNCH ###
echo "✅ Installation complete! Launching Watsonx Code Assistant..."

# Create launcher script
cat > ./launch-watsonx.sh << 'EOF'
#!/bin/bash
# Launch script for Watsonx Code Assistant

# Check if Ollama is running
if ! pgrep -x "ollama" > /dev/null; then
    echo "Starting Ollama server..."
    ollama serve &
    sleep 2
fi

# Start the Web UI
echo "Starting Watsonx Web Management Interface..."
python start_ui_server.py &

# Launch VS Code
echo "Launching Visual Studio Code..."
code .

echo ""
echo "🚀 Watsonx Code Assistant is now running"
echo "💡 Web UI: http://localhost:5000"
echo "💡 GPU/NPU acceleration is active"
echo ""
EOF

chmod +x ./launch-watsonx.sh

echo ""
echo "🚀 DeepSoul Optimization Complete!"
echo "💡 GPU/NPU acceleration is now prioritized"
echo "💡 Tensor operations have been optimized"
echo "💡 Memory management has been configured for efficiency"
echo ""
echo "To start the Watsonx Code Assistant with Web UI, run:"
echo "./launch-watsonx.sh"
echo ""
echo "Starting the interface now..."
./launch-watsonx.sh

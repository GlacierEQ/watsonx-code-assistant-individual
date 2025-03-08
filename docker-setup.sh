#!/bin/bash
# Docker Setup Script for Watsonx Code Assistant
# Simplifies Docker installation and container management

set -e  # Exit on error

echo "==================================================================="
echo "🐳 Watsonx Code Assistant - Docker Setup"
echo "==================================================================="

# Check Docker installation
if ! command -v docker &> /dev/null; then
    echo "❌ Docker not found. Please install Docker first."
    echo "   Visit https://docs.docker.com/get-docker/ for installation instructions."
    exit 1
fi

# Check Docker Compose installation
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose not found. Please install Docker Compose first."
    echo "   Visit https://docs.docker.com/compose/install/ for installation instructions."
    exit 1
fi

# Check for NVIDIA Container Toolkit if GPU exists
if command -v nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA GPU detected."
    if ! command -v nvidia-container-cli &> /dev/null; then
        echo "⚠️  NVIDIA Container Toolkit not detected."
        echo "   For GPU acceleration, please install NVIDIA Container Toolkit:"
        echo "   https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
        
        read -p "Continue without NVIDIA Container Toolkit? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        echo "✅ NVIDIA Container Toolkit detected. GPU acceleration will be available."
    fi
else
    echo "⚠️  NVIDIA GPU not detected. Application will run in CPU-only mode."
fi

# Create data directory if it doesn't exist
mkdir -p data

# Generate requirements file if it doesn't exist
if [ ! -f requirements.txt ]; then
    echo "📝 Creating requirements.txt..."
    cat > requirements.txt << EOF
flask==2.2.3
torch==2.0.0
numpy==1.24.2
psutil==5.9.4
py3nvml==0.2.7
tensorflow==2.12.0
EOF
fi

# Ensure optimize_gpu.py exists
if [ ! -f optimize_gpu.py ]; then
    echo "📝 Creating GPU optimization script..."
    # Copy the optimization script from install.sh
    if [ -f install.sh ]; then
        # Extract the optimize_gpu.py content from install.sh
        sed -n '/cat > .\/optimize_gpu.py << .EOF./,/EOF/p' install.sh | sed '1d;$d' > optimize_gpu.py
        chmod +x optimize_gpu.py
    else
        # Create a basic version if install.sh is not available
        cat > optimize_gpu.py << 'EOF'
#!/usr/bin/env python3
import os
import sys
print("GPU optimization script")
try:
    import torch
    if torch.cuda.is_available():
        print(f"GPU available: {torch.cuda.get_device_name(0)}")
        print(f"Available GPU memory: {torch.cuda.get_device_properties(0).total_memory / 1e9:.2f} GB")
    else:
        print("No GPU detected by PyTorch")
except ImportError:
    print("PyTorch not installed")
EOF
        chmod +x optimize_gpu.py
    fi
fi

# Check if start_ui_server.py exists
if [ ! -f start_ui_server.py ]; then
    echo "📝 Creating UI server script..."
    # Copy from install.sh or create a basic version
    if [ -f install.sh ]; then
        sed -n '/cat > .\/start_ui_server.py << .EOF./,/EOF/p' install.sh | sed '1d;$d' > start_ui_server.py
        chmod +x start_ui_server.py
    else
        # Create a basic version
        cat > start_ui_server.py << 'EOF'
#!/usr/bin/env python3
from flask import Flask, send_from_directory
import os

app = Flask(__name__)

@app.route('/')
def home():
    return send_from_directory('.', 'index.html')

if __name__ == '__main__':
    print("✅ Starting Watsonx Management Interface at http://0.0.0.0:5000")
    app.run(host='0.0.0.0', port=5000)
EOF
        chmod +x start_ui_server.py
    fi
fi

# Stop any existing containers
echo "🛑 Stopping any existing containers..."
docker-compose down 2>/dev/null || true

# Build and start the containers
echo "🔨 Building Docker image (this may take several minutes)..."
docker-compose build

echo "🚀 Starting Watsonx Code Assistant..."
docker-compose up -d

echo ""
echo "==================================================================="
echo "✅ Watsonx Code Assistant is now running!"
echo "   Access the UI at: http://localhost:5000"
echo "   Ollama API available at: http://localhost:11434"
echo ""
echo "📋 Useful commands:"
echo "   - View logs: docker-compose logs -f"
echo "   - Stop service: docker-compose down"
echo "   - Restart service: docker-compose restart"
echo "==================================================================="

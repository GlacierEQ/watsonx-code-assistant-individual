# 🧠 IBM Watsonx Code Assistant

Enterprise-grade AI coding assistant powered by IBM Granite models.

## 📋 Features

- 🤖 **Local AI Models**: Run powerful Granite coding models locally on your own machine
- 🔧 **VSCode Integration**: Seamless IDE integration with code generation and review
- 🔁 **Real-time Collaboration**: Work together with team members using collaborative features
- 📊 **Code Analytics**: Quality metrics, vulnerability scanning, and improvement suggestions
- 🎯 **Prompt Engineering**: Build custom prompts for specialized coding tasks
- 🌐 **Multilingual**: Full interface localization in multiple languages
- 📱 **Progressive Web App**: Install as a standalone app on any OS

## 🚀 Quick Start

### Using Docker (Recommended)

Before you begin, ensure you have the following installed:

- [Docker](https://www.docker.com/get-started)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

```bash
# Clone the repository
git clone https://github.com/IBM/watsonx-code-assistant-individual.git
cd watsonx-code-assistant-individual

# Check Docker version
docker --version

# Check Docker Compose version
docker compose version

# Run the Docker setup script
bash docker-setup.sh
```

If you encounter any issues during the Docker setup, please refer to the [Troubleshooting Guide](docs/TROUBLESHOOTING.md).

Once running, open http://localhost:5000 in your browser.

### Manual Installation

Before you begin, ensure you have the following installed:

- [Python 3.x](https://www.python.org/downloads/)
- [pip](https://pip.pypa.io/en/stable/installing/)
- [Node.js](https://nodejs.org/en/download/)
- [npm](https://www.npmjs.com/get-npm)
- [Git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

```bash
# Clone the repository
git clone https://github.com/IBM/watsonx-code-assistant-individual.git
cd watsonx-code-assistant-individual

# Check Python version
python --version

# Check Node.js version
node --version

# Check npm version
npm --version

# Run the automated setup
bash install.sh
```

If you encounter any issues during the manual installation, please refer to the [Troubleshooting Guide](docs/TROUBLESHOOTING.md).

## 🖥️ System Requirements

- **CPU**: 4+ cores recommended
- **RAM**: 8GB minimum, 16GB+ recommended
- **GPU**: NVIDIA GPU with 4GB+ VRAM recommended for optimal performance
- **Disk**: 10GB+ free space
- **OS**: Windows 10/11, macOS 10.15+, Ubuntu 20.04+

## 🔄 Docker Container Structure

The application uses a multi-container architecture:
- **watsonx**: Main container with the UI and Ollama
- **nginx**: Production proxy with SSL support

## 🛡️ Security Features

- Content Security Policy implementation
- HTTPS with TLS 1.3 support
- Docker security best practices (least privilege, read-only container)
- Authentication and authorization system
- Role-based access control

## 🌐 Enterprise Deployment

For enterprise deployment, we support:
- Kubernetes deployment with autoscaling
- Multi-architecture support (amd64, arm64)
- CI/CD integration
- Monitoring and alerting
- High availability configuration

## 📚 Documentation

- [Developer Guide](docs/DEVELOPER.md)
- [API Documentation](docs/API.md)
- [Deployment Guide](docs/DEPLOYMENT.md)

## 📄 License

This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details.


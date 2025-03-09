#!/bin/bash
# Production Deployment Script for Watsonx Code Assistant
# This script automates the deployment of the application to production environments

set -eo pipefail

# Color formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "${BLUE}${BOLD}     IBM Watsonx Code Assistant - Production Deployment           ${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"

# Configuration variables - these can be overridden with environment variables
REGISTRY=${REGISTRY:-"ghcr.io/ibm"}
IMAGE_NAME=${IMAGE_NAME:-"watsonx-code-assistant"}
VERSION=${VERSION:-$(git describe --tags --always || echo "latest")}
DEPLOY_TARGET=${DEPLOY_TARGET:-"kubernetes"} # Options: kubernetes, docker-compose, cloud
NAMESPACE=${NAMESPACE:-"watsonx-prod"}
ENVIRONMENT=${ENVIRONMENT:-"production"}
DOMAIN=${DOMAIN:-"watsonx-assistant.example.com"}
CONFIG_DIR=${CONFIG_DIR:-"./config/$ENVIRONMENT"}
DATA_DIR=${DATA_DIR:-"/data/watsonx"}
LOG_DIR=${LOG_DIR:-"/var/log/watsonx"}

# Ensure config directory exists
mkdir -p "$CONFIG_DIR"

# Check required tools based on deployment target
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"
    
    # Common prerequisites
    for cmd in git curl jq; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "${RED}❌ Required command not found: $cmd${NC}"
            exit 1
        fi
    done
    
    # Deployment target specific prerequisites
    case $DEPLOY_TARGET in
        kubernetes)
            for cmd in kubectl helm; do
                if ! command -v $cmd &> /dev/null; then
                    echo -e "${RED}❌ Required command not found: $cmd${NC}"
                    echo -e "${YELLOW}Please install $cmd for Kubernetes deployment${NC}"
                    exit 1
                fi
            done
            
            # Check kubectl connection
            if ! kubectl cluster-info &> /dev/null; then
                echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
                echo -e "${YELLOW}Please ensure you have proper kubeconfig set up${NC}"
                exit 1
            fi
            ;;
            
        docker-compose)
            if ! command -v docker-compose &> /dev/null; then
                echo -e "${RED}❌ docker-compose not found${NC}"
                exit 1
            fi
            ;;
            
        cloud)
            if ! command -v aws &> /dev/null && ! command -v az &> /dev/null; then
                echo -e "${RED}❌ No cloud CLI found (aws/az)${NC}"
                echo -e "${YELLOW}Please install the appropriate cloud provider CLI${NC}"
                exit 1
            fi
            ;;
    esac
    
    echo -e "${GREEN}✅ All prerequisites satisfied${NC}"
}

# Generate or update SSL certificates
setup_ssl() {
    echo -e "${YELLOW}Setting up SSL certificates...${NC}"
    SSL_DIR="$CONFIG_DIR/ssl"
    mkdir -p "$SSL_DIR"
    
    if [[ "$ENVIRONMENT" == "production" ]]; then
        # For production, check for existing certificates or use Let's Encrypt
        if [[ ! -f "$SSL_DIR/fullchain.pem" || ! -f "$SSL_DIR/privkey.pem" ]]; then
            echo -e "${YELLOW}Production SSL certificates not found${NC}"
            
            if command -v certbot &> /dev/null; then
                echo -e "${YELLOW}Using certbot to obtain Let's Encrypt certificate...${NC}"
                certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos -m "admin@example.com" \
                    --cert-path "$SSL_DIR/fullchain.pem" --key-path "$SSL_DIR/privkey.pem"
            else
                echo -e "${YELLOW}Generating self-signed certificate (NOT RECOMMENDED FOR PRODUCTION)${NC}"
                openssl req -x509 -newkey rsa:4096 -keyout "$SSL_DIR/privkey.pem" -out "$SSL_DIR/fullchain.pem" \
                    -days 365 -nodes -subj "/CN=$DOMAIN"
            fi
        else
            echo -e "${GREEN}✅ SSL certificates already exist${NC}"
        fi
    else
        # For non-production environments, generate self-signed certificate
        echo -e "${YELLOW}Generating self-signed certificate for $ENVIRONMENT environment${NC}"
        openssl req -x509 -newkey rsa:4096 -keyout "$SSL_DIR/privkey.pem" -out "$SSL_DIR/fullchain.pem" \
            -days 365 -nodes -subj "/CN=$DOMAIN"
    fi
    
    # Link certificates to expected nginx locations
    mkdir -p "$(dirname $0)/nginx/ssl"
    ln -sf "$SSL_DIR/fullchain.pem" "$(dirname $0)/nginx/ssl/server.crt"
    ln -sf "$SSL_DIR/privkey.pem" "$(dirname $0)/nginx/ssl/server.key"
    
    echo -e "${GREEN}✅ SSL certificates configured${NC}"
}

# Generate environment-specific configuration
generate_config() {
    echo -e "${YELLOW}Generating configuration for $ENVIRONMENT environment...${NC}"
    
    # Create .env file for docker-compose
    ENV_FILE="$CONFIG_DIR/.env"
    cat > "$ENV_FILE" << EOF
# Watsonx Code Assistant Production Environment
# Generated on $(date)

# Docker image configuration
REGISTRY_URL=$REGISTRY
TAG=$VERSION

# Service configuration
UI_PORT=5000
OLLAMA_PORT=11434
HTTP_PORT=80
HTTPS_PORT=443

# Resource paths
DATA_DIR=$DATA_DIR
LOG_DIR=$LOG_DIR

# Environment settings
NODE_ENV=production
ENV=$ENVIRONMENT
TZ=UTC

# Performance tuning
MAX_WORKERS=4
MEMORY_LIMIT=8G
EOF

    # Create kubernetes namespace if it doesn't exist
    if [[ "$DEPLOY_TARGET" == "kubernetes" ]]; then
        if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
            kubectl create namespace "$NAMESPACE"
        fi

        # Create kubernetes secret for configuration
        kubectl create secret generic watsonx-config \
            --from-file="$ENV_FILE" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
            
        # Create secrets for SSL certificates
        kubectl create secret tls watsonx-tls \
            --cert="$SSL_DIR/fullchain.pem" \
            --key="$SSL_DIR/privkey.pem" \
            --namespace="$NAMESPACE" \
            --dry-run=client -o yaml | kubectl apply -f -
    fi
    
    echo -e "${GREEN}✅ Configuration generated${NC}"
}

# Pull or build the Docker image
prepare_image() {
    echo -e "${YELLOW}Preparing Docker image...${NC}"
    FULL_IMAGE="$REGISTRY/$IMAGE_NAME:$VERSION"
    
    # Check if we need to build the image
    if [[ "$VERSION" == "latest" || "$VERSION" == *"-dev"* ]]; then
        echo -e "${YELLOW}Building Docker image: $FULL_IMAGE${NC}"
        docker build -t "$FULL_IMAGE" .
        
        # Push to registry if needed
        if [[ -n "$REGISTRY" && "$REGISTRY" != "local" ]]; then
            echo -e "${YELLOW}Pushing Docker image to registry...${NC}"
            docker push "$FULL_IMAGE"
        fi
    else
        # Try to pull the image
        echo -e "${YELLOW}Pulling Docker image: $FULL_IMAGE${NC}"
        if ! docker pull "$FULL_IMAGE"; then
            echo -e "${RED}❌ Failed to pull image. Building locally...${NC}"
            docker build -t "$FULL_IMAGE" .
            
            # Push to registry if needed
            if [[ -n "$REGISTRY" && "$REGISTRY" != "local" ]]; then
                docker push "$FULL_IMAGE"
            fi
        fi
    fi
    
    echo -e "${GREEN}✅ Docker image ready: $FULL_IMAGE${NC}"
}

# Setup data directories and permissions
setup_directories() {
    echo -e "${YELLOW}Setting up data directories...${NC}"
    
    # Create required directories with proper permissions
    mkdir -p "$DATA_DIR/models" "$DATA_DIR/app" "$LOG_DIR/nginx"
    
    # Set proper permissions (if running as root)
    if [[ $EUID -eq 0 ]]; then
        chown -R 10000:10001 "$DATA_DIR"
        chmod -R 750 "$DATA_DIR"
        
        chown -R 101:101 "$LOG_DIR/nginx"  # Nginx user in container
        chmod -R 750 "$LOG_DIR/nginx"
    else
        echo -e "${YELLOW}⚠️  Running as non-root. Please ensure proper permissions on data directories.${NC}"
    fi
    
    echo -e "${GREEN}✅ Directories configured${NC}"
}

# Deploy using docker-compose
deploy_docker_compose() {
    echo -e "${YELLOW}Deploying with docker-compose...${NC}"
    
    # Set environment variables for compose
    export REGISTRY_URL=$REGISTRY
    export TAG=$VERSION
    export DATA_DIR=$DATA_DIR
    export LOG_DIR=$LOG_DIR
    
    # Deploy the application
    docker-compose -f docker-compose.prod.yml --env-file "$CONFIG_DIR/.env" up -d
    
    echo -e "${GREEN}✅ Application deployed with docker-compose${NC}"
    echo -e "${BLUE}📊 Services are accessible at:${NC}"
    echo -e "   - HTTPS: https://$DOMAIN"
    echo -e "   - Ollama API: https://$DOMAIN/ollama/"
}

# Deploy to Kubernetes
deploy_kubernetes() {
    echo -e "${YELLOW}Deploying to Kubernetes...${NC}"
    
    # Replace placeholders in Kubernetes YAML files
    find ./kubernetes/production -type f -name "*.yaml" | while read file; do
        sed -i.bak \
            -e "s|{{NAMESPACE}}|$NAMESPACE|g" \
            -e "s|{{IMAGE}}|$REGISTRY/$IMAGE_NAME:$VERSION|g" \
            -e "s|{{DOMAIN}}|$DOMAIN|g" \
            "$file"
        rm -f "$file.bak"
    done
    
    # Apply Kubernetes manifests
    kubectl apply -f ./kubernetes/production/ -n "$NAMESPACE"
    
    # Apply autoscaling configuration
    kubectl apply -f ./kubernetes/autoscaling/hpa.yaml -n "$NAMESPACE"
    
    # Wait for deployment to become ready
    echo -e "${YELLOW}Waiting for deployment to become ready...${NC}"
    kubectl rollout status deployment/watsonx-code-assistant -n "$NAMESPACE" --timeout=300s
    
    echo -e "${GREEN}✅ Application deployed to Kubernetes${NC}"
    
    # Get service information
    SERVICE_IP=$(kubectl get svc watsonx-code-assistant -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
    SERVICE_HOST=$(kubectl get svc watsonx-code-assistant -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
    
    echo -e "${BLUE}📊 Service information:${NC}"
    if [[ -n $SERVICE_IP ]]; then
        echo -e "   - External IP: $SERVICE_IP"
    elif [[ -n $SERVICE_HOST ]]; then
        echo -e "   - External Hostname: $SERVICE_HOST"
    else
        echo -e "   - Service is pending external address assignment"
    fi
    
    # Get ingress information if available
    if kubectl get ingress -n "$NAMESPACE" &> /dev/null; then
        INGRESS_HOST=$(kubectl get ing -n "$NAMESPACE" -o jsonpath="{.items[0].spec.rules[0].host}")
        echo -e "   - Ingress: https://$INGRESS_HOST"
    fi
}

# Deploy to cloud platform
deploy_cloud() {
    echo -e "${RED}Cloud deployment not yet implemented${NC}"
    echo -e "${YELLOW}Please adapt this script for your specific cloud provider${NC}"
    
    # This would contain provider-specific deployment logic
    # AWS example:
    # aws cloudformation deploy --template-file cloudformation.yaml --stack-name watsonx-code-assistant
    
    # Azure example:
    # az deployment group create --resource-group myResourceGroup --template-file azuredeploy.json
}

# Setup monitoring
setup_monitoring() {
    echo -e "${YELLOW}Setting up monitoring...${NC}"
    
    if [[ "$DEPLOY_TARGET" == "kubernetes" ]]; then
        # Install Prometheus and Grafana if requested
        if [[ "$INSTALL_MONITORING" == "true" ]]; then
            echo -e "${YELLOW}Installing Prometheus and Grafana...${NC}"
            
            # Add Prometheus Helm repo
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
            helm repo update
            
            # Install Prometheus Stack (includes Grafana)
            helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
                --namespace monitoring --create-namespace \
                --set grafana.adminPassword=admin \
                --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
                
            # Apply ServiceMonitor for our application
            kubectl apply -f ./kubernetes/monitoring/service-monitor.yaml -n "$NAMESPACE"
            
            # Wait for Grafana to be ready
            kubectl rollout status deployment/monitoring-grafana -n monitoring --timeout=120s
            
            # Get Grafana access information
            GRAFANA_IP=$(kubectl get svc monitoring-grafana -n monitoring -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
            GRAFANA_PORT=$(kubectl get svc monitoring-grafana -n monitoring -o jsonpath="{.spec.ports[0].port}")
            
            echo -e "${GREEN}✅ Monitoring setup complete${NC}"
            echo -e "${BLUE}📊 Grafana dashboard:${NC}"
            echo -e "   - URL: http://$GRAFANA_IP:$GRAFANA_PORT"
            echo -e "   - Username: admin"
            echo -e "   - Password: admin (please change after first login)"
        else
            echo -e "${YELLOW}Skipping monitoring installation${NC}"
            echo -e "${YELLOW}ℹ️ To install monitoring, run the script with INSTALL_MONITORING=true${NC}"
        fi
    elif [[ "$DEPLOY_TARGET" == "docker-compose" ]]; then
        # Create Prometheus config for docker-compose
        mkdir -p "$CONFIG_DIR/prometheus"
        cat > "$CONFIG_DIR/prometheus/prometheus.yml" << EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'watsonx'
    static_configs:
      - targets: ['watsonx:5000']
EOF
        echo -e "${YELLOW}Created Prometheus configuration${NC}"
        echo -e "${YELLOW}To enable monitoring, add Prometheus and Grafana services to your docker-compose.prod.yml${NC}"
    fi
}

# Perform post-deployment verification
verify_deployment() {
    echo -e "${YELLOW}Verifying deployment...${NC}"
    
    # Check if the service is accessible
    case $DEPLOY_TARGET in
        kubernetes)
            echo -e "${YELLOW}Checking service health...${NC}"
            SERVICE_IP=$(kubectl get svc watsonx-code-assistant -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].ip}")
            
            if [[ -z "$SERVICE_IP" ]]; then
                SERVICE_HOST=$(kubectl get svc watsonx-code-assistant -n "$NAMESPACE" -o jsonpath="{.status.loadBalancer.ingress[0].hostname}")
                if [[ -n "$SERVICE_HOST" ]]; then
                    SERVICE_IP=$SERVICE_HOST
                else
                    echo -e "${YELLOW}⚠️ Service IP not available yet, skipping health check${NC}"
                    return
                fi
            fi
            
            # Check health endpoint
            if curl -s -o /dev/null -w "%{http_code}" "http://$SERVICE_IP:80/health"; then
                echo -e "${GREEN}✅ Service is healthy${NC}"
            else
                echo -e "${RED}❌ Service health check failed${NC}"
            fi
            ;;
            
        docker-compose)
            echo -e "${YELLOW}Checking service health...${NC}"
            if curl -s -o /dev/null -w "%{http_code}" "http://localhost:${HTTP_PORT:-80}/health"; then
                echo -e "${GREEN}✅ Service is healthy${NC}"
            else
                echo -e "${RED}❌ Service health check failed${NC}"
            fi
            ;;
    esac
}

# Display deployment summary
deployment_summary() {
    echo -e "\n${BLUE}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}✅ Watsonx Code Assistant Deployment Complete${NC}"
    echo -e "${BLUE}${BOLD}==================================================================${NC}"
    echo -e "${BLUE}Deployment Configuration:${NC}"
    echo -e "   - Environment: ${BOLD}$ENVIRONMENT${NC}"
    echo -e "   - Target: ${BOLD}$DEPLOY_TARGET${NC}"
    echo -e "   - Image: ${BOLD}$REGISTRY/$IMAGE_NAME:$VERSION${NC}"
    echo -e "   - Data Directory: ${BOLD}$DATA_DIR${NC}"
    
    echo -e "\n${BLUE}Access Information:${NC}"
    case $DEPLOY_TARGET in
        kubernetes)
            echo -e "   - Service: ${BOLD}https://$DOMAIN${NC}"
            echo -e "   - Namespace: ${BOLD}$NAMESPACE${NC}"
            ;;
        docker-compose)
            echo -e "   - Web UI: ${BOLD}https://$DOMAIN${NC}"
            echo -e "   - Ollama API: ${BOLD}https://$DOMAIN/ollama/${NC}"
            ;;
    esac
    
    echo -e "\n${BLUE}Management Commands:${NC}"
    case $DEPLOY_TARGET in
        kubernetes)
            echo -e "   - View logs: ${BOLD}kubectl logs -n $NAMESPACE -l app=watsonx-code-assistant${NC}"
            echo -e "   - Get pods: ${BOLD}kubectl get pods -n $NAMESPACE${NC}"
            echo -e "   - Scale deployment: ${BOLD}kubectl scale deployment/watsonx-code-assistant -n $NAMESPACE --replicas=3${NC}"
            ;;
        docker-compose)
            echo -e "   - View logs: ${BOLD}docker-compose -f docker-compose.prod.yml logs -f${NC}"
            echo -e "   - Restart: ${BOLD}docker-compose -f docker-compose.prod.yml restart${NC}"
            echo -e "   - Stop: ${BOLD}docker-compose -f docker-compose.prod.yml down${NC}"
            ;;
    esac
    
    echo -e "\n${BLUE}Next Steps:${NC}"
    echo -e "   - Set up regular database backups"
    echo -e "   - Review monitoring alerts and dashboards"
    echo -e "   - Update DNS records to point to your deployment"
    echo -e "   - Implement additional security measures for your environment"
    echo -e "${BLUE}==================================================================${NC}\n"
}

# Main function to execute deployment
main() {
    # Welcome message
    echo -e "${YELLOW}Starting deployment of Watsonx Code Assistant to $ENVIRONMENT environment${NC}"
    echo -e "${YELLOW}Deployment target: $DEPLOY_TARGET${NC}"
    
    # Check prerequisites
    check_prerequisites
    
    # Setup directories
    setup_directories
    
    # Setup SSL certificates
    setup_ssl
    
    # Generate configuration
    generate_config
    
    # Prepare Docker image
    prepare_image
    
    # Deploy based on target
    case $DEPLOY_TARGET in
        kubernetes)
            deploy_kubernetes
            ;;
        docker-compose)
            deploy_docker_compose
            ;;
        cloud)
            deploy_cloud
            ;;
        *)
            echo -e "${RED}❌ Unsupported deployment target: $DEPLOY_TARGET${NC}"
            echo -e "${YELLOW}Supported targets: kubernetes, docker-compose, cloud${NC}"
            exit 1
            ;;
    esac
    
    # Setup monitoring
    setup_monitoring
    
    # Verify deployment
    verify_deployment
    
    # Display deployment summary
    deployment_summary
}

# Execute main function
main

#!/bin/bash
# Docker Production Deployment Script for Watsonx Code Assistant
# Provides zero-downtime deployment with health verification and automated rollback

set -eo pipefail

# Color formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Default configuration (can be overridden with environment variables)
REGISTRY=${REGISTRY:-"ghcr.io/ibm"}
IMAGE_NAME=${IMAGE_NAME:-"watsonx-code-assistant"}
VERSION=${VERSION:-$(git describe --tags --always 2>/dev/null || echo "latest")}
ENVIRONMENT=${ENVIRONMENT:-"production"}
DATA_DIR=${DATA_DIR:-"/data/watsonx"}
LOG_DIR=${LOG_DIR:-"/var/log/watsonx"}
BACKUP_DIR=${BACKUP_DIR:-"./backups"}
CONFIG_DIR=${CONFIG_DIR:-"./config/$ENVIRONMENT"}
COMPOSE_FILE=${COMPOSE_FILE:-"docker-compose.prod.yml"}
STACK_NAME=${STACK_NAME:-"watsonx"}
AUTO_ROLLBACK=${AUTO_ROLLBACK:-"true"}
HEALTH_CHECK_URL=${HEALTH_CHECK_URL:-"http://localhost:5000/health"}
MAX_HEALTH_RETRIES=${MAX_HEALTH_RETRIES:-"12"}
HEALTH_RETRY_INTERVAL=${HEALTH_RETRY_INTERVAL:-"5"}
SWARM_MODE=${SWARM_MODE:-"false"}
SEND_METRICS=${SEND_METRICS:-"true"}
NOTIFY_SLACK=${NOTIFY_SLACK:-"false"}
SLACK_WEBHOOK_URL=${SLACK_WEBHOOK_URL:-""}
ENABLE_SECRETS=${ENABLE_SECRETS:-"true"}

echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "${BLUE}${BOLD}     Watsonx Code Assistant - Docker Production Deployment        ${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "${YELLOW}Environment: $ENVIRONMENT${NC}"
echo -e "${YELLOW}Image: $REGISTRY/$IMAGE_NAME:$VERSION${NC}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --env=*)
            ENVIRONMENT="${1#*=}"
            CONFIG_DIR="./config/$ENVIRONMENT"
            ;;
        --version=*)
            VERSION="${1#*=}"
            ;;
        --no-rollback)
            AUTO_ROLLBACK="false"
            ;;
        --swarm)
            SWARM_MODE="true"
            ;;
        --no-metrics)
            SEND_METRICS="false"
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --env=NAME                 Set environment (production, staging, etc.)"
            echo "  --version=VERSION          Specify version tag to deploy"
            echo "  --no-rollback              Disable automatic rollback on failure"
            echo "  --swarm                    Deploy to Docker Swarm instead of Compose"
            echo "  --no-metrics               Disable sending deployment metrics"
            echo "  --help                     Show this help message"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
    shift
done

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ Required command not found: $1${NC}"
        echo "Please install it before running this script."
        exit 1
    fi
}

# Function to send metrics about the deployment
send_deployment_metrics() {
    local status=$1
    local duration=$2
    local error_msg=$3

    if [[ "$SEND_METRICS" != "true" ]]; then
        return 0
    fi

    # Create a deployment metrics file
    local metrics_file="$CONFIG_DIR/deploy-metrics.json"
    cat > "$metrics_file" << EOF
{
  "deployment": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "environment": "$ENVIRONMENT",
    "version": "$VERSION",
    "status": "$status",
    "duration_seconds": $duration,
    "error": "$error_msg",
    "host": "$(hostname)",
    "user": "$(whoami)"
  }
}
EOF

    # In a real scenario, you would send this to a metrics collection endpoint
    echo -e "${GREEN}✓ Deployment metrics recorded to $metrics_file${NC}"
    
    # Optionally send to Slack
    if [[ "$NOTIFY_SLACK" == "true" && -n "$SLACK_WEBHOOK_URL" ]]; then
        local emoji="✅"
        if [[ "$status" != "success" ]]; then
            emoji="❌"
        fi
        
        curl -s -X POST -H "Content-type: application/json" \
            --data "{\"text\":\"$emoji *Watsonx Code Assistant Deployment*\n*Status:* $status\n*Environment:* $ENVIRONMENT\n*Version:* $VERSION\n*Duration:* ${duration}s${error_msg:+\n*Error:* $error_msg}\"}" \
            "$SLACK_WEBHOOK_URL" || echo -e "${YELLOW}⚠️ Failed to send Slack notification${NC}"
    fi
}

# Function to create a backup of current Docker volumes and configs
backup_current_state() {
    echo -e "${YELLOW}Creating backup of current state...${NC}"
    
    # Create backup directory with timestamp
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_path="$BACKUP_DIR/$timestamp"
    mkdir -p "$backup_path"
    
    # Save current Docker Compose file
    if [[ -f "$COMPOSE_FILE" ]]; then
        cp "$COMPOSE_FILE" "$backup_path/"
    fi
    
    # If supporting swarm, back up stack configs
    if [[ "$SWARM_MODE" == "true" ]]; then
        if docker stack ls | grep -q "$STACK_NAME"; then
            docker stack config "$STACK_NAME" > "$backup_path/stack-config.yml" 2>/dev/null || true
        fi
    fi
    
    # Export environment variables
    env | grep -E 'WATSONX_|OLLAMA_|MODEL_' > "$backup_path/environment.txt" 2>/dev/null || true
    
    # Back up Docker configs and secrets if used
    if [[ "$ENABLE_SECRETS" == "true" ]]; then
        mkdir -p "$backup_path/secrets"
        if [[ -d "$CONFIG_DIR/secrets" ]]; then
            cp -r "$CONFIG_DIR/secrets"/* "$backup_path/secrets/" 2>/dev/null || true
        fi
    fi
    
    # Record version information
    echo "$VERSION" > "$backup_path/version.txt"
    
    echo -e "${GREEN}✓ Backup created at $backup_path${NC}"
    
    # Return the backup path
    echo "$backup_path"
}

# Function to verify Docker images exist or pull them
verify_docker_images() {
    echo -e "${YELLOW}Verifying Docker images...${NC}"
    
    # Main application image
    local full_image="$REGISTRY/$IMAGE_NAME:$VERSION"
    
    if ! docker image inspect "$full_image" &>/dev/null; then
        echo -e "${YELLOW}Image $full_image not found locally, attempting to pull...${NC}"
        if ! docker pull "$full_image"; then
            echo -e "${RED}❌ Failed to pull image $full_image${NC}"
            echo -e "${YELLOW}Attempting to build image locally...${NC}"
            
            if [[ -f "Dockerfile" ]]; then
                docker build -t "$full_image" .
            else
                echo -e "${RED}❌ Cannot pull or build image $full_image${NC}"
                return 1
            fi
        fi
    else
        echo -e "${GREEN}✓ Image $full_image found locally${NC}"
    fi
    
    # Nginx image (if used in production)
    if grep -q "nginx:" "$COMPOSE_FILE"; then
        local nginx_image=$(grep -o "nginx:[^ ]*" "$COMPOSE_FILE" | head -1)
        if [[ -n "$nginx_image" && ! $(docker image inspect "nginx:$nginx_image" 2>/dev/null) ]]; then
            echo -e "${YELLOW}Pulling nginx image...${NC}"
            docker pull "nginx:$nginx_image" || true
        fi
    fi
    
    echo -e "${GREEN}✓ Docker images verified${NC}"
    return 0
}

# Function to prepare Docker configuration
prepare_docker_configuration() {
    echo -e "${YELLOW}Preparing Docker configuration...${NC}"
    
    # Create configuration directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Prepare .env file for Docker Compose
    local env_file="$CONFIG_DIR/.env"
    cat > "$env_file" << EOF
# Watsonx Code Assistant Environment Configuration
# Generated on $(date)
# Environment: $ENVIRONMENT
REGISTRY_URL=$REGISTRY
TAG=$VERSION
DATA_DIR=$DATA_DIR
LOG_DIR=$LOG_DIR
HTTP_PORT=80
HTTPS_PORT=443
UI_PORT=5000
OLLAMA_PORT=11434
TZ=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || echo "UTC")
ENV=$ENVIRONMENT
NODE_ENV=$ENVIRONMENT
EOF
    
    # Create directories for persistent data if they don't exist
    mkdir -p "$DATA_DIR/models" "$DATA_DIR/app" "$LOG_DIR/nginx"
    
    # Set proper permissions on data directory
    if [[ $EUID -eq 0 ]]; then
        # Assuming 10000/10001 is the container user/group
        chown -R 10000:10001 "$DATA_DIR" 2>/dev/null || true
    fi
    
    # Generate SSL certificates if needed
    if [[ ! -f "$CONFIG_DIR/ssl/server.crt" ]]; then
        echo -e "${YELLOW}Generating SSL certificates...${NC}"
        mkdir -p "$CONFIG_DIR/ssl"
        openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
            -subj "/CN=localhost" \
            -keyout "$CONFIG_DIR/ssl/server.key" \
            -out "$CONFIG_DIR/ssl/server.crt" 2>/dev/null
        
        # Link certificates to expected nginx locations
        mkdir -p "./nginx/ssl"
        ln -sf "$CONFIG_DIR/ssl/server.crt" "./nginx/ssl/server.crt" 2>/dev/null || cp "$CONFIG_DIR/ssl/server.crt" "./nginx/ssl/server.crt" 2>/dev/null || true
        ln -sf "$CONFIG_DIR/ssl/server.key" "./nginx/ssl/server.key" 2>/dev/null || cp "$CONFIG_DIR/ssl/server.key" "./nginx/ssl/server.key" 2>/dev/null || true
    fi
    
    # Handle Docker secrets if enabled
    if [[ "$ENABLE_SECRETS" == "true" ]]; then
        prepare_docker_secrets
    fi
    
    echo -e "${GREEN}✓ Docker configuration prepared${NC}"
}

# Function to prepare Docker secrets
prepare_docker_secrets() {
    echo -e "${YELLOW}Setting up Docker secrets...${NC}"
    
    mkdir -p "$CONFIG_DIR/secrets"
    local secrets_dir="$CONFIG_DIR/secrets"
    
    # Check if we're in swarm mode
    if [[ "$SWARM_MODE" == "true" ]]; then
        # Create Docker secrets for swarm deployment
        for secret_file in "$secrets_dir"/*; do
            if [[ -f "$secret_file" ]]; then
                local secret_name=$(basename "$secret_file")
                # Check if secret already exists
                if ! docker secret ls | grep -q "$secret_name"; then
                    echo -e "${YELLOW}Creating Docker secret: $secret_name${NC}"
                    docker secret create "$secret_name" "$secret_file"
                fi
            fi
        done
    else
        # For Docker Compose, secrets are mounted as files
        echo -e "${GREEN}✓ Secrets directory prepared for Docker Compose${NC}"
    fi
}

# Function to deploy using Docker Compose or Swarm
deploy_docker() {
    echo -e "${YELLOW}Starting Docker deployment...${NC}"
    
    # Load environment variables from config
    set -a
    source "$CONFIG_DIR/.env"
    set +a
    
    # Different deployment depending on mode
    if [[ "$SWARM_MODE" == "true" ]]; then
        echo -e "${YELLOW}Deploying to Docker Swarm...${NC}"
        
        # Initialize swarm if needed
        if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
            echo -e "${YELLOW}Initializing Docker Swarm...${NC}"
            docker swarm init --advertise-addr "$(hostname -I | awk '{print $1}')" || true
        fi
        
        # Deploy the stack
        docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
        
        # Wait for services to be running
        echo -e "${YELLOW}Waiting for services to start...${NC}"
        sleep 10  # Initial wait for services to start creating tasks
        
        # Check if all services are running with the desired number of replicas
        local max_attempts=30
        local attempt=1
        local all_services_ready=false
        
        while [[ $attempt -le $max_attempts && "$all_services_ready" != "true" ]]; do
            all_services_ready=true
            
            # Get all services in the stack
            local services=$(docker stack services "$STACK_NAME" --format "{{.Name}}")
            
            for service in $services; do
                local replicas=$(docker service ls --filter "name=${service}" --format "{{.Replicas}}")
                # Check if the actual matches desired (e.g., "2/2")
                if [[ "$replicas" != *"/"* || "${replicas%/*}" != "${replicas#*/}" ]]; then
                    all_services_ready=false
                    echo -e "${YELLOW}Service $service: $replicas${NC}"
                    break
                fi
            done
            
            if [[ "$all_services_ready" != "true" ]]; then
                echo -e "${YELLOW}Attempt $attempt/$max_attempts: Waiting for all services to be ready...${NC}"
                sleep 5
                attempt=$((attempt+1))
            fi
        done
        
        if [[ "$all_services_ready" == "true" ]]; then
            echo -e "${GREEN}✓ All services are running${NC}"
        else
            echo -e "${RED}❌ Timed out waiting for services to be ready${NC}"
            return 1
        fi
        
    else
        echo -e "${YELLOW}Deploying with Docker Compose...${NC}"
        
        # Pull images first to prevent downtime
        docker-compose -f "$COMPOSE_FILE" pull 2>/dev/null || true
        
        # Deploy with zero downtime by doing it one service at a time
        # First, make sure nginx is updated first if it exists in the compose file
        if grep -q "nginx:" "$COMPOSE_FILE"; then
            echo -e "${YELLOW}Updating nginx service...${NC}"
            docker-compose -f "$COMPOSE_FILE" up -d --no-deps --build nginx
            sleep 3
        fi
        
        # Then, update the main application
        echo -e "${YELLOW}Updating main application service...${NC}"
        docker-compose -f "$COMPOSE_FILE" up -d --no-deps --build watsonx
        
        # Finally, update any remaining services
        echo -e "${YELLOW}Ensuring all services are up-to-date...${NC}"
        docker-compose -f "$COMPOSE_FILE" up -d
    fi
    
    echo -e "${GREEN}✓ Docker deployment completed${NC}"
    return 0
}

# Health check to validate deployment
verify_health() {
    echo -e "${YELLOW}Verifying deployment health...${NC}"
    
    # Give services time to initialize
    sleep 5
    
    # Attempt to check health endpoint
    local attempt=1
    local health_status=false
    
    echo -e "${YELLOW}Checking health at: $HEALTH_CHECK_URL${NC}"
    
    while [[ $attempt -le $MAX_HEALTH_RETRIES ]]; do
        echo -e "${YELLOW}Health check attempt $attempt/$MAX_HEALTH_RETRIES...${NC}"
        
        # Try to get HTTP status code from health endpoint
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" "$HEALTH_CHECK_URL" || echo "error")
        
        if [[ "$http_status" == "200" ]]; then
            echo -e "${GREEN}✓ Health check passed${NC}"
            health_status=true
            break
        else
            echo -e "${YELLOW}Health check failed with status: $http_status. Retrying in ${HEALTH_RETRY_INTERVAL}s...${NC}"
            sleep "$HEALTH_RETRY_INTERVAL"
            attempt=$((attempt+1))
        fi
    done
    
    # Check for Docker container errors
    if [[ "$health_status" == "true" ]]; then
        if [[ "$SWARM_MODE" == "true" ]]; then
            # Check for errors in Docker service logs
            local service_errors=$(docker service logs --since 1m "$STACK_NAME"_watsonx 2>&1 | grep -i "error" | wc -l)
            if [[ $service_errors -gt 5 ]]; then
                echo -e "${RED}⚠️ Warning: $service_errors recent errors found in service logs${NC}"
            fi
        else
            # Check for container errors
            local container_errors=$(docker-compose -f "$COMPOSE_FILE" logs --tail=50 watsonx 2>&1 | grep -i "error" | wc -l)
            if [[ $container_errors -gt 5 ]]; then
                echo -e "${RED}⚠️ Warning: $container_errors recent errors found in container logs${NC}"
            fi
        fi
    else
        echo -e "${RED}❌ Health check failed after $MAX_HEALTH_RETRIES attempts${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Deployment verified${NC}"
    return 0
}

# Rollback to the previous version if deployment fails
rollback_deployment() {
    echo -e "${YELLOW}Rolling back deployment...${NC}"
    
    # Find last successful backup
    local latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d -not -name "$(basename "$current_backup")" | sort -r | head -1)
    
    if [[ -z "$latest_backup" ]]; then
        echo -e "${RED}❌ No previous backup found for rollback${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}Rolling back to backup: $latest_backup${NC}"
    
    # Get previous version
    local previous_version=$(cat "$latest_backup/version.txt" 2>/dev/null || echo "latest")
    VERSION=$previous_version
    
    # Restore environment configuration
    if [[ -f "$latest_backup/.env" ]]; then
        cp "$latest_backup/.env" "$CONFIG_DIR/"
    fi
    
    # Restore Docker Compose file if it exists in the backup
    if [[ -f "$latest_backup/$COMPOSE_FILE" ]]; then
        cp "$latest_backup/$COMPOSE_FILE" "./"
    fi
    
    # In swarm mode, use the backed up stack config
    if [[ "$SWARM_MODE" == "true" && -f "$latest_backup/stack-config.yml" ]]; then
        docker stack deploy -c "$latest_backup/stack-config.yml" "$STACK_NAME"
    else
        echo -e "${YELLOW}Redeploying with previous version: $previous_version${NC}"
        
        # Update version in .env file
        sed -i "s/TAG=.*/TAG=$previous_version/" "$CONFIG_DIR/.env"
        
        # Load environment variables
        set -a
        source "$CONFIG_DIR/.env"
        set +a
        
        # Redeploy with previous version
        docker-compose -f "$COMPOSE_FILE" up -d
    fi
    
    echo -e "${GREEN}✓ Rollback completed to version $previous_version${NC}"
    return 0
}

# Clean up old backups and deployments
cleanup() {
    echo -e "${YELLOW}Performing cleanup...${NC}"
    
    # Keep only the last 5 backups
    local backup_count=$(find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d | wc -l)
    if [[ $backup_count -gt 5 ]]; then
        echo -e "${YELLOW}Removing old backups (keeping the most recent 5)...${NC}"
        find "$BACKUP_DIR" -maxdepth 1 -mindepth 1 -type d | sort | head -n -5 | xargs rm -rf
    fi
    
    # Remove unused Docker images
    if [[ "$CLEAN_IMAGES" == "true" ]]; then
        echo -e "${YELLOW}Removing dangling Docker images...${NC}"
        docker image prune --force
    fi
    
    echo -e "${GREEN}✓ Cleanup completed${NC}"
}

# Show information about the deployed services
show_deployment_info() {
    echo -e "\n${BLUE}${BOLD}==================================================================${NC}"
    echo -e "${GREEN}${BOLD}✅ Watsonx Code Assistant Deployment Information${NC}"
    echo -e "${BLUE}${BOLD}==================================================================${NC}"
    
    echo -e "${BLUE}${BOLD}Deployment Details:${NC}"
    echo -e "${BLUE}• Environment:${NC} $ENVIRONMENT"
    echo -e "${BLUE}• Version:${NC} $VERSION"
    echo -e "${BLUE}• Timestamp:${NC} $(date)"
    
    # Show service endpoints
    echo -e "\n${BLUE}${BOLD}Service Endpoints:${NC}"
    
    # Determine service endpoints based on deployment method
    if [[ "$SWARM_MODE" == "true" ]]; then
        local service_ip=$(docker node inspect self --format '{{.Status.Addr}}')
        echo -e "${BLUE}• Web UI:${NC} https://$service_ip"
        echo -e "${BLUE}• Ollama API:${NC} https://$service_ip/ollama/"
    else
        echo -e "${BLUE}• Web UI:${NC} https://localhost"
        echo -e "${BLUE}• Ollama API:${NC} https://localhost/ollama/"
    fi
    
    # Show container status
    echo -e "\n${BLUE}${BOLD}Container Status:${NC}"
    if [[ "$SWARM_MODE" == "true" ]]; then
        docker stack services "$STACK_NAME"
    else
        docker-compose -f "$COMPOSE_FILE" ps
    fi
    
    # Show management commands
    echo -e "\n${BLUE}${BOLD}Management Commands:${NC}"
    if [[ "$SWARM_MODE" == "true" ]]; then
        echo -e "${BLUE}• View logs:${NC} docker service logs $STACK_NAME"_"watsonx"
        echo -e "${BLUE}• Scale service:${NC} docker service scale $STACK_NAME"_"watsonx=3"
        echo -e "${BLUE}• Stop services:${NC} docker stack rm $STACK_NAME"
    else
        echo -e "${BLUE}• View logs:${NC} docker-compose -f $COMPOSE_FILE logs -f"
        echo -e "${BLUE}• Restart services:${NC} docker-compose -f $COMPOSE_FILE restart"
        echo -e "${BLUE}• Stop services:${NC} docker-compose -f $COMPOSE_FILE down"
    fi
    
    echo -e "${BLUE}${BOLD}==================================================================${NC}\n"
}

# Main function
main() {
    local start_time=$(date +%s)
    local deploy_status="failed"
    local error_message=""
    local current_backup=""
    
    # Check prerequisites
    check_command docker
    [[ "$SWARM_MODE" == "false" ]] && check_command docker-compose
    check_command curl
    
    trap 'send_deployment_metrics "$deploy_status" "$(($(date +%s) - start_time))" "$error_message"' EXIT
    
    try {
        # Create backup of current state
        current_backup=$(backup_current_state)
        
        # Verify Docker images exist
        verify_docker_images
        
        # Prepare Docker configuration
        prepare_docker_configuration
        
        # Deploy using Docker
        deploy_docker
        
        # Verify deployment health
        if ! verify_health; then
            error_message="Health check failed"
            throw "Health check failed"
        fi
        
        # Deployment succeeded
        deploy_status="success"
        
        # Perform cleanup
        cleanup
        
        # Show information about deployment
        show_deployment_info
        
    } catch {
        # Deployment failed
        echo -e "${RED}❌ Deployment failed: $1${NC}"
        error_message="$1"
        
        # Rollback if enabled
        if [[ "$AUTO_ROLLBACK" == "true" ]]; then
            echo -e "${YELLOW}Initiating automatic rollback...${NC}"
            if rollback_deployment; then
                deploy_status="failed_with_rollback"
            else
                deploy_status="failed_rollback_failed"
                error_message="$error_message (Rollback also failed)"
            fi
        fi
    }
    
    # Return appropriate exit code
    if [[ "$deploy_status" == "success" ]]; then
        return 0
    else
        return 1
    fi
}

# Function that implements try-catch in bash
try() {
    # Run the code that might fail
    "$@"
}

catch() {
    # Store the exit code
    local exit_code=$?
    
    # If the exit code is not 0, meaning an error occured
    if [ $exit_code -ne 0 ]; then
        # Run the error handler
        "$@"
        
        # And return the original error code
        return $exit_code
    fi
}

throw() {
    # Exit with error message
    echo "$1" >&2
    exit 1
}

# Run the main function
main

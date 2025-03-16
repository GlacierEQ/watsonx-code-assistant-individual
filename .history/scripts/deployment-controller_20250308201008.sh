#!/bin/bash
# Deployment Controller for Watsonx Code Assistant
# Manages the complete deployment lifecycle including verification and rollback

set -eo pipefail

# Color formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration - can be overridden with environment variables
DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-"standard"} # Options: standard, blue-green, canary
ENVIRONMENT=${ENVIRONMENT:-"production"}  # Options: production, staging, development
APPROVAL_REQUIRED=${APPROVAL_REQUIRED:-"true"}  # Whether manual approval is needed
AUTOMATED_TESTS=${AUTOMATED_TESTS:-"true"}  # Whether to run automated tests
AUTO_ROLLBACK=${AUTO_ROLLBACK:-"true"}  # Whether to auto-rollback on failure
VALIDATION_TIMEOUT=${VALIDATION_TIMEOUT:-"300"}  # Time in seconds to validate deployment
NOTIFICATION_URL=${NOTIFICATION_URL:-""}  # Webhook URL for notifications
CONFIG_FILE=${CONFIG_FILE:-"./deployment-config.json"}  # Deployment configuration

# Main deployment controller
main() {
    echo -e "${BLUE}${BOLD}===== Watsonx Code Assistant Deployment Controller =====${NC}"
    echo -e "${YELLOW}Deployment Type: ${DEPLOYMENT_TYPE}${NC}"
    echo -e "${YELLOW}Environment: ${ENVIRONMENT}${NC}"
    
    # Load configuration
    load_config
    
    # Pre-flight checks
    pre_flight_checks
    
    # Backup before deployment
    backup_current_state
    
    # Get deployment approval if required
    if [[ "$APPROVAL_REQUIRED" == "true" ]]; then
        get_deployment_approval
    fi
    
    # Execute pre-deployment tasks
    execute_pre_deployment_tasks
    
    # Execute deployment based on type
    case $DEPLOYMENT_TYPE in
        blue-green)
            execute_blue_green_deployment
            ;;
        canary)
            execute_canary_deployment
            ;;
        *)
            execute_standard_deployment
            ;;
    esac
    
    # Execute post-deployment verification
    if ! execute_post_deployment_verification; then
        echo -e "${RED}${BOLD}Deployment verification failed!${NC}"
        
        if [[ "$AUTO_ROLLBACK" == "true" ]]; then
            echo -e "${YELLOW}Automatically rolling back to previous state...${NC}"
            execute_rollback
            send_notification "FAILED_WITH_ROLLBACK" "Deployment failed verification and was rolled back"
            exit 1
        else
            echo -e "${YELLOW}Please check logs and resolve issues manually.${NC}"
            send_notification "FAILED" "Deployment failed verification - manual intervention required"
            exit 1
        fi
    fi
    
    # Finalize deployment
    finalize_deployment
    
    # Send success notification
    send_notification "SUCCESS" "Deployment completed successfully"
    
    echo -e "${GREEN}${BOLD}===== Deployment Completed Successfully =====${NC}"
}

# Load configuration from file
load_config() {
    echo -e "${YELLOW}Loading deployment configuration...${NC}"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        # Extract values from config file
        if command -v jq &>/dev/null; then
            # Use jq if available
            if [[ -z "$DEPLOYMENT_TYPE" || "$DEPLOYMENT_TYPE" == "default" ]]; then
                DEPLOYMENT_TYPE=$(jq -r '.deployment_type // "standard"' "$CONFIG_FILE")
            fi
            
            # Load other configs if not set by environment variables
            DEPLOY_TIMEOUT=$(jq -r '.timeout // 600' "$CONFIG_FILE")
            PRE_DEPLOYMENT_SCRIPT=$(jq -r '.pre_deployment_script // ""' "$CONFIG_FILE")
            POST_DEPLOYMENT_SCRIPT=$(jq -r '.post_deployment_script // ""' "$CONFIG_FILE")
            
            echo -e "${GREEN}✓ Configuration loaded from $CONFIG_FILE${NC}"
        else
            echo -e "${YELLOW}⚠️ jq not found. Using basic config parsing.${NC}"
            # Basic parsing using grep
            if [[ -z "$DEPLOYMENT_TYPE" || "$DEPLOYMENT_TYPE" == "default" ]]; then
                DEPLOYMENT_TYPE=$(grep -o '"deployment_type"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" | cut -d'"' -f4)
                DEPLOYMENT_TYPE=${DEPLOYMENT_TYPE:-"standard"}
            fi
        fi
    else
        echo -e "${YELLOW}⚠️ Configuration file not found. Using default values.${NC}"
    fi
    
    # Validate deployment type
    case $DEPLOYMENT_TYPE in
        standard|blue-green|canary)
            echo -e "${GREEN}✓ Using $DEPLOYMENT_TYPE deployment strategy${NC}"
            ;;
        *)
            echo -e "${RED}❌ Invalid deployment type: $DEPLOYMENT_TYPE${NC}"
            echo -e "${YELLOW}Falling back to standard deployment${NC}"
            DEPLOYMENT_TYPE="standard"
            ;;
    esac
}

# Pre-flight checks before deployment
pre_flight_checks() {
    echo -e "${YELLOW}Running pre-flight checks...${NC}"
    
    # Check required tools
    for cmd in curl jq kubectl docker; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${YELLOW}⚠️ Command not found: $cmd${NC}"
        else
            echo -e "${GREEN}✓ Found: $cmd${NC}"
        fi
    done
    
    # Check connection to Kubernetes cluster if needed
    if [[ "$DEPLOYMENT_TYPE" == "blue-green" || "$DEPLOYMENT_TYPE" == "canary" ]]; then
        if ! kubectl cluster-info &>/dev/null; then
            echo -e "${RED}❌ Cannot connect to Kubernetes cluster${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Kubernetes connection verified${NC}"
    fi
    
    # Check Docker registry access
    if ! docker info &>/dev/null; then
        echo -e "${RED}❌ Cannot connect to Docker daemon${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Docker connection verified${NC}"
    
    # Check disk space
    FREE_SPACE=$(df -h / | awk 'NR==2 {print $4}')
    echo -e "${GREEN}✓ Free disk space: $FREE_SPACE${NC}"
    
    # Run automated tests if enabled
    if [[ "$AUTOMATED_TESTS" == "true" ]]; then
        run_automated_tests
    fi
    
    echo -e "${GREEN}✓ All pre-flight checks passed${NC}"
}

# Backup current deployment state
backup_current_state() {
    echo -e "${YELLOW}Creating backup of current state...${NC}"
    
    BACKUP_DIR="./backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    case $DEPLOYMENT_TYPE in
        blue-green|canary)
            # Export Kubernetes resources
            kubectl get deployment,service,configmap,ingress -n "$NAMESPACE" -o yaml > "$BACKUP_DIR/k8s-resources.yaml" || true
            echo -e "${GREEN}✓ Kubernetes resources backed up${NC}"
            ;;
        standard)
            # For Docker Compose, copy the config and any volumes if possible
            if [[ -f "docker-compose.prod.yml" ]]; then
                cp docker-compose.prod.yml "$BACKUP_DIR/"
                echo -e "${GREEN}✓ Docker Compose configuration backed up${NC}"
            fi
            ;;
    esac
    
    # Backup database if applicable
    if [[ -f "./scripts/backup-database.sh" ]]; then
        echo -e "${YELLOW}Backing up database...${NC}"
        ./scripts/backup-database.sh "$BACKUP_DIR/database.dump"
        echo -e "${GREEN}✓ Database backed up${NC}"
    fi
    
    # Save current version info
    if [[ -f "version.txt" ]]; then
        cp version.txt "$BACKUP_DIR/"
    else
        git rev-parse HEAD > "$BACKUP_DIR/git-commit.txt"
    fi
    
    echo -e "${GREEN}✓ Current state backed up to $BACKUP_DIR${NC}"
}

# Get deployment approval
get_deployment_approval() {
    echo -e "${YELLOW}Waiting for deployment approval...${NC}"
    
    if [[ -n "$CI" ]]; then
        # In CI environment, approval is managed by CI/CD system
        echo -e "${GREEN}✓ Running in CI - approval is managed by CI/CD system${NC}"
        return 0
    fi
    
    # Interactive approval for manual deployments
    echo -e "${YELLOW}You are about to deploy to ${BOLD}$ENVIRONMENT${NC} environment."
    echo -e "${YELLOW}Deployment type: ${BOLD}$DEPLOYMENT_TYPE${NC}"
    read -p "Do you want to continue? [y/N] " -n 1 -r REPLY
    echo    # Move to a new line
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deployment aborted by user${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Deployment approved${NC}"
}

# Execute pre-deployment tasks
execute_pre_deployment_tasks() {
    echo -e "${YELLOW}Executing pre-deployment tasks...${NC}"
    
    # Run custom pre-deployment script if specified
    if [[ -n "$PRE_DEPLOYMENT_SCRIPT" && -f "$PRE_DEPLOYMENT_SCRIPT" ]]; then
        echo -e "${YELLOW}Running pre-deployment script: $PRE_DEPLOYMENT_SCRIPT${NC}"
        chmod +x "$PRE_DEPLOYMENT_SCRIPT"
        if ! ./"$PRE_DEPLOYMENT_SCRIPT"; then
            echo -e "${RED}❌ Pre-deployment script failed${NC}"
            exit 1
        fi
    fi
    
    # Update deployment manifest with current timestamp
    DEPLOY_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    echo "$DEPLOY_TIMESTAMP" > "./.deploy-timestamp"
    
    echo -e "${GREEN}✓ Pre-deployment tasks completed${NC}"
}

# Execute blue/green deployment
execute_blue_green_deployment() {
    echo -e "${BLUE}${BOLD}Executing Blue/Green Deployment${NC}"
    
    # Get current deployment color (blue or green)
    CURRENT_COLOR=$(kubectl get service main-service -n "$NAMESPACE" \
        -o jsonpath='{.spec.selector.color}' 2>/dev/null || echo "blue")
    
    # Determine new deployment color
    if [[ "$CURRENT_COLOR" == "blue" ]]; then
        NEW_COLOR="green"
    else
        NEW_COLOR="blue"
    fi
    
    echo -e "${YELLOW}Current deployment: $CURRENT_COLOR, New deployment: $NEW_COLOR${NC}"
    
    # Deploy new version with the new color
    if ! ./scripts/blue-green-deploy.sh "$NEW_COLOR"; then
        echo -e "${RED}❌ Failed to deploy $NEW_COLOR environment${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ New $NEW_COLOR environment deployed${NC}"
    
    # Verify new deployment
    if ! ./scripts/verify-deployment.sh "$NEW_COLOR" "$VALIDATION_TIMEOUT"; then
        echo -e "${RED}❌ New deployment validation failed${NC}"
        return 1
    fi
    
    # Switch traffic to new color
    echo -e "${YELLOW}Switching traffic to $NEW_COLOR deployment...${NC}"
    if ! ./scripts/switch-traffic.sh "$NEW_COLOR"; then
        echo -e "${RED}❌ Failed to switch traffic to $NEW_COLOR${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Traffic switched to $NEW_COLOR deployment${NC}"
    
    # Optionally keep old deployment for quick rollback
    if [[ "$AUTO_ROLLBACK" == "true" ]]; then
        echo -e "${YELLOW}Keeping $CURRENT_COLOR deployment for possible rollback${NC}"
    else
        echo -e "${YELLOW}Removing old $CURRENT_COLOR deployment...${NC}"
        ./scripts/remove-deployment.sh "$CURRENT_COLOR" || true
    fi
    
    return 0
}

# Execute canary deployment
execute_canary_deployment() {
    echo -e "${BLUE}${BOLD}Executing Canary Deployment${NC}"
    
    # Initial canary deployment - small percentage
    echo -e "${YELLOW}Deploying canary with 10% traffic...${NC}"
    ./scripts/canary-deploy.sh "10"
    
    # Verify canary deployment
    if ! ./scripts/verify-deployment.sh "canary" 120; then
        echo -e "${RED}❌ Canary deployment validation failed${NC}"
        echo -e "${YELLOW}Rolling back canary...${NC}"
        ./scripts/remove-canary.sh
        return 1
    fi
    
    # Increase canary traffic gradually
    for percentage in 30 50 80 100; do
        echo -e "${YELLOW}Increasing canary traffic to $percentage%...${NC}"
        
        ./scripts/canary-deploy.sh "$percentage"
        
        # Allow time for traffic shift to stabilize
        echo -e "${YELLOW}Waiting for traffic stabilization...${NC}"
        sleep 30
        
        # Verify deployment at new traffic percentage
        if ! ./scripts/verify-deployment.sh "canary" 60; then
            echo -e "${RED}❌ Canary deployment failed at $percentage% traffic${NC}"
            echo -e "${YELLOW}Rolling back to previous state...${NC}"
            ./scripts/remove-canary.sh
            return 1
        fi
        
        echo -e "${GREEN}✓ Canary stable at $percentage% traffic${NC}"
    done
    
    # Complete deployment - remove old version
    echo -e "${YELLOW}Completing canary deployment...${NC}"
    ./scripts/finalize-canary.sh
    
    return 0
}

# Execute standard deployment
execute_standard_deployment() {
    echo -e "${BLUE}${BOLD}Executing Standard Deployment${NC}"
    
    # Use the existing deploy-production.sh with added parameters
    if ! ./deploy-production.sh --environment "$ENVIRONMENT" --non-interactive; then
        echo -e "${RED}❌ Standard deployment failed${NC}"
        return 1
    fi
    
    return 0
}

# Run automated tests
run_automated_tests() {
    echo -e "${YELLOW}Running automated tests...${NC}"
    
    # Run tests based on environment
    case $ENVIRONMENT in
        production)
            # Run smoke tests only for production
            if ! ./scripts/run-tests.sh --smoke; then
                echo -e "${RED}❌ Smoke tests failed${NC}"
                exit 1
            fi
            ;;
        *)
            # Run full test suite for non-production
            if ! ./scripts/run-tests.sh --all; then
                echo -e "${RED}❌ Tests failed${NC}"
                exit 1
            fi
            ;;
    esac
    
    echo -e "${GREEN}✓ All tests passed${NC}"
}

# Execute post-deployment verification
execute_post_deployment_verification() {
    echo -e "${YELLOW}Running post-deployment verification...${NC}"
    
    # Wait for deployment to stabilize
    echo -e "${YELLOW}Waiting for deployment to stabilize...${NC}"
    sleep 30
    
    # Check application health
    echo -e "${YELLOW}Checking application health...${NC}"
    
    # Determine endpoint based on deployment type
    local HEALTH_ENDPOINT
    case $DEPLOYMENT_TYPE in
        blue-green)
            SERVICE_IP=$(kubectl get svc -n "$NAMESPACE" -l "app=watsonx-code-assistant,color=$NEW_COLOR" \
                -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
            HEALTH_ENDPOINT="http://$SERVICE_IP/health"
            ;;
        canary)
            SERVICE_IP=$(kubectl get svc -n "$NAMESPACE" -l "app=watsonx-code-assistant,version=canary" \
                -o jsonpath="{.items[0].status.loadBalancer.ingress[0].ip}")
            HEALTH_ENDPOINT="http://$SERVICE_IP/health"
            ;;
        *)
            HEALTH_ENDPOINT="http://localhost/health"
            ;;
    esac
    
    # Check if application is responding
    local attempts=0
    local max_attempts=10
    
    while [[ $attempts -lt $max_attempts ]]; do
        if curl -s -o /dev/null -w "%{http_code}" "$HEALTH_ENDPOINT" | grep -q "200"; then
            echo -e "${GREEN}✓ Application is healthy${NC}"
            break
        else
            echo -e "${YELLOW}Attempt $((attempts+1))/$max_attempts: Application is not ready yet...${NC}"
            attempts=$((attempts+1))
            sleep 15
            
            if [[ $attempts -eq $max_attempts ]]; then
                echo -e "${RED}❌ Application health check failed after $max_attempts attempts${NC}"
                return 1
            fi
        fi
    done
    
    # Run integration tests against deployed application
    if [[ -f "./scripts/integration-tests.sh" ]]; then
        echo -e "${YELLOW}Running integration tests...${NC}"
        if ! ./scripts/integration-tests.sh "$HEALTH_ENDPOINT"; then
            echo -e "${RED}❌ Integration tests failed${NC}"
            return 1
        fi
    fi
    
    # Check for error rate in logs
    echo -e "${YELLOW}Checking error rate...${NC}"
    if [[ "$DEPLOYMENT_TYPE" == "blue-green" || "$DEPLOYMENT_TYPE" == "canary" ]]; then
        # For Kubernetes, check pod logs
        ERRORS=$(kubectl logs -n "$NAMESPACE" -l "app=watsonx-code-assistant" --since=5m | grep -i "error" | wc -l)
        
        if [[ $ERRORS -gt 10 ]]; then
            echo -e "${RED}❌ High error rate detected: $ERRORS errors in the last 5 minutes${NC}"
            return 1
        fi
    else
        # For Docker Compose, check container logs
        ERRORS=$(docker-compose -f docker-compose.prod.yml logs --tail=50 watsonx 2>&1 | grep -i "error" | wc -l)
        
        if [[ $ERRORS -gt 10 ]]; then
            echo -e "${RED}❌ High error rate detected: $ERRORS errors in recent logs${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ Error rate is acceptable${NC}"
    
    # Run any post-deployment scripts
    if [[ -n "$POST_DEPLOYMENT_SCRIPT" && -f "$POST_DEPLOYMENT_SCRIPT" ]]; then
        echo -e "${YELLOW}Running post-deployment script: $POST_DEPLOYMENT_SCRIPT${NC}"
        chmod +x "$POST_DEPLOYMENT_SCRIPT"
        if ! ./"$POST_DEPLOYMENT_SCRIPT"; then
            echo -e "${RED}❌ Post-deployment script failed${NC}"
            return 1
        fi
    fi
    
    echo -e "${GREEN}✓ Post-deployment verification completed successfully${NC}"
    return 0
}

# Execute rollback
execute_rollback() {
    echo -e "${YELLOW}Executing rollback...${NC}"
    
    case $DEPLOYMENT_TYPE in
        blue-green)
            echo -e "${YELLOW}Rolling back to previous color...${NC}"
            if ! ./scripts/switch-traffic.sh "$CURRENT_COLOR"; then
                echo -e "${RED}❌ Failed to switch traffic back to $CURRENT_COLOR${NC}"
                return 1
            fi
            echo -e "${GREEN}✓ Traffic switched back to $CURRENT_COLOR deployment${NC}"
            ;;
        canary)
            echo -e "${YELLOW}Removing canary deployment...${NC}"
            if ! ./scripts/remove-canary.sh; then
                echo -e "${RED}❌ Failed to remove canary deployment${NC}"
                return 1
            fi
            echo -e "${GREEN}✓ Canary deployment removed${NC}"
            ;;
        *)
            echo -e "${YELLOW}Restoring from backup...${NC}"
            LATEST_BACKUP=$(find ./backups -type d | sort | tail -n 1)
            if [[ -n "$LATEST_BACKUP" ]]; then
                echo -e "${YELLOW}Restoring from $LATEST_BACKUP...${NC}"
                
                # Restore Docker Compose config if it exists
                if [[ -f "$LATEST_BACKUP/docker-compose.prod.yml" ]]; then
                    cp "$LATEST_BACKUP/docker-compose.prod.yml" ./
                    docker-compose -f docker-compose.prod.yml down
                    docker-compose -f docker-compose.prod.yml up -d
                fi
                
                # Restore database if backup exists
                if [[ -f "$LATEST_BACKUP/database.dump" && -f "./scripts/restore-database.sh" ]]; then
                    ./scripts/restore-database.sh "$LATEST_BACKUP/database.dump"
                fi
                
                echo -e "${GREEN}✓ Restored from backup${NC}"
            else
                echo -e "${RED}❌ No backup found for rollback${NC}"
                return 1
            fi
            ;;
    esac
    
    echo -e "${GREEN}✓ Rollback completed${NC}"
    return 0
}

# Finalize deployment
finalize_deployment() {
    echo -e "${YELLOW}Finalizing deployment...${NC}"
    
    # Record deployment info
    DEPLOY_INFO="./deployments/$(date +%Y%m%d-%H%M%S).json"
    mkdir -p ./deployments
    
    cat > "$DEPLOY_INFO" <<EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "environment": "$ENVIRONMENT",
    "deployment_type": "$DEPLOYMENT_TYPE",
    "version": "$(cat version.txt 2>/dev/null || git rev-parse HEAD)",
    "deployer": "$(whoami)@$(hostname)"
}
EOF
    
    echo -e "${GREEN}✓ Deployment information recorded${NC}"
    
    # Clean up old backups if needed
    BACKUP_COUNT=$(find ./backups -maxdepth 1 -type d | wc -l)
    if [[ $BACKUP_COUNT -gt 5 ]]; then
        echo -e "${YELLOW}Cleaning up old backups...${NC}"
        find ./backups -maxdepth 1 -type d | sort | head -n -5 | xargs rm -rf
        echo -e "${GREEN}✓ Old backups cleaned up${NC}"
    fi
}

# Send notification
send_notification() {
    local STATUS=$1
    local MESSAGE=$2
    
    if [[ -z "$NOTIFICATION_URL" ]]; then
        return 0
    fi
    
    echo -e "${YELLOW}Sending deployment notification...${NC}"
    
    # Prepare notification payload
    local PAYLOAD
    PAYLOAD=$(cat <<EOF
{
    "status": "$STATUS",
    "environment": "$ENVIRONMENT",
    "deployment_type": "$DEPLOYMENT_TYPE",
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "message": "$MESSAGE",
    "deployer": "$(whoami)@$(hostname)"
}
EOF
)
    
    # Send notification
    if ! curl -s -X POST -H "Content-Type: application/json" -d "$PAYLOAD" "$NOTIFICATION_URL"; then
        echo -e "${YELLOW}⚠️ Failed to send notification${NC}"
    else
        echo -e "${GREEN}✓ Notification sent${NC}"
    fi
}

# Run the main function
main "$@"

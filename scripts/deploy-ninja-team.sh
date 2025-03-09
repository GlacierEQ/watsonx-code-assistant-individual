#!/bin/bash
# Advanced Ninja Build Team Deployment System
# Deploys a distributed, recursive build system across multiple hosts

set -eo pipefail

# Color formatting
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration variables
TEAM_CONFIG=${TEAM_CONFIG:-"./ninja-team-config.json"}
HOSTS_FILE=${HOSTS_FILE:-"./ninja-hosts.txt"}
SSH_KEY=${SSH_KEY:-"~/.ssh/id_rsa"}
RECURSIVE_DEPTH=${RECURSIVE_DEPTH:-3}
BUILD_MODE=${BUILD_MODE:-"recursive"}
LOG_DIR=${LOG_DIR:-"./logs/ninja-team"}
MAX_AGENTS=${MAX_AGENTS:-16}
SYNC_STRATEGY=${SYNC_STRATEGY:-"rsync"}
CENTRAL_CACHE=${CENTRAL_CACHE:-"/tmp/ninja-cache"}
CONNECTION_TIMEOUT=${CONNECTION_TIMEOUT:-5}
PARALLEL_DEPLOY=${PARALLEL_DEPLOY:-"true"}

echo -e "${BLUE}${BOLD}==================================================================${NC}"
echo -e "${BLUE}${BOLD}     Advanced Ninja Build Team - Recursive Deployment System      ${NC}"
echo -e "${BLUE}${BOLD}==================================================================${NC}"

# Create log directory
mkdir -p "$LOG_DIR"

# Log message to file and stdout
log() {
    local level=$1
    local message=$2
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${timestamp} [${level}] ${message}" | tee -a "${LOG_DIR}/deployment.log"
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config=*)
                TEAM_CONFIG="${1#*=}"
                ;;
            --hosts=*)
                HOSTS_FILE="${1#*=}"
                ;;
            --depth=*)
                RECURSIVE_DEPTH="${1#*=}"
                ;;
            --mode=*)
                BUILD_MODE="${1#*=}"
                ;;
            --max-agents=*)
                MAX_AGENTS="${1#*=}"
                ;;
            --sync=*)
                SYNC_STRATEGY="${1#*=}"
                ;;
            --cache=*)
                CENTRAL_CACHE="${1#*=}"
                ;;
            --timeout=*)
                CONNECTION_TIMEOUT="${1#*=}"
                ;;
            --sequential)
                PARALLEL_DEPLOY="false"
                ;;
            --help)
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --config=FILE            Team configuration file"
                echo "  --hosts=FILE             Hosts file listing build agents"
                echo "  --depth=N                Recursive deployment depth (default: 3)"
                echo "  --mode=MODE              Build mode (single, distributed, recursive, cloud)"
                echo "  --max-agents=N           Maximum number of agents to deploy (default: 16)"
                echo "  --sync=STRATEGY          Sync strategy (rsync, git, s3)"
                echo "  --cache=PATH             Central cache directory"
                echo "  --timeout=SECONDS        Host connection timeout"
                echo "  --sequential             Deploy agents sequentially, not in parallel"
                echo "  --help                   Show this help message"
                exit 0
                ;;
            *)
                log "ERROR" "Unknown option: $1"
                exit 1
                ;;
        esac
        shift
    done
}

# Validate configuration
validate_config() {
    log "INFO" "Validating configuration..."
    
    # Check if config file exists
    if [ ! -f "$TEAM_CONFIG" ]; then
        log "WARN" "Config file $TEAM_CONFIG not found, generating default configuration"
        generate_default_config
    else
        log "INFO" "Using team configuration: $TEAM_CONFIG"
    fi
    
    # Check if hosts file exists
    if [ ! -f "$HOSTS_FILE" ]; then
        log "ERROR" "Hosts file $HOSTS_FILE not found"
        
        # Try to generate a default hosts file if none exists
        if [ -f "/etc/hosts" ]; then
            log "INFO" "Generating default hosts file from /etc/hosts"
            grep -v "^#" /etc/hosts | grep -v "^$" | grep -v "localhost" | awk '{print $1}' > "$HOSTS_FILE"
        else
            # Create an empty hosts file with just localhost
            echo "localhost 8374" > "$HOSTS_FILE"
        fi
        
        log "WARN" "Created hosts file with local host only: $HOSTS_FILE"
    fi
    
    # Validate mode
    case $BUILD_MODE in
        single|distributed|recursive|cloud)
            log "INFO" "Build mode: $BUILD_MODE"
            ;;
        *)
            log "ERROR" "Invalid build mode: $BUILD_MODE"
            log "ERROR" "Valid options are: single, distributed, recursive, cloud"
            exit 1
            ;;
    esac
    
    # Validate recursive depth
    if ! [[ "$RECURSIVE_DEPTH" =~ ^[0-9]+$ ]]; then
        log "ERROR" "Invalid recursive depth: $RECURSIVE_DEPTH"
        exit 1
    elif [ "$RECURSIVE_DEPTH" -gt 5 ]; then
        log "WARN" "Very high recursive depth ($RECURSIVE_DEPTH) may cause excessive network traffic"
    fi
    
    log "INFO" "Configuration validated successfully"
}

# Generate default configuration file
generate_default_config() {
    log "INFO" "Generating default team configuration"
    
    cat > "$TEAM_CONFIG" << EOF
{
    "team_name": "watsonx-ninja-team",
    "team_version": "1.0.0",
    "max_parallel_jobs": $(nproc),
    "cache_enabled": true,
    "cache_dir": "$CENTRAL_CACHE",
    "recursive_depth": $RECURSIVE_DEPTH,
    "heartbeat_interval": 5,
    "optimization_strategy": "balanced",
    "cc_launcher": "ccache",
    "remote_execution": {
        "enabled": true,
        "protocol": "ssh",
        "timeout": $CONNECTION_TIMEOUT,
        "retry_attempts": 3
    },
    "advanced_features": {
        "distributed_cache": true,
        "predictive_scheduling": true,
        "auto_recovery": true,
        "load_balancing": true,
        "artifact_compression": true
    },
    "logging": {
        "level": "INFO",
        "file": "$LOG_DIR/ninja-team.log",
        "metrics_enabled": true
    }
}
EOF
    
    log "INFO" "Default configuration generated at $TEAM_CONFIG"
}

# Parse hosts file
parse_hosts() {
    log "INFO" "Parsing hosts file: $HOSTS_FILE"
    
    # Array to store hosts
    declare -a HOSTS
    declare -a PORTS
    HOST_COUNT=0
    
    # Read hosts file line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        
        # Extract host and port
        host=$(echo "$line" | awk '{print $1}')
        port=$(echo "$line" | awk '{print $2}')
        
        # Use default port if not specified
        if [ -z "$port" ]; then
            port=8374
        fi
        
        # Add to arrays
        HOSTS+=("$host")
        PORTS+=("$port")
        HOST_COUNT=$((HOST_COUNT + 1))
        
        # Check if we've reached the maximum number of agents
        if [ "$HOST_COUNT" -ge "$MAX_AGENTS" ]; then
            log "WARN" "Maximum number of agents reached ($MAX_AGENTS), ignoring remaining hosts"
            break
        fi
    done < "$HOSTS_FILE"
    
    log "INFO" "Found $HOST_COUNT build agents in hosts file"
    
    # Export arrays for later use
    export HOSTS
    export PORTS
    export HOST_COUNT
}

# Check SSH connections to hosts
check_connections() {
    log "INFO" "Checking connections to build agents..."
    
    # Track valid hosts
    declare -a VALID_HOSTS
    declare -a VALID_PORTS
    VALID_COUNT=0
    
    for i in $(seq 0 $((HOST_COUNT - 1))); do
        host=${HOSTS[$i]}
        port=${PORTS[$i]}
        
        # Skip localhost - always assumed to be available
        if [ "$host" == "localhost" ] || [ "$host" == "127.0.0.1" ]; then
            log "INFO" "✅ Local agent available (localhost:$port)"
            VALID_HOSTS+=("$host")
            VALID_PORTS+=("$port")
            VALID_COUNT=$((VALID_COUNT + 1))
            continue
        fi
        
        # Check if we can SSH into the host
        if ssh -i "$SSH_KEY" -o ConnectTimeout="$CONNECTION_TIMEOUT" -o BatchMode=yes -o StrictHostKeyChecking=no "$host" echo 2>/dev/null; then
            log "INFO" "✅ Host $host:$port is reachable"
            VALID_HOSTS+=("$host")
            VALID_PORTS+=("$port")
            VALID_COUNT=$((VALID_COUNT + 1))
        else
            log "WARN" "❌ Cannot connect to host $host:$port - skipping"
        fi
    done
    
    log "INFO" "Connection check complete: $VALID_COUNT/$HOST_COUNT hosts are valid"
    
    # Update arrays with valid hosts
    HOSTS=("${VALID_HOSTS[@]}")
    PORTS=("${VALID_PORTS[@]}")
    HOST_COUNT=$VALID_COUNT
    
    # Check if we have any valid remote hosts for distributed mode
    if [ "$BUILD_MODE" != "single" ] && [ "$VALID_COUNT" -le 1 ]; then
        log "WARN" "Not enough valid remote hosts for $BUILD_MODE mode"
        log "WARN" "Falling back to single mode"
        BUILD_MODE="single"
    fi
}

# Deploy agent software to remote hosts
deploy_agents() {
    log "INFO" "Deploying Ninja agents to $HOST_COUNT hosts..."
    
    # Create temporary directory for deployment files
    DEPLOY_DIR=$(mktemp -d -t ninja-deploy-XXXXXXXX)
    
    # Generate agent installation package
    log "INFO" "Generating agent installation package"
    
    # Create agent directory structure
    mkdir -p "$DEPLOY_DIR/scripts"
    mkdir -p "$DEPLOY_DIR/config"
    
    # Copy required files to deployment directory
    cp "$(dirname "$0")/ninja-team.py" "$DEPLOY_DIR/scripts/"
    cp "$TEAM_CONFIG" "$DEPLOY_DIR/config/"
    
    # Create agent setup script
    cat > "$DEPLOY_DIR/setup.sh" << 'EOF'
#!/bin/bash
# Agent setup script
set -e

AGENT_HOME="$HOME/.ninja-agent"
CONFIG_DIR="$AGENT_HOME/config"
SCRIPTS_DIR="$AGENT_HOME/scripts"
LOG_DIR="$AGENT_HOME/logs"

# Create directory structure
mkdir -p "$CONFIG_DIR" "$SCRIPTS_DIR" "$LOG_DIR"

# Copy files from deployment package
cp -f config/* "$CONFIG_DIR/"
cp -f scripts/* "$SCRIPTS_DIR/"

# Make scripts executable
chmod +x "$SCRIPTS_DIR/"*.py

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Python 3 not found, attempting to install..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y python3 python3-pip
    elif command -v yum &> /dev/null; then
        sudo yum install -y python3 python3-pip
    elif command -v brew &> /dev/null; then
        brew install python
    else
        echo "ERROR: Could not install Python 3. Please install manually."
        exit 1
    fi
fi

# Install required Python packages
pip3 install --user psutil colorama

# Create agent service file
cat > "$AGENT_HOME/agent-service.sh" << 'EOFS'
#!/bin/bash
# Ninja build agent service
exec python3 "$SCRIPTS_DIR/ninja-team.py" --mode agent --config "$CONFIG_DIR/ninja-team-config.json" "$@"
EOFS

chmod +x "$AGENT_HOME/agent-service.sh"

# Add to path if not already there
if ! grep -q "$AGENT_HOME" "$HOME/.bashrc"; then
    echo "export PATH=\"\$PATH:$AGENT_HOME\"" >> "$HOME/.bashrc"
fi

echo "Ninja build agent installed successfully in $AGENT_HOME"
EOF
    
    chmod +x "$DEPLOY_DIR/setup.sh"
    
    # Deploy to all hosts
    for i in $(seq 0 $((HOST_COUNT - 1))); do
        host=${HOSTS[$i]}
        
        # Skip localhost - already has the agent software
        if [ "$host" == "localhost" ] || [ "$host" == "127.0.0.1" ]; then
            log "INFO" "✓ Local agent already has required software"
            continue
        fi
        
        # Create deployment function for this host
        deploy_to_host() {
            local host=$1
            log "INFO" "Deploying to $host..."
            
            # Ensure .ssh directory exists on remote host
            ssh -i "$SSH_KEY" -o BatchMode=yes "$host" "mkdir -p ~/.ssh" || true
            
            # Create deployment directory on remote host
            remote_dir="/tmp/ninja-agent-deploy-$(date +%s)"
            ssh -i "$SSH_KEY" -o BatchMode=yes "$host" "mkdir -p $remote_dir" || {
                log "ERROR" "Failed to create directory on $host"
                return 1
            }
            
            # Copy deployment files
            rsync -a -e "ssh -i $SSH_KEY -o BatchMode=yes" "$DEPLOY_DIR/" "$host:$remote_dir/" || {
                log "ERROR" "Failed to copy files to $host"
                return 1
            }
            
            # Run setup script on remote host
            ssh -i "$SSH_KEY" -o BatchMode=yes "$host" "cd $remote_dir && ./setup.sh" || {
                log "ERROR" "Failed to run setup script on $host"
                return 1
            }
            
            # Start agent on remote host
            ssh -i "$SSH_KEY" -o BatchMode=yes "$host" \
                "nohup ~/.ninja-agent/agent-service.sh --host $host --port ${PORTS[$i]} > ~/.ninja-agent/logs/agent.log 2>&1 &" || {
                log "ERROR" "Failed to start agent on $host"
                return 1
            }
            
            # Clean up
            ssh -i "$SSH_KEY" -o BatchMode=yes "$host" "rm -rf $remote_dir" || true
            
            log "INFO" "✅ Successfully deployed and started agent on $host"
            return 0
        }
        
        # Deploy in parallel or sequentially
        if [ "$PARALLEL_DEPLOY" = "true" ]; then
            deploy_to_host "$host" &
        else
            deploy_to_host "$host"
        fi
    done
    
    # Wait for parallel deployments to complete
    if [ "$PARALLEL_DEPLOY" = "true" ]; then
        wait
    fi
    
    # Clean up temporary directory
    rm -rf "$DEPLOY_DIR"
    
    log "INFO" "Agent deployment complete"
}

# Set up distributed cache system
setup_distributed_cache() {
    log "INFO" "Setting up distributed build cache..."
    
    # Create cache directory
    mkdir -p "$CENTRAL_CACHE"
    
    # Configure ccache
    CCACHE_DIR="$CENTRAL_CACHE/ccache"
    mkdir -p "$CCACHE_DIR"
    
    # Set permissions to allow sharing
    chmod 777 "$CENTRAL_CACHE" "$CCACHE_DIR"
    
    # Configure ccache size and settings
    ccache -o max_size=20G
    ccache -o compression=true
    ccache -o compression_level=9
    ccache -o cache_dir="$CCACHE_DIR"
    
    log "INFO" "Distributed cache set up at $CENTRAL_CACHE"
}

# Launch master controller
launch_controller() {
    log "INFO" "Launching Ninja build team controller..."
    
    # Generate hosts file for ninja-team.py
    NINJA_HOSTS_FILE="$LOG_DIR/ninja-hosts-generated.txt"
    
    # Create hosts file
    rm -f "$NINJA_HOSTS_FILE"
    for i in $(seq 0 $((HOST_COUNT - 1))); do
        echo "${HOSTS[$i]} ${PORTS[$i]}" >> "$NINJA_HOSTS_FILE"
    done
    
    log "INFO" "Generated hosts file with $HOST_COUNT entries"
    
    # Launch controller with appropriate parameters
    log "INFO" "Starting ninja-team controller in $BUILD_MODE mode with recursive depth $RECURSIVE_DEPTH"
    
    # Set environment variables
    export PYTHONUNBUFFERED=1
    export NINJA_CACHE_DIR="$CENTRAL_CACHE"
    export NINJA_TEAM_CONFIG="$TEAM_CONFIG"
    
    # Command to run
    CONTROLLER_CMD="python3 $(dirname "$0")/ninja-team.py \
        --mode $BUILD_MODE \
        --config $TEAM_CONFIG \
        --hosts $NINJA_HOSTS_FILE \
        --recursive-depth $RECURSIVE_DEPTH \
        --verbose"
    
    log "INFO" "Executing: $CONTROLLER_CMD"
    
    # Run controller
    if [ "$BUILD_MODE" = "recursive" ]; then
        log "INFO" "Starting recursive controller with depth $RECURSIVE_DEPTH"
        $CONTROLLER_CMD
    else
        log "INFO" "Starting controller in $BUILD_MODE mode"
        $CONTROLLER_CMD
    fi
    
    # Check exit status
    if [ $? -eq 0 ]; then
        log "INFO" "✅ Ninja build team controller completed successfully"
    else
        log "ERROR" "❌ Ninja build team controller failed with exit code $?"
        return 1
    fi
}

# Clean up after completion
cleanup() {
    log "INFO" "Cleaning up..."
    
    # Stop remote agents if needed
    if [ "$BUILD_MODE" != "single" ] && [ "$1" == "success" ]; then
        log "INFO" "Stopping remote agents..."
        
        for i in $(seq 0 $((HOST_COUNT - 1))); do
            host=${HOSTS[$i]}
            
            # Skip localhost
            if [ "$host" == "localhost" ] || [ "$host" == "127.0.0.1" ]; then
                continue
            fi
            
            # Stop agent
            ssh -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=3 "$host" \
                "pkill -f 'ninja-team.py --mode agent' || true" &
        done
        
        # Wait for all stop commands to complete
        wait
    fi
    
    log "INFO" "Cleanup complete"
}

# Main function
main() {
    # Parse command line arguments
    parse_args "$@"
    
    # Validate configuration
    validate_config
    
    # Parse hosts file
    parse_hosts
    
    # Check connections to hosts
    check_connections
    
    # Deploy agents to remote hosts
    if [ "$BUILD_MODE" != "single" ]; then
        deploy_agents
    fi
    
    # Set up distributed cache
    if [ "$BUILD_MODE" != "single" ]; then
        setup_distributed_cache
    fi
    
    # Launch master controller
    if launch_controller; then
        cleanup "success"
        log "INFO" "🚀 Ninja build team deployment completed successfully"
        return 0
    else
        cleanup "failure"
        log "ERROR" "❌ Ninja build team deployment failed"
        return 1
    fi
}

# Run main function with all arguments
main "$@"

#
# Deploy-Ninjas.ps1
# PowerShell script for deploying ninja build team on Windows
# 
# Usage:
#   .\Deploy-Ninjas.ps1             - Deploy basic ninja team
#   .\Deploy-Ninjas.ps1 -Full       - Deploy full recursive ninja team
#   .\Deploy-Ninjas.ps1 -Clean      - Clean ninja cache before deploying
#   .\Deploy-Ninjas.ps1 -Help       - Show help information

param (
    [switch]$Full,
    [switch]$Clean,
    [switch]$Help,
    [int]$Depth = 3,
    [string]$Mode = "recursive",
    [string]$Config = "scripts\ninja-team-config.json",
    [string]$HostsFile = "ninja-hosts.txt"
)

# Output formatting
function WriteColor([string]$text, [string]$color = "White") {
    Write-Host $text -ForegroundColor $color
}

# Banner
WriteColor "`n========================================================" "Cyan"
WriteColor "           NINJA BUILD TEAM DEPLOYMENT SYSTEM           " "Cyan" 
WriteColor "                      [PowerShell]                      " "Cyan"
WriteColor "========================================================`n" "Cyan"

# Show help if requested
if ($Help) {
    WriteColor "Usage: .\Deploy-Ninjas.ps1 [options]" "Yellow"
    WriteColor "`nOptions:"
    WriteColor "  -Full        Deploy full recursive ninja team with all features"
    WriteColor "  -Clean       Clean ninja cache before deploying"
    WriteColor "  -Depth N     Set recursive deployment depth (default: 3)"
    WriteColor "  -Mode X      Set deployment mode (default: recursive)"
    WriteColor "  -Config X    Specify config file path"
    WriteColor "  -HostsFile X Specify hosts file path"
    WriteColor "  -Help        Show this help message"
    exit 0
}

# Check prerequisites
WriteColor "Checking prerequisites..." "Yellow"

# Check for Python
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    WriteColor "[ERROR] Python not found. Please install Python 3.x and try again." "Red"
    exit 1
}

# Check for Ninja
if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
    WriteColor "[WARNING] Ninja not found in PATH. Will try to install via pip..." "Yellow"
    python -m pip install ninja
}

# Create default hosts file if it doesn't exist
if (-not (Test-Path $HostsFile)) {
    WriteColor "[INFO] Creating default $HostsFile file..." "Yellow"
    @"
# Ninja Build Team - Host Configuration
# Format: hostname port [capabilities]

# Local host (always available)
localhost 8374

# Add remote build hosts below
# hostname1 8374
# hostname2 8374

# For machines with special capabilities, add them after the port
# gpu-server1 8374 gpu,cuda=11.4
# build-server5 8374 high-mem,fast-storage
"@ | Set-Content $HostsFile
}

# Create logs directory
if (-not (Test-Path "logs\ninja-team")) {
    New-Item -Path "logs\ninja-team" -ItemType Directory -Force | Out-Null
}

# Clean ninja cache if requested
if ($Clean) {
    WriteColor "[INFO] Cleaning ninja cache..." "Yellow"
    if (Test-Path ".ninja_cache") {
        Remove-Item -Recurse -Force ".ninja_cache"
    }
    WriteColor "[INFO] Ninja cache cleaned" "Green"
}

# Handle full deployment mode
if ($Full) {
    WriteColor "[INFO] Deploying full recursive ninja team..." "Yellow"
    
    # Check if WSL is available for bash script execution
    $wslEnabled = $false
    try {
        # Try to execute a simple command in WSL
        $wslOutput = wsl ls 2>&1
        $wslEnabled = $LASTEXITCODE -eq 0
    }
    catch {
        $wslEnabled = $false
    }
    
    if ($wslEnabled) {
        WriteColor "[INFO] Using WSL to run full deployment script..." "Yellow"
        # Convert Windows path to WSL path
        $currentDir = (Get-Location).Path.Replace("\", "/").Replace("C:", "/mnt/c")
        
        # Execute the bash script through WSL
        wsl cd $currentDir "&&" chmod +x ./scripts/deploy-ninja-team.sh "&&" ./scripts/deploy-ninja-team.sh --config=$Config --hosts=$HostsFile --depth=$Depth --mode=$Mode
        
        if ($LASTEXITCODE -eq 0) {
            WriteColor "`n===============================================" "Green"
            WriteColor "        NINJA DEPLOYMENT SUCCESSFUL!          " "Green"
            WriteColor "===============================================`n" "Green"
        }
        else {
            WriteColor "[ERROR] Full ninja team deployment failed with code $LASTEXITCODE" "Red"
        }
    }
    else {
        WriteColor "[WARNING] WSL not available. Full deployment requires WSL or Linux." "Yellow"
        WriteColor "[INFO] Falling back to basic deployment..." "Yellow"
        # Fall back to basic deployment
        $Full = $false
    }
}

# Basic deployment (if not full or if full deployment wasn't possible)
if (-not $Full) {
    WriteColor "[INFO] Deploying ninja build team..." "Yellow"
    
    # Deploy using Python script directly
    $pythonArgs = @(
        "scripts\ninja-team.py",
        "--mode", $Mode,
        "--hosts", $HostsFile,
        "--recursive-depth", $Depth,
        "--config", $Config
    )
    
    if ($Clean) {
        $pythonArgs += "--clean"
    }
    
    # Add verbose flag
    $pythonArgs += "--verbose"
    
    # Execute the Python script
    & python $pythonArgs
    
    if ($LASTEXITCODE -eq 0) {
        WriteColor "`n===============================================" "Green"
        WriteColor "        NINJA DEPLOYMENT SUCCESSFUL!          " "Green"
        WriteColor "===============================================`n" "Green"
    }
    else {
        WriteColor "[ERROR] Ninja deployment failed with code $LASTEXITCODE" "Red"
        exit $LASTEXITCODE
    }
}

exit 0

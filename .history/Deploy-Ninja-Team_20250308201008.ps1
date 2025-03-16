#
# Deploy-Ninja-Team.ps1
# Universal Ninja Build Team Deployment Script
# Supports local, server, cloud, and container-based deployments
# 
# Usage:
#   .\Deploy-Ninja-Team.ps1 -Method <method> [options]
#   Methods: Local, Server, Container, Cloud, WSL

param (
    [Parameter(Position = 0)]
    [ValidateSet("Local", "Server", "Container", "Cloud", "WSL", "Docker", "AzureDevOps", "GitHub")]
    [string]$Method = "Local",
    
    [switch]$Clean,
    [switch]$Initialize,
    [switch]$Verbose,
    [string]$ConfigFile = "deploy-config.json",
    [string]$BuildDir = "build",
    [string]$HostsFile = "ninja-hosts.txt",
    [int]$RecursiveDepth = 3,
    [ValidateSet("single", "distributed", "recursive", "cloud")]
    [string]$Mode = "recursive",
    [string]$ContainerRegistry = "ghcr.io",
    [string]$ContainerImage = "watsonx-ninja:latest",
    [string]$CloudRegion = "us-east-1",
    [switch]$Help
)

# Output formatting
function WriteColor([string]$text, [string]$color = "White") {
    Write-Host $text -ForegroundColor $color
}

# Banner
WriteColor "`n========================================================" "Cyan"
WriteColor "           NINJA BUILD TEAM DEPLOYMENT SYSTEM           " "Cyan" 
WriteColor "                    [Universal Mode]                    " "Cyan"
WriteColor "========================================================`n" "Cyan"

# Show help if requested
if ($Help) {
    WriteColor "Universal Ninja Build Team Deployment" "Yellow"
    WriteColor "`nUsage: .\Deploy-Ninja-Team.ps1 -Method <method> [options]`n" "Yellow"
    
    WriteColor "Methods:" "White"
    WriteColor "  Local      - Deploy on local machine (default)" "White"
    WriteColor "  Server     - Deploy on remote server(s)" "White"
    WriteColor "  Container  - Deploy using Docker containers" "White"
    WriteColor "  Cloud      - Deploy to cloud infrastructure" "White"
    WriteColor "  WSL        - Deploy using Windows Subsystem for Linux" "White"
    WriteColor "  Docker     - Deploy using Docker Compose" "White"
    WriteColor "  AzureDevOps - Deploy using Azure DevOps pipelines" "White"
    WriteColor "  GitHub     - Deploy using GitHub Actions" "White"
    
    WriteColor "`nOptions:" "White"
    WriteColor "  -Clean         Clean build artifacts before deploying" "White"
    WriteColor "  -Initialize    Initialize build environment" "White"
    WriteColor "  -Verbose       Show verbose output" "White"
    WriteColor "  -ConfigFile    Specify deployment config file" "White"
    WriteColor "  -BuildDir      Specify build directory" "White"
    WriteColor "  -HostsFile     Specify hosts file for distributed builds" "White"
    WriteColor "  -RecursiveDepth Set depth for recursive builds" "White"
    WriteColor "  -Mode          Build mode (single, distributed, recursive, cloud)" "White"
    WriteColor "  -Help          Show this help message" "White"

    WriteColor "`nExamples:" "Green"
    WriteColor "  # Deploy locally" "Green"
    WriteColor "  .\Deploy-Ninja-Team.ps1 -Method Local -Initialize" "Green"
    WriteColor "`n  # Deploy using Docker" "Green"
    WriteColor "  .\Deploy-Ninja-Team.ps1 -Method Docker -ContainerImage my-image:latest" "Green"
    WriteColor "`n  # Deploy to cloud" "Green"
    WriteColor "  .\Deploy-Ninja-Team.ps1 -Method Cloud -CloudRegion eu-west-1" "Green"
    
    exit 0
}

# Load configuration if available
$config = @{}
if (Test-Path $ConfigFile) {
    WriteColor "[INFO] Loading configuration from $ConfigFile..." "Yellow"
    try {
        $configContent = Get-Content $ConfigFile -Raw | ConvertFrom-Json
        $config = $configContent
        WriteColor "[INFO] Configuration loaded successfully" "Green"
    }
    catch {
        WriteColor "[WARNING] Error loading configuration: $_" "Yellow"
        WriteColor "[WARNING] Using default configuration" "Yellow"
    }
}

# Check prerequisites based on deployment method
function Check-Prerequisites {
    WriteColor "[INFO] Checking prerequisites for $Method deployment..." "Yellow"
    
    # Common prerequisites
    if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
        WriteColor "[ERROR] Python not found. Please install Python 3.x and try again." "Red"
        exit 1
    }
    
    # Method-specific prerequisites
    switch ($Method) {
        "Local" {
            if (-not (Get-Command ninja -ErrorAction SilentlyContinue)) {
                WriteColor "[WARNING] Ninja not found in PATH. Will try to install via pip..." "Yellow"
                python -m pip install ninja
            }
        }
        "Container" {
            if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
                WriteColor "[ERROR] Docker not found. Please install Docker and try again." "Red"
                exit 1
            }
        }
        "Cloud" {
            # Check for cloud provider CLI tools
            if (-not ((Get-Command aws -ErrorAction SilentlyContinue) -or 
                       (Get-Command az -ErrorAction SilentlyContinue) -or
                       (Get-Command gcloud -ErrorAction SilentlyContinue))) {
                WriteColor "[WARNING] No cloud provider CLI tools found. You may need to install AWS CLI, Azure CLI, or Google Cloud SDK." "Yellow"
            }
        }
        "WSL" {
            try {
                $wslOutput = wsl --status 2>&1
                if ($LASTEXITCODE -ne 0) {
                    WriteColor "[ERROR] WSL not properly configured. Please run 'wsl --install' as administrator." "Red"
                    exit 1
                }
            }
            catch {
                WriteColor "[ERROR] WSL not available. Please install WSL and try again." "Red"
                exit 1
            }
        }
        "Docker" {
            if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue) -and 
                -not ((Get-Command docker -ErrorAction SilentlyContinue) -and (docker compose version 2>&1 | Out-Null; $?))) {
                WriteColor "[ERROR] Docker Compose not found. Please install Docker with Compose support and try again." "Red"
                exit 1
            }
        }
        "AzureDevOps" {
            if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
                WriteColor "[ERROR] Azure CLI not found. Please install Azure CLI and try again." "Red"
                exit 1
            }
        }
        "GitHub" {
            if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
                WriteColor "[WARNING] GitHub CLI not found. Installation will continue but some features may be limited." "Yellow"
            }
        }
    }
    
    WriteColor "[INFO] Prerequisites check completed" "Green"
}

# Initialize build environment
function Initialize-BuildEnvironment {
    WriteColor "[INFO] Initializing build environment for $Method deployment..." "Yellow"
    
    # Create build directory if it doesn't exist
    if (-not (Test-Path $BuildDir)) {
        New-Item -Path $BuildDir -ItemType Directory -Force | Out-Null
    }
    
    # Method-specific initialization
    switch ($Method) {
        "Local" {
            & "$PSScriptRoot\scripts\init-build-env.ps1" -BuildDir $BuildDir
        }
        "WSL" {
            $currentDir = (Get-Location).Path.Replace("\", "/").Replace("C:", "/mnt/c")
            wsl bash -c "mkdir -p $currentDir/scripts && chmod +x $currentDir/scripts/init-wsl-build.sh && $currentDir/scripts/init-wsl-build.sh $currentDir/$BuildDir"
        }
        "Container" {
            # Create a Docker volume for build artifacts
            docker volume create ninja-build-artifacts
            
            # Create a minimal Dockerfile if it doesn't exist
            if (-not (Test-Path "Dockerfile.ninja")) {
                @"
FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    python3 \
    python3-pip \
    ninja-build \
    ccache \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip3 install psutil colorama

# Working directory
WORKDIR /build

# Copy scripts
COPY scripts/ninja-team.py /usr/local/bin/
COPY scripts/ninja-team-config.json /etc/ninja-team/

# Set executable permissions
RUN chmod +x /usr/local/bin/ninja-team.py

# Entry point
ENTRYPOINT ["python3", "/usr/local/bin/ninja-team.py"]
CMD ["--help"]
"@ | Set-Content -Path "Dockerfile.ninja" -Encoding UTF8
                WriteColor "[INFO] Created Dockerfile.ninja" "Green"
            }
        }
        "Cloud" {
            # Create cloud deployment template
            $templateFile = "cloud-deploy-template.yaml"
            if (-not (Test-Path $templateFile)) {
                switch -Wildcard ($CloudRegion) {
                    "us-*" {
                        # AWS CloudFormation template
                        @"
AWSTemplateFormatVersion: '2010-09-09'
Description: 'Ninja Build Team Cloud Deployment'
Resources:
  NinjaBuildInstance:
    Type: AWS::EC2::Instance
    Properties:
      InstanceType: c5.large
      ImageId: ami-0c55b159cbfafe1f0 # Amazon Linux 2
      KeyName: my-key-pair
      SecurityGroups:
        - !Ref NinjaBuildSecurityGroup
      UserData:
        Fn::Base64: !Sub |
          #!/bin/bash -xe
          yum update -y
          yum install -y python3 python3-pip git
          pip3 install ninja
          mkdir -p /opt/ninja-build
          # Additional installation steps would go here
  
  NinjaBuildSecurityGroup:
    Type: AWS::EC2::SecurityGroup
    Properties:
      GroupDescription: Security group for Ninja Build Team
      SecurityGroupIngress:
        - CidrIp: 0.0.0.0/0
          IpProtocol: tcp
          FromPort: 22
          ToPort: 22
        - CidrIp: 0.0.0.0/0
          IpProtocol: tcp
          FromPort: 8374
          ToPort: 8374

Outputs:
  InstanceId:
    Description: ID of the EC2 instance
    Value: !Ref NinjaBuildInstance
  PublicDNS:
    Description: Public DNS of the EC2 instance
    Value: !GetAtt NinjaBuildInstance.PublicDnsName
"@ | Set-Content -Path $templateFile -Encoding UTF8
                    }
                    "eu-*" {
                        # Azure ARM template skeleton
                        @"
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vmName": {
      "type": "string",
      "defaultValue": "NinjaBuildVM"
    },
    "adminUsername": {
      "type": "string"
    },
    "adminPassword": {
      "type": "securestring"
    }
  },
  "resources": [
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2021-03-01",
      "name": "[parameters('vmName')]",
      "location": "[resourceGroup().location]",
      "properties": {
        "hardwareProfile": {
          "vmSize": "Standard_D2s_v3"
        },
        "osProfile": {
          "computerName": "[parameters('vmName')]",
          "adminUsername": "[parameters('adminUsername')]",
          "adminPassword": "[parameters('adminPassword')]"
        },
        "storageProfile": {
          "imageReference": {
            "publisher": "Canonical",
            "offer": "UbuntuServer",
            "sku": "18.04-LTS",
            "version": "latest"
          }
        },
        "networkProfile": {
          "networkInterfaces": []
        }
      }
    }
  ]
}
"@ | Set-Content -Path $templateFile -Encoding UTF8
                    }
                    default {
                        # Generic GCP deployment template
                        @"
resources:
- name: ninja-build-instance
  type: compute.v1.instance
  properties:
    zone: us-central1-a
    machineType: zones/us-central1-a/machineTypes/n1-standard-2
    disks:
    - deviceName: boot
      type: PERSISTENT
      boot: true
      autoDelete: true
      initializeParams:
        sourceImage: projects/debian-cloud/global/images/family/debian-10
    networkInterfaces:
    - network: global/networks/default
      accessConfigs:
      - name: External NAT
        type: ONE_TO_ONE_NAT
    metadata:
      items:
      - key: startup-script
        value: |
          #!/bin/bash
          apt-get update
          apt-get install -y python3 python3-pip git ninja-build
          pip3 install psutil colorama
          mkdir -p /opt/ninja-build
"@ | Set-Content -Path $templateFile -Encoding UTF8
                    }
                }
                WriteColor "[INFO] Created cloud deployment template: $templateFile" "Green"
            }
        }
        "Docker" {
            # Create Docker Compose file if it doesn't exist
            $composeFile = "docker-compose.ninja.yml"
            if (-not (Test-Path $composeFile)) {
                @"
version: '3.8'

services:
  ninja-build:
    build:
      context: .
      dockerfile: Dockerfile.ninja
    image: ${ContainerRegistry}/watsonx-ninja:latest
    volumes:
      - ./:/build
      - ninja-cache:/cache
    environment:
      - NINJA_CACHE_DIR=/cache
      - NINJA_TEAM_CONFIG=/etc/ninja-team/ninja-team-config.json
      - NINJA_TEAM_MODE=${Mode}
      - PYTHONUNBUFFERED=1
    command: ["--mode", "${Mode}", "--recursive-depth", "${RecursiveDepth}", "--verbose"]

  # Agent service for distributed builds
  ninja-agent:
    image: ${ContainerRegistry}/watsonx-ninja:latest
    deploy:
      replicas: 3
    volumes:
      - ninja-cache:/cache
    environment:
      - NINJA_CACHE_DIR=/cache
      - NINJA_TEAM_AGENT=true
    command: ["--mode", "agent", "--verbose"]
    depends_on:
      - ninja-build

volumes:
  ninja-cache:
"@ | Set-Content -Path $composeFile -Encoding UTF8
                WriteColor "[INFO] Created Docker Compose file: $composeFile" "Green"
            }
        }
        "AzureDevOps" {
            # Create Azure DevOps pipeline file
            $pipelineFile = "azure-pipelines-ninja.yml"
            if (-not (Test-Path $pipelineFile)) {
                @"
trigger:
  branches:
    include:
    - main
    - master
    - develop

pool:
  vmImage: 'ubuntu-latest'

variables:
  buildMode: '$Mode'
  recursiveDepth: '$RecursiveDepth'

steps:
- checkout: self
  fetchDepth: 1

- task: UsePythonVersion@0
  inputs:
    versionSpec: '3.x'
    addToPath: true

- script: |
    pip install ninja psutil colorama
    mkdir -p build
  displayName: 'Install dependencies'

- script: |
    python scripts/ninja-team.py --mode $(buildMode) --recursive-depth $(recursiveDepth) --build-dir build --verbose
  displayName: 'Run Ninja Build Team'

- task: PublishBuildArtifacts@1
  inputs:
    pathtoPublish: 'build'
    artifactName: 'ninja-build-output'
  displayName: 'Publish build artifacts'
"@ | Set-Content -Path $pipelineFile -Encoding UTF8
                WriteColor "[INFO] Created Azure DevOps pipeline: $pipelineFile" "Green"
            }
        }
        "GitHub" {
            # Create GitHub Actions workflow file
            $workflowDir = ".github/workflows"
            $workflowFile = "$workflowDir/ninja-build.yml"
            if (-not (Test-Path $workflowDir)) {
                New-Item -Path $workflowDir -ItemType Directory -Force | Out-Null
            }
            if (-not (Test-Path $workflowFile)) {
                @"
name: Ninja Build Team

on:
  push:
    branches: [ main, master, develop ]
  pull_request:
    branches: [ main, master ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python
      uses: actions/setup-python@v4
      with:
        python-version: '3.10'
    
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install ninja psutil colorama
        mkdir -p build
    
    - name: Run Ninja Build Team
      run: |
        python scripts/ninja-team.py --mode $Mode --recursive-depth $RecursiveDepth --build-dir build --verbose
    
    - name: Archive build artifacts
      uses: actions/upload-artifact@v3
      with:
        name: build-artifacts
        path: build/
"@ | Set-Content -Path $workflowFile -Encoding UTF8
                WriteColor "[INFO] Created GitHub Actions workflow: $workflowFile" "Green"
            }
        }
    }
    
    WriteColor "[INFO] Build environment initialized for $Method deployment" "Green"
}

# Clean build artifacts
function Clean-BuildArtifacts {
    if ($Clean) {
        WriteColor "[INFO] Cleaning build artifacts..." "Yellow"
        
        switch ($Method) {
            "Local" {
                if (Test-Path $BuildDir) {
                    Remove-Item -Recurse -Force $BuildDir
                }
                if (Test-Path ".ninja_cache") {
                    Remove-Item -Recurse -Force ".ninja_cache"
                }
            }
            "WSL" {
                wsl rm -rf "$BuildDir" ".ninja_cache"
            }
            "Container" {
                docker volume rm ninja-build-artifacts --force
            }
            "Docker" {
                docker-compose -f docker-compose.ninja.yml down -v
            }
        }
        
        WriteColor "[INFO] Clean completed" "Green"
    }
}

# Execute the deployment
function Execute-Deployment {
    WriteColor "[INFO] Executing $Method deployment..." "Yellow"
    
    # Deployment logic for each method
    switch ($Method) {
        "Local" {
            $pythonArgs = @(
                "scripts\ninja-team.py",
                "--mode", $Mode,
                "--hosts", $HostsFile,
                "--recursive-depth", $RecursiveDepth,
                "--build-dir", $BuildDir,
                "--verbose"
            )
            
            # Execute the Python script
            & python $pythonArgs
            $deploymentSuccess = $?
        }
        "Server" {
            # Parse hosts file to get server list
            $servers = @()
            if (Test-Path $HostsFile) {
                Get-Content $HostsFile | ForEach-Object {
                    $line = $_ -replace '#.*', '' # Remove comments
                    if ($line -match '^\s*(\S+)') {
                        $server = $matches[1]
                        if ($server -ne "localhost" -and $server -ne "127.0.0.1") {
                            $servers += $server
                        }
                    }
                }
            }
            
            if ($servers.Count -eq 0) {
                WriteColor "[WARNING] No remote servers found in $HostsFile. Falling back to local deployment." "Yellow"
                $Method = "Local"
                Execute-Deployment
                return
            }
            
            WriteColor "[INFO] Deploying to ${servers.Count} remote servers..." "Yellow"
            
            # Deploy to each server
            $deploymentSuccess = $true
            foreach ($server in $servers) {
                WriteColor "[INFO] Deploying to $server..." "Yellow"
                
                # Use SSH to deploy (assumes SSH keys are set up)
                $deployCmd = "ssh $server `"mkdir -p ~/ninja-build && cd ~/ninja-build && python3 -m pip install ninja && python3 -m ninja_team --mode agent --verbose`""
                WriteColor "[INFO] Running: $deployCmd" "Yellow"
                Invoke-Expression $deployCmd
                
                if (-not $?) {
                    WriteColor "[ERROR] Failed to deploy to $server" "Red"
                    $deploymentSuccess = $false
                }
            }
            
            # Start controller on local machine
            if ($deploymentSuccess) {
                WriteColor "[INFO] Starting controller on local machine..." "Yellow"
                $pythonArgs = @(
                    "scripts\ninja-team.py",
                    "--mode", $Mode,
                    "--hosts", $HostsFile,
                    "--recursive-depth", $RecursiveDepth,
                    "--build-dir", $BuildDir,
                    "--verbose"
                )
                
                # Execute the Python script
                & python $pythonArgs
                $deploymentSuccess = $?
            }
        }
        "Container" {
            # Build the container
            WriteColor "[INFO] Building Ninja container..." "Yellow"
            docker build -t $ContainerImage -f Dockerfile.ninja .
            
            if (-not $?) {
                WriteColor "[ERROR] Failed to build container" "Red"
                $deploymentSuccess = $false
            }
            else {
                # Run the container
                WriteColor "[INFO] Running Ninja container..." "Yellow"
                docker run --rm -v ${PWD}:/build -v ninja-build-artifacts:/cache $ContainerImage --mode $Mode --recursive-depth $RecursiveDepth --verbose
                $deploymentSuccess = $?
            }
        }
        "Cloud" {
            WriteColor "[INFO] Deploying to cloud ($CloudRegion)..." "Yellow"
            
            # Determine cloud provider based on region
            $cloudProvider = if ($CloudRegion -like "us-*" -or $CloudRegion -like "eu-west-*") {
                "aws"
            }
            elseif ($CloudRegion -like "eastus*" -or $CloudRegion -like "westus*") {
                "azure"
            }
            else {
                "gcp"
            }
            
            WriteColor "[INFO] Detected cloud provider: $cloudProvider" "Yellow"
            
            # Execute cloud-specific deployment
            switch ($cloudProvider) {
                "aws" {
                    if (Get-Command aws -ErrorAction SilentlyContinue) {
                        # Create stack name
                        $stackName = "ninja-build-team-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                        
                        # Deploy CloudFormation template
                        WriteColor "[INFO] Deploying AWS CloudFormation stack: $stackName..." "Yellow"
                        aws cloudformation create-stack --stack-name $stackName --template-body file://cloud-deploy-template.yaml --region $CloudRegion
                        $deploymentSuccess = $?
                        
                        if ($deploymentSuccess) {
                            WriteColor "[INFO] Waiting for stack creation to complete..." "Yellow"
                            aws cloudformation wait stack-create-complete --stack-name $stackName --region $CloudRegion
                            
                            # Get instance details
                            $instanceId = aws cloudformation describe-stacks --stack-name $stackName --region $CloudRegion --query "Stacks[0].Outputs[?OutputKey=='InstanceId'].OutputValue" --output text
                            $publicDns = aws cloudformation describe-stacks --stack-name $stackName --region $CloudRegion --query "Stacks[0].Outputs[?OutputKey=='PublicDNS'].OutputValue" --output text
                            
                            WriteColor "[INFO] Deployment complete!" "Green"
                            WriteColor "[INFO] Instance ID: $instanceId" "Green"
                            WriteColor "[INFO] Public DNS: $publicDns" "Green"
                        }
                    }
                    else {
                        WriteColor "[ERROR] AWS CLI not found. Please install AWS CLI and configure credentials." "Red"
                        $deploymentSuccess = $false
                    }
                }
                "azure" {
                    if (Get-Command az -ErrorAction SilentlyContinue) {
                        # Create resource group name
                        $resourceGroup = "ninja-build-team-rg"
                        $deploymentName = "ninja-build-team-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                        
                        # Create resource group if it doesn't exist
                        WriteColor "[INFO] Ensuring resource group exists: $resourceGroup..." "Yellow"
                        az group create --name $resourceGroup --location $CloudRegion
                        
                        # Deploy ARM template
                        WriteColor "[INFO] Deploying Azure ARM template: $deploymentName..." "Yellow"
                        az deployment group create --resource-group $resourceGroup --name $deploymentName --template-file cloud-deploy-template.yaml
                        $deploymentSuccess = $?
                        
                        if ($deploymentSuccess) {
                            WriteColor "[INFO] Deployment complete!" "Green"
                        }
                    }
                    else {
                        WriteColor "[ERROR] Azure CLI not found. Please install Azure CLI and login." "Red"
                        $deploymentSuccess = $false
                    }
                }
                "gcp" {
                    if (Get-Command gcloud -ErrorAction SilentlyContinue) {
                        # Create deployment name
                        $deploymentName = "ninja-build-team-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                        
                        # Deploy to GCP
                        WriteColor "[INFO] Deploying to GCP: $deploymentName..." "Yellow"
                        gcloud deployment-manager deployments create $deploymentName --config cloud-deploy-template.yaml
                        $deploymentSuccess = $?
                        
                        if ($deploymentSuccess) {
                            WriteColor "[INFO] Deployment complete!" "Green"
                        }
                    }
                    else {
                        WriteColor "[ERROR] gcloud CLI not found. Please install Google Cloud SDK and configure credentials." "Red"
                        $deploymentSuccess = $false
                    }
                }
            }
        }
        "WSL" {
            # Launch WSL deployment
            WriteColor "[INFO] Deploying with WSL..." "Yellow"
            
            # Convert Windows path to WSL path
            $currentDir = (Get-Location).Path.Replace("\", "/").Replace("C:", "/mnt/c")
            $wslConfig = "$currentDir/scripts/ninja-team-config.json"
            $wslHosts = "$currentDir/$HostsFile"
            
            # Make sure Ninja is installed in WSL
            WriteColor "[INFO] Ensuring Ninja is installed in WSL environment..." "Yellow"
            wsl bash -c "command -v ninja || sudo apt-get update && sudo apt-get install -y ninja-build"
            
            # Execute the bash deployment script through WSL
            wsl cd $currentDir "&&" chmod +x ./scripts/deploy-ninja-team.sh "&&" ./scripts/deploy-ninja-team.sh --config=$wslConfig --hosts=$wslHosts --depth=$RecursiveDepth --mode=$Mode
            $deploymentSuccess = $?
        }
        "Docker" {
            # Deploy using Docker Compose
            WriteColor "[INFO] Deploying with Docker Compose..." "Yellow"
            
            # Build and start the containers
            docker-compose -f docker-compose.ninja.yml up --build -d
            $deploymentSuccess = $?
            
            if ($deploymentSuccess) {
                # Display logs
                WriteColor "[INFO] Deployment successful. Displaying logs..." "Green"
                docker-compose -f docker-compose.ninja.yml logs -f ninja-build
            }
        }
        "AzureDevOps" {
            WriteColor "[INFO] Setting up Azure DevOps pipeline..." "Yellow"
            
            # Check if Azure CLI and Azure DevOps extension are available
            if ((Get-Command az -ErrorAction SilentlyContinue) -and (az extension list --query "[?name=='azure-devops']" 2>&1 | Out-Null; $?)) {
                # Create a new pipeline
                $organization = Read-Host "Enter your Azure DevOps organization name"
                $project = Read-Host "Enter your Azure DevOps project name"
                $repositoryName = Read-Host "Enter repository name"
                
                WriteColor "[INFO] Creating Azure DevOps pipeline..." "Yellow"
                az pipelines create --name "Ninja Build Team" --repository $repositoryName --branch master --yml-path azure-pipelines-ninja.yml --organization "https://dev.azure.com/$organization" --project $project
                $deploymentSuccess = $?
            }
            else {
                WriteColor "[ERROR] Azure CLI with DevOps extension not found. Please install with: az extension add --name azure-devops" "Red"
                $deploymentSuccess = $false
            }
        }
        "GitHub" {
            WriteColor "[INFO] Setting up GitHub Actions workflow..." "Yellow"
            
            # Check if git is initialized
            if (-not (Test-Path ".git")) {
                WriteColor "[ERROR] Git repository not initialized. Please run 'git init' first." "Red"
                $deploymentSuccess = $false
            }
            else {
                # Add and commit the workflow file
                git add .github/workflows/ninja-build.yml
                git commit -m "Add Ninja Build Team GitHub Actions workflow"
                $deploymentSuccess = $?
                
                if ($deploymentSuccess) {
                    WriteColor "[INFO] GitHub Actions workflow committed. Push to GitHub to trigger the workflow." "Green"
                }
            }
        }
    }
    
    # Display deployment result
    if ($deploymentSuccess) {
        WriteColor "`n===============================================" "Green"
        WriteColor "        NINJA DEPLOYMENT SUCCESSFUL!          " "Green"
        WriteColor "===============================================" "Green"
    }
    else {
        WriteColor "`n===============================================" "Red"
        WriteColor "        NINJA DEPLOYMENT FAILED!              " "Red"
        WriteColor "===============================================" "Red"
        exit 1
    }
}

# Main execution flow
Check-Prerequisites
Clean-BuildArtifacts
if ($Initialize) {
    Initialize-BuildEnvironment
}
Execute-Deployment

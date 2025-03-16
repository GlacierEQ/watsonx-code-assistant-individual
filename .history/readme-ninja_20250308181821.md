# Ninja Build Team Deployment Guide

This guide explains how to deploy the ninja build team on Windows using PowerShell.

## Prerequisites

- Python 3.x
- PowerShell 5.1 or later
- Optional: Windows Subsystem for Linux (WSL) for full deployment

## Quick Start

### Basic Deployment
```powershell
# Deploy basic ninja team (in PowerShell)
.\Deploy-Ninjas.ps1
```

### Full Deployment
```powershell
# Deploy full recursive ninja team with all features (requires WSL)
.\Deploy-Ninjas.ps1 -Full
```

## Advanced Options

```powershell
# Clean ninja cache before deploying
.\Deploy-Ninjas.ps1 -Clean

# Set recursive deployment depth 
.\Deploy-Ninjas.ps1 -Depth 5

# Change deployment mode
.\Deploy-Ninjas.ps1 -Mode distributed

# Show help information
.\Deploy-Ninjas.ps1 -Help
```

## Configuration Files

- `ninja-hosts.txt` - List of build hosts (format: hostname port [capabilities])
- `scripts\ninja-team-config.json` - Configuration settings for the ninja team

## Troubleshooting

If you encounter the error "make: command not found", use the PowerShell script instead:
```powershell
# Instead of: make deploy-ninjas
.\Deploy-Ninjas.ps1

# Instead of: make deploy-ninjas-full
.\Deploy-Ninjas.ps1 -Full
```

For WSL-related issues, ensure WSL is installed and configured correctly:
```powershell
# Check WSL status
wsl --status
```

## Further Information

For more details on the ninja build system, see the documentation in the `/docs` directory.

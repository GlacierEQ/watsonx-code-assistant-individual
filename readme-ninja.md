# Ninja Build Team Deployment Guide

This guide explains how to deploy the ninja build team on Windows systems.

## Prerequisites

- Python 3.x
- PowerShell 5.1 or later
- Optional: Windows Subsystem for Linux (WSL) for full deployment

## Quick Start

### Using PowerShell (Recommended)
```powershell
# Deploy basic ninja team with automatic build initialization
.\Deploy-Ninjas.ps1 -Initialize

# Deploy full recursive ninja team with all features
.\Deploy-Ninjas.ps1 -Full
```

### Using make.cmd (Compatibility Mode)
For users who prefer the `make` command-style interface:
```cmd
# Deploy basic ninja team
make deploy-ninjas

# Deploy full recursive ninja team
make deploy-ninjas-full
```

## Troubleshooting

### "Ninja build file not found" Error
If you see this error, initialize the build environment first:
```powershell
.\scripts\init-build-env.ps1
```

### WSL Not Available
WSL is only needed for the full deployment mode. For basic deployment, WSL isn't required.

To install WSL (requires admin permissions):
```powershell
wsl --install
```

### make: command not found
Windows doesn't include the `make` command by default. Use one of these alternatives:
- Use the included `make.cmd` batch file: `make deploy-ninjas`
- Use PowerShell directly: `.\Deploy-Ninjas.ps1`

## Advanced Options

```powershell
# Clean ninja cache before deploying
.\Deploy-Ninjas.ps1 -Clean

# Change deployment mode
.\Deploy-Ninjas.ps1 -Mode distributed

# Show help information
.\Deploy-Ninjas.ps1 -Help
```

## Configuration Files

- `ninja-hosts.txt` - List of build hosts (format: hostname port [capabilities])
- `scripts\ninja-team-config.json` - Configuration settings for the ninja team

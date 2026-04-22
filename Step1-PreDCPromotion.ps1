<#
.SYNOPSIS
    Step 1: Pre-Domain Controller Promotion Script
    Windows Server 2025 Automation - Phase 1
    
.DESCRIPTION
    This script performs all configuration steps that can be completed before
    promoting the server to a Domain Controller. The server requires a restart
    after DC promotion, so this script prepares everything that doesn't depend
    on AD being available.
    
    Operations:
    - System validation
    - Computer renaming
    - Static IP configuration
    - Role installation (DHCP, DNS, IIS, AD-DS)
    - PowerShell extensions
    - Shared folder structure creation
    - Schedules Step 2 to run after restart
    - Initiates DC promotion
    
.AUTHOR
    Windows Server Automation
    
.VERSION
    1.0

.NOTES
    IMPORTANT: Run this script with administrator privileges
    The server will restart automatically at the end for DC promotion
#>

#Requires -RunAsAdministrator

# Error handling
$ErrorActionPreference = "Stop"

# Get script directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $scriptPath

# Load function libraries
. ".\includes\Functions-Common.ps1"
. ".\includes\Functions-Network.ps1"
. ".\includes\Functions-Roles.ps1"
. ".\includes\Functions-Shares.ps1"
. ".\includes\Functions-AD.ps1"

Write-Host @"
================================================================
                                                                
     Windows Server 2025 - Domain Controller Automation        
                                                                
                    STEP 1: PRE-DC PROMOTION                   
                                                                
     This script will configure the server for DC promotion    
                   and initiate the promotion.                 
                                                                
================================================================
"@ -ForegroundColor Cyan

# Step 1: Initialize
Write-Host "[1/10] Initializing automation environment..." -ForegroundColor Yellow
Initialize-Logging
Write-Log "Step 1: Pre-DC Promotion Script Started"

try {
    # Step 2: Validate Admin Rights
    Write-Host "[2/10] Validating administrator privileges..." -ForegroundColor Yellow
    Test-AdminPrivileges
    
    # Step 3: Load Configuration
    Write-Host "[3/10] Loading configuration..." -ForegroundColor Yellow
    [xml]$config = Get-Configuration
    
    # Step 4: System Requirements Check
    Write-Host "[4/10] Checking system requirements..." -ForegroundColor Yellow
    Test-SystemRequirements -Config $config
    
    # Step 5: Network Configuration
    Write-Host "[5/10] Configuring network..." -ForegroundColor Yellow
    $networkSuccess = Set-StaticIPConfiguration -Config $config
    if (-not $networkSuccess) {
        Write-Log "Network configuration had issues, but continuing..." -Warning
    }
    Start-Sleep -Seconds 2  # Give network time to stabilize
    
    # Step 6: Computer Renaming
    Write-Host "[6/10] Renaming computer..." -ForegroundColor Yellow
    Rename-ServerComputer -Config $config
    
    # Step 7: Role Installation
    Write-Host "[7/10] Installing server roles and features..." -ForegroundColor Yellow
    Install-ServerRoles -Config $config
    Install-PowerShellExtensions
    
    # Step 8: Shared Folders
    Write-Host "[8/10] Creating shared folders..." -ForegroundColor Yellow
    Add-SharedFolders -Config $config
    Add-SmbShares -Config $config
    
    # Step 9: Test Network Connectivity
    Write-Host "[9/10] Testing network connectivity..." -ForegroundColor Yellow
    Test-NetworkConnectivity -Config $config
    
    # Step 10: Schedule Step 2 and Promote
    Write-Host "[10/10] Scheduling post-promotion automation..." -ForegroundColor Yellow
    
    # Get safe mode password from config
    $safeModePassword = $config.Configuration.ActiveDirectory.SafeModePassword
    
    Write-Log "All pre-promotion tasks completed successfully!"
    Write-Log ""
    Write-Log "=== PRE-PROMOTION SUMMARY ==="
    Write-Log "[ERROR] Computer name: $($config.Configuration.Server.ComputerName)"
    Write-Log "[ERROR] Static IP: $($config.Configuration.Network.StaticIP)"
    Write-Log "[ERROR] Domain: $($config.Configuration.ActiveDirectory.Domain)"
    Write-Log "[ERROR] Shared folders created"
    Write-Log "[ERROR] Required roles installed"
    Write-Log ""
    
    # Schedule Step 2 to run after restart
    $step2Path = Join-Path $scriptPath "Step2-PostDCPromotion.ps1"
    Register-RestartTask -ScriptPath $step2Path -TaskName "DC-Automation-Step2"
    
    Write-Host "" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host " CONFIGURATION COMPLETE - INITIATING DC PROMOTION              " -ForegroundColor Green
    Write-Host "                                                                " -ForegroundColor Green
    Write-Host " The server will:                                              " -ForegroundColor Green
    Write-Host " 1. Promote to Domain Controller                                " -ForegroundColor Green
    Write-Host " 2. Restart automatically                                       " -ForegroundColor Green
    Write-Host " 3. Run Step 2 automation on next boot                          " -ForegroundColor Green
    Write-Host "                                                                " -ForegroundColor Green
    Write-Host " Domain: havgap-camping.no                                     " -ForegroundColor Green
    Write-Host " Computer: $($config.Configuration.Server.ComputerName)        " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    
    Wait-Execution -Message "Press any key to begin DC promotion (server will restart automatically)..."
    
    # Initiate DC Promotion
    Write-Host "Initiating Domain Controller promotion..." -ForegroundColor Cyan
    Promote-ToDomainController -Config $config -SafeModePassword $safeModePassword
    
} catch {
    Write-Log "[ERROR] CRITICAL ERROR: $_" -IsError
    Write-Log "Execution halted due to error"
    Write-Host "[ERROR] An error occurred during automation!" -ForegroundColor Red
    Write-Host "Check the log file for details: $(Get-CurrentLogFile)" -ForegroundColor Red
    
    Write-ExecutionSummary -PendingTasks @(
        "Domain Controller promotion"
        "Step 2: Post-promotion automation"
    )
    
    # Don't restart on error
    exit 1
}

Write-Host "" -ForegroundColor Green
Write-ExecutionSummary -CompletedTasks @(
    "System validation"
    "Network configuration"
    "Computer renaming"
    "Role installation"
    "Shared folder creation"
    "Post-promotion automation scheduled"
)

# Final pause before DC promotion
Start-Sleep -Seconds 5

Write-Log "Step 1: Pre-DC Promotion Script Completed Successfully"
Write-Log "Server will restart for Domain Controller promotion"

# If we reach here, DC promotion is starting
Write-Host "Server is preparing to restart for DC promotion..." -ForegroundColor Yellow
Write-Log "=== End of Step 1 Execution ===" -Verbose

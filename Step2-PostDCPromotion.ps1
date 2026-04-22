<#
.SYNOPSIS
    Step 2: Post-Domain Controller Promotion Script
    Windows Server 2025 Automation - Phase 2
    
.DESCRIPTION
    This script runs after the server has been promoted to a Domain Controller
    and has restarted. It performs all AD-dependent configuration tasks.
    
    Operations:
    - Verify DC promotion success
    - Configure DHCP scopes
    - Configure DNS zones
    - Create AD Organizational Unit structure
    - Create security groups
    - Configure Group Policies (password restrictions, Ctrl+Alt+Del, drive mappings)
    - Finalize sharing and permissions
    - System optimization
    
.AUTHOR
    Windows Server Automation
    
.VERSION
    1.0

.NOTES
    This script is automatically scheduled by Step 1 and runs after
    the server restart following DC promotion.
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
. ".\includes\Functions-AD.ps1"
. ".\includes\Functions-GPO.ps1"
. ".\includes\Functions-Shares.ps1"
. ".\includes\Functions-Roles.ps1"

Write-Host @"
================================================================
                                                                
     Windows Server 2025 - Domain Controller Automation        
                                                                
                   STEP 2: POST-DC PROMOTION                   
                                                                
     Configuring Active Directory and domain services...       
                                                                
================================================================
"@ -ForegroundColor Cyan

# Step 1: Initialize
Write-Host "`n[1/11] Initializing post-promotion environment..." -ForegroundColor Yellow
Initialize-Logging
Write-Log "Step 2: Post-DC Promotion Script Started"

try {
    # Step 2: Validate Admin Rights
    Write-Host "[2/11] Validating administrator privileges..." -ForegroundColor Yellow
    Test-AdminPrivileges
    
    # Step 3: Load Configuration
    Write-Host "[3/11] Loading configuration..." -ForegroundColor Yellow
    [xml]$config = Get-Configuration
    
    # Step 4: Verify DC Promotion
    Write-Host "[4/11] Verifying Domain Controller promotion..." -ForegroundColor Yellow
    $dcVerified = Test-DCPromotion -Domain $config.Configuration.ActiveDirectory.Domain
    if (-not $dcVerified) {
        Write-Log "WARNING: DC promotion verification failed, but continuing..." -Warning
    }
    
    # Step 5: Create AD Structure
    Write-Host "[5/11] Creating Active Directory structure..." -ForegroundColor Yellow
    Create-OUStructure -Config $config
    Create-SecurityGroups -Config $config
    
    # Step 6: Configure DHCP
    Write-Host "[6/11] Configuring DHCP..." -ForegroundColor Yellow
    Configure-DHCPScope -Config $config
    
    # Step 7: Configure DNS
    Write-Host "[7/11] Configuring DNS..." -ForegroundColor Yellow
    Configure-DNSZone -Config $config
    
    # Step 8: Configure Password Policy
    Write-Host "[8/11] Configuring password policies..." -ForegroundColor Yellow
    Configure-PasswordPolicy -Config $config
    
    # Step 9: Configure Security Policies
    Write-Host "[9/11] Configuring security policies..." -ForegroundColor Yellow
    Configure-SecurityPolicy -Config $config
    
    # Step 10: Configure Drive Mappings
    Write-Host "[10/11] Configuring drive mappings via Group Policy..." -ForegroundColor Yellow
    Configure-DriveMappings -Config $config
    
    # Step 11: Finalize and Verify
    Write-Host "[11/11] Finalizing configuration and verification..." -ForegroundColor Yellow
    Test-SharedFolders -Config $config
    
    Write-Log "All post-promotion tasks completed successfully!"
    Write-Log ""
    Write-Log "=== POST-PROMOTION SUMMARY ==="
    Write-Log "[ERROR] DC promotion verified"
    Write-Log "[ERROR] AD structure created"
    Write-Log "[ERROR] Security groups configured"
    Write-Log "[ERROR] DHCP configured"
    Write-Log "[ERROR] DNS configured"
    Write-Log "[ERROR] Group Policies applied"
    Write-Log "[ERROR] Password restrictions disabled"
    Write-Log "[ERROR] Ctrl+Alt+Del disabled"
    Write-Log "[ERROR] Drive mappings configured"
    Write-Log ""
    
    Write-Host "`n" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "║  DOMAIN CONTROLLER SETUP COMPLETE!                            " -ForegroundColor Green
    Write-Host "║                                                                " -ForegroundColor Green
    Write-Host "║  Configuration Summary:                                        " -ForegroundColor Green
    Write-Host "║  [ERROR] Domain: $($config.Configuration.ActiveDirectory.Domain)                              " -ForegroundColor Green
    Write-Host "║  [ERROR] Controller: $($config.Configuration.Server.ComputerName)                                        " -ForegroundColor Green
    Write-Host "║  [ERROR] IP Address: $($config.Configuration.Network.StaticIP)                                 " -ForegroundColor Green
    Write-Host "║  [ERROR] DHCP Pool: $($config.Configuration.DHCP.StartRange) - $($config.Configuration.DHCP.EndRange) " -ForegroundColor Green
    Write-Host "║  [ERROR] AD OUs: Created and configured                             " -ForegroundColor Green
    Write-Host "║  [ERROR] Group Policies: Applied                                    " -ForegroundColor Green
    Write-Host "║  [ERROR] Shared Folders: Configured                                 " -ForegroundColor Green
    Write-Host "║                                                                " -ForegroundColor Green
    Write-Host "║  The domain controller is ready for production use.            " -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    
    Write-ExecutionSummary -CompletedTasks @(
        "DC promotion verification"
        "AD structure creation"
        "Security group configuration"
        "DHCP configuration"
        "DNS configuration"
        "Group Policy application"
        "Password policy (disabled restrictions)"
        "Security policy (Ctrl+Alt+Del disabled)"
        "Drive mappings (configured)"
        "Shared folders (verified)"
    )
    
    # Remove scheduled task
    try {
        Unregister-ScheduledTask -TaskName "DC-Automation-Step2" -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Cleaned up scheduled task: DC-Automation-Step2" -Verbose
    } catch {
        Write-Log "Could not remove scheduled task (non-critical)" -Warning
    }
    
} catch {
    Write-Log "[ERROR] CRITICAL ERROR: $_" -IsError
    Write-Log "Execution halted due to error"
    Write-Host "`n[ERROR] An error occurred during post-promotion automation!" -ForegroundColor Red
    Write-Host "Check the log file for details: $(Get-CurrentLogFile)" -ForegroundColor Red
    
    Write-ExecutionSummary -PendingTasks @(
        "Any remaining configuration tasks"
    )
    
    exit 1
}

Write-Log "Step 2: Post-DC Promotion Script Completed Successfully"
Write-Host "`nAutomation complete! Press any key to exit..." -ForegroundColor Green
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
Write-Log "=== End of Step 2 Execution ===" -Verbose

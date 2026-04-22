<# 
    Common PowerShell Functions for Windows Server DC Automation
    Used by both Step1 and Step2 scripts
#>

# Global variables
$script:LogDirectory = $null
$script:LogFile = $null

<#
.SYNOPSIS
    Initializes logging infrastructure
.DESCRIPTION
    Creates log directory and sets up log file for the current execution
#>
function Initialize-Logging {
    param(
        [string]$LogDir = ".\logs"
    )
    
    if (-not (Test-Path $LogDir)) {
        New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $script:LogFile = Join-Path $LogDir "Automation_$timestamp.log"
    $script:LogDirectory = $LogDir
    
    Write-Log "=== Automation Started: $(Get-Date) ===" -Verbose
}

<#
.SYNOPSIS
    Writes messages to both console and log file
#>
function Write-Log {
    param(
        [string]$Message,
        [switch]$Warning,
        [switch]$IsError,
        [switch]$Verbose
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] $Message"
    
    # Write to log file
    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $logMessage
    }
    
    # Write to console
    if ($Warning) {
        Write-Host $logMessage -ForegroundColor Yellow
    }
    elseif ($IsError) {
        Write-Host $logMessage -ForegroundColor Red
    }
    elseif ($Verbose) {
        Write-Host $logMessage -ForegroundColor Green
    }
    else {
        Write-Host $logMessage
    }
}

<#
.SYNOPSIS
    Loads and validates XML configuration file
#>
function Get-Configuration {
    param(
        [string]$ConfigPath = ".\config\server-config.xml"
    )
    
    if (-not (Test-Path $ConfigPath)) {
        Write-Log "Configuration file not found: $ConfigPath" -IsError
        throw "Configuration file not found"
    }
    
    try {
        [xml]$config = Get-Content $ConfigPath
        Write-Log "Configuration loaded successfully from: $ConfigPath" -Verbose
        return $config
    }
    catch {
        Write-Log "Failed to load configuration: $_" -IsError
        throw $_
    }
}

<#
.SYNOPSIS
    Checks if script is running with administrator privileges
#>
function Test-AdminPrivileges {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "ERROR: This script must be run with administrator privileges!" -IsError
        throw "Administrator privileges required"
    }
    
    Write-Log "Administrator privileges confirmed" -Verbose
}

<#
.SYNOPSIS
    Executes a command with error handling and logging
#>
function Invoke-Command-Logged {
    param(
        [string]$Description,
        [scriptblock]$Command,
        [switch]$ContinueOnError
    )
    
    Write-Log "Executing: $Description"
    
    try {
        & $Command
        Write-Log "✓ Completed: $Description" -Verbose
        return $true
    }
    catch {
        Write-Log "✗ Failed: $Description - $_" -IsError
        
        if (-not $ContinueOnError) {
            throw $_
        }
        return $false
    }
}

<#
.SYNOPSIS
    Pauses execution and prompts for continuation
#>
function Wait-Execution {
    param(
        [string]$Message = "Press any key to continue..."
    )
    
    Write-Log "PAUSE: $Message"
    Write-Host "`nPause: $Message" -ForegroundColor Cyan
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

<#
.SYNOPSIS
    Schedules a script to run after restart
#>
function Register-RestartTask {
    param(
        [string]$ScriptPath,
        [string]$TaskName = "AutomationStep2"
    )
    
    Write-Log "Scheduling script to run after restart: $ScriptPath"
    
    try {
        $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""
        
        $taskTrigger = New-ScheduledTaskTrigger -AtStartup
        
        $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
            -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount `
            -RunLevel Highest
        
        Register-ScheduledTask -TaskName $TaskName -Action $taskAction `
            -Trigger $taskTrigger -Settings $taskSettings -Principal $principal -Force | Out-Null
        
        Write-Log "✓ Scheduled task created: $TaskName" -Verbose
    }
    catch {
        Write-Log "✗ Failed to create scheduled task: $_" -IsError
        throw $_
    }
}

<#
.SYNOPSIS
    Validates system requirements before proceeding
#>
function Test-SystemRequirements {
    param(
        [xml]$Config
    )
    
    Write-Log "Validating system requirements..."
    
    # Check Windows version
    $osVersion = (Get-WmiObject Win32_OperatingSystem).Version
    Write-Log "Windows version: $osVersion"
    
    # Check disk space (at least 20GB free)
    $systemDrive = Get-Volume -DriveLetter C
    if ($systemDrive.SizeRemaining -lt 20GB) {
        Write-Log "WARNING: Less than 20GB free disk space available" -Warning
    }
    
    # Check available memory (at least 2GB)
    $totalMemory = (Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory
    if ($totalMemory -lt 2GB) {
        Write-Log "WARNING: Less than 2GB RAM available" -Warning
    }
    
    Write-Log "✓ System requirements check completed" -Verbose
}

<#
.SYNOPSIS
    Restarts the computer with optional delay
#>
function Restart-ComputerForDC {
    param(
        [int]$DelaySeconds = 10
    )
    
    Write-Log "Computer will restart in $DelaySeconds seconds for DC promotion..."
    Write-Host "`n*** IMPORTANT: Computer will restart in $DelaySeconds seconds ***`n" -ForegroundColor Red
    
    Start-Sleep -Seconds $DelaySeconds
    
    Restart-Computer -Force
}

<#
.SYNOPSIS
    Gets current execution log file path
#>
function Get-CurrentLogFile {
    return $script:LogFile
}

<#
.SYNOPSIS
    Writes execution summary to log
#>
function Write-ExecutionSummary {
    param(
        [string[]]$CompletedTasks,
        [string[]]$PendingTasks
    )
    
    Write-Log "`n=== EXECUTION SUMMARY ===" -Verbose
    
    if ($CompletedTasks.Count -gt 0) {
        Write-Log "Completed Tasks:" -Verbose
        $CompletedTasks | ForEach-Object { Write-Log "  ✓ $_" -Verbose }
    }
    
    if ($PendingTasks.Count -gt 0) {
        Write-Log "Pending Tasks:" -Verbose
        $PendingTasks | ForEach-Object { Write-Log "  ⊳ $_" }
    }
    
    Write-Log "Log file: $(Get-CurrentLogFile)" -Verbose
    Write-Log "=== EXECUTION COMPLETED: $(Get-Date) ===" -Verbose
}

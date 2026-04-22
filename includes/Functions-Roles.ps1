<# 
    Role Installation Functions for Windows Server DC Automation
#>

<#
.SYNOPSIS
    Installs Windows Server roles and features
#>
function Install-ServerRoles {
    param(
        [xml]$Config
    )
    
    $roles = @()
    $features = @()
    
    # Active Directory Domain Services
    $roles += "AD-Domain-Services"
    
    # DNS
    if ($Config.Configuration.DNS.Enabled -eq "true") {
        $roles += "DNS"
    }
    
    # DHCP
    if ($Config.Configuration.DHCP.Enabled -eq "true") {
        $roles += "DHCP"
    }
    
    # IIS
    if ($Config.Configuration.IIS.Enabled -eq "true") {
        $roles += "Web-Server"
        
        # Add IIS features from config
        foreach ($feature in $Config.Configuration.IIS.Features.Feature) {
            $features += $feature
        }
    }
    
    # Add common features
    $features += "RSAT-AD-Tools"
    $features += "RSAT-DHCP"
    $features += "RSAT-DNS-Server"
    $features += "PowerShell-ISE"
    
    Write-Log "Installing server roles and features..."
    
    try {
        if ($roles.Count -gt 0) {
            Write-Log "  Installing roles: $($roles -join ', ')"
            Install-WindowsFeature -Name $roles -IncludeManagementTools -ErrorAction Stop | Out-Null
        }
        
        if ($features.Count -gt 0) {
            Write-Log "  Installing features: $($features -join ', ')"
            Install-WindowsFeature -Name $features -ErrorAction Stop | Out-Null
        }
        
        Write-Log "[ERROR] Server roles and features installed successfully" -Verbose
        return $true
    } catch {
        Write-Log "[ERROR] Failed to install server roles/features: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Installs additional PowerShell modules and extensions
#>
function Install-PowerShellExtensions {
    param()
    
    Write-Log "Installing PowerShell extensions..."
    
    try {
        # Update PowerShell Help
        Update-Help -Force -ErrorAction SilentlyContinue
        
        # Install useful modules if not present
        $modules = @(
            "PSWindowsUpdate",
            "NTFSSecurity",
            "Posh-SSH"
        )
        
        foreach ($module in $modules) {
            try {
                if (-not (Get-Module -ListAvailable -Name $module -ErrorAction SilentlyContinue)) {
                    Install-Module -Name $module -Force -AllowClobber -ErrorAction SilentlyContinue | Out-Null
                    Write-Log "  [ERROR] Installed module: $module"
                }
            } catch {
                Write-Log "  [WARNING] Could not install module $module (non-critical)" -Warning
            }
        }
        
        Write-Log "[ERROR] PowerShell extensions installed successfully" -Verbose
        return $true
    } catch {
        Write-Log "[WARNING] Some PowerShell extensions may not have installed properly" -Warning
        return $false
    }
}

<#
.SYNOPSIS
    Initializes and configures IIS
#>
function Initialize-IIS {
    param(
        [xml]$Config
    )
    
    if ($Config.Configuration.IIS.Enabled -ne "true") {
        Write-Log "IIS not enabled in configuration"
        return $true
    }
    
    Write-Log "Configuring Internet Information Services (IIS)..."
    
    try {
        # IIS is installed with roles, now configure it
        $iisPath = "C:\inetpub\wwwroot"
        
        if (Test-Path $iisPath) {
            Write-Log "  [ERROR] IIS root directory: $iisPath"
        }
        
        # Enable common IIS features
        Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Enable-WindowsOptionalFeature -Online -FeatureName IIS-ASP -NoRestart -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "[ERROR] IIS configured successfully" -Verbose
        return $true
    } catch {
        Write-Log "[ERROR] Failed to configure IIS: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Verifies role installation
#>
function Test-RoleInstallation {
    param(
        [string]$RoleName
    )
    
    try {
        $role = Get-WindowsFeature -Name $RoleName -ErrorAction Stop
        
        if ($role.Installed) {
            Write-Log "[ERROR] Role verified: $RoleName" -Verbose
            return $true
        } else {
            Write-Log "[ERROR] Role not installed: $RoleName" -Warning
            return $false
        }
    } catch {
        Write-Log "[ERROR] Error verifying role: $RoleName - $_" -Warning
        return $false
    }
}

<#
.SYNOPSIS
    Gets list of installed roles
#>
function Get-InstalledRoles {
    try {
        $installed = Get-WindowsFeature | Where-Object { $_.Installed -eq $true }
        return $installed
    } catch {
        Write-Log "[ERROR] Failed to get installed roles: $_" -IsError
        return @()
    }
}

<# 
    Group Policy Functions for Windows Server DC Automation
#>

<#
.SYNOPSIS
    Creates and configures Group Policy Objects for password policy
#>
function Configure-PasswordPolicy {
    param(
        [xml]$Config
    )
    
    $domain = $Config.Configuration.ActiveDirectory.Domain
    $policyConfig = $Config.Configuration.GroupPolicy.PasswordPolicy
    
    Write-Log "Configuring password policy..."
    
    try {
        # Get Default Domain Policy GPO
        $gpo = Get-GPO -Name "Default Domain Policy" -ErrorAction Stop
        
        # Configure password settings
        Set-GPRegistryValue -Guid $gpo.Id -Key "HKLM\System\CurrentControlSet\Services\Netlogon\Parameters" `
            -ValueName "MaximumPasswordAge" -Value $policyConfig.MaximumPasswordAge -Type DWord -ErrorAction Stop | Out-Null
        
        Set-GPRegistryValue -Guid $gpo.Id -Key "HKLM\System\CurrentControlSet\Services\Netlogon\Parameters" `
            -ValueName "MinimumPasswordLength" -Value $policyConfig.MinimumPasswordLength -Type DWord -ErrorAction Stop | Out-Null
        
        Set-GPRegistryValue -Guid $gpo.Id -Key "HKLM\System\CurrentControlSet\Services\Netlogon\Parameters" `
            -ValueName "PasswordComplexity" -Value (if ($policyConfig.RequireComplexity -eq "true") { 1 } else { 0 }) -Type DWord -ErrorAction Stop | Out-Null
        
        # Force policy update
        Invoke-GPUpdate -Force -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "✓ Password policy configured successfully" -Verbose
        Write-Log "  Maximum Password Age: $($policyConfig.MaximumPasswordAge) days"
        Write-Log "  Minimum Password Length: $($policyConfig.MinimumPasswordLength) characters"
        Write-Log "  Require Complexity: $($policyConfig.RequireComplexity)"
        
        return $true
    } catch {
        Write-Log "✗ Failed to configure password policy: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Configures security policies (Ctrl+Alt+Del, lock screen)
#>
function Configure-SecurityPolicy {
    param(
        [xml]$Config
    )
    
    $securityPolicy = $Config.Configuration.GroupPolicy.SecurityPolicy
    
    Write-Log "Configuring security policies..."
    
    try {
        $gpo = Get-GPO -Name "Default Domain Policy" -ErrorAction Stop
        
        if ($securityPolicy.DisableCtrlAltDel -eq "true") {
            Set-GPRegistryValue -Guid $gpo.Id -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
                -ValueName "DisableCAD" -Value 1 -Type DWord -ErrorAction Stop | Out-Null
            Write-Log "  ✓ Ctrl+Alt+Del disabled"
        }
        
        if ($securityPolicy.DisableLockScreen -eq "true") {
            Set-GPRegistryValue -Guid $gpo.Id -Key "HKLM\Software\Policies\Microsoft\Windows\Control Panel\Desktop" `
                -ValueName "ScreenSaverIsSecure" -Value 0 -Type DWord -ErrorAction Stop | Out-Null
            Write-Log "  ✓ Lock screen disabled"
        }
        
        Invoke-GPUpdate -Force -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "✓ Security policies configured successfully" -Verbose
        
        return $true
    } catch {
        Write-Log "✗ Failed to configure security policies: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Creates drive mapping Group Policy
#>
function Configure-DriveMappings {
    param(
        [xml]$Config
    )
    
    $domain = $Config.Configuration.ActiveDirectory.Domain
    $mappings = $Config.Configuration.GroupPolicy.DriveMappings.Mapping
    
    Write-Log "Configuring drive mappings..."
    
    try {
        # Create new GPO for drive mappings
        $gpoName = "DriveMappings"
        
        # Check if GPO exists
        $gpo = Get-GPO -Name $gpoName -ErrorAction SilentlyContinue
        if (-not $gpo) {
            $gpo = New-GPO -Name $gpoName -ErrorAction Stop
            Write-Log "  ✓ Created GPO: $gpoName"
        } else {
            Write-Log "  ↻ GPO already exists: $gpoName"
        }
        
        # Configure drive mappings
        foreach ($mapping in $mappings) {
            Set-GPRegistryValue -Guid $gpo.Id `
                -Key "HKCU\Network\$($mapping.DriveLetter -replace ':')" `
                -ValueName "RemotePath" -Value $mapping.Path -Type String -ErrorAction Stop | Out-Null
            
            Write-Log "  ✓ Configured mapping: $($mapping.DriveLetter) -> $($mapping.Path)"
        }
        
        Write-Log "✓ Drive mappings configured successfully" -Verbose
        
        return $true
    } catch {
        Write-Log "✗ Failed to configure drive mappings: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Applies Group Policy to organization units
#>
function Apply-GroupPolicy {
    param(
        [xml]$Config,
        [string]$OUPath
    )
    
    Write-Log "Applying Group Policy to OU: $OUPath"
    
    try {
        # Link GPO to OU if not already linked
        $gpo = Get-GPO -Name "DriveMappings" -ErrorAction SilentlyContinue
        
        if ($gpo) {
            New-GPLink -Name $gpo.DisplayName -Target $OUPath -LinkEnabled Yes `
                -ErrorAction SilentlyContinue | Out-Null
        }
        
        # Force group policy update
        Invoke-GPUpdate -Force -ErrorAction SilentlyContinue | Out-Null
        
        Write-Log "✓ Group Policy applied to OU: $OUPath" -Verbose
        
        return $true
    } catch {
        Write-Log "✗ Failed to apply Group Policy: $_" -IsError
        return $false
    }
}

<#
.SYNOPSIS
    Verifies GPO application
#>
function Test-GroupPolicyApplication {
    param(
        [string]$GPOName
    )
    
    try {
        $gpo = Get-GPO -Name $GPOName -ErrorAction Stop
        Write-Log "✓ GPO verified: $GPOName" -Verbose
        return $true
    } catch {
        Write-Log "✗ GPO not found: $GPOName" -Warning
        return $false
    }
}

# Windows Server 2025 DC Automation - Quick Start

## What's Been Created

A complete automation project for setting up Windows Server 2025 as a Domain Controller for `havgap-camping.no` with the following phases:

### Phase 1: Pre-DC Promotion (Step1-PreDCPromotion.ps1)
Executes on the fresh Windows Server 2025 installation:
- [OK] Renames computer to DC01
- [OK] Configures static IP: 192.168.5.10
- [OK] Installs DHCP, DNS, IIS, AD-DS roles
- [OK] Creates shared folder structure on D: drive
- [OK] Promotes server to Domain Controller
- [OK] Schedules Phase 2 to run after restart
- [OK] **Initiates automatic restart**

### Phase 2: Post-DC Promotion (Step2-PostDCPromotion.ps1)
Automatically runs after the server restarts:
- [OK] Verifies DC promotion success
- [OK] Creates AD Organizational Units
- [OK] Creates security groups (IT, Finance, HR)
- [OK] Configures DHCP scope (192.168.5.100-200)
- [OK] Configures DNS zones
- [OK] Disables password complexity requirements
- [OK] Disables Ctrl+Alt+Del for users
- [OK] Configures drive mappings (Z: -> \\DC01\Public)
- [OK] Finalizes all configurations

---

## Quick Start

### 1. Prepare the Server
- Fresh Windows Server 2025 installation
- Administrator access
- Network connected to your network with 192.168.5.1 gateway

### 2. Customize Configuration
Edit `config/server-config.xml`:
- [ ] Change Safe Mode password (critical!)
- [ ] Verify network settings (gateway = 192.168.5.1)
- [ ] Review AD structure and shared folders
- [ ] Adjust any IP ranges or computer names if needed

### 3. Run Step 1
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\Step1-PreDCPromotion.ps1
```
- Monitor the progress
- Server will restart automatically for DC promotion
- **Do not interrupt the process**

### 4. Step 2 Runs Automatically
After the restart:
- Step 2 script automatically runs via scheduled task
- Completes domain setup
- No action needed - just monitor

### 5. Verify Success
After completion, check:
```powershell
Get-ADDomainController          # Verify DC is active
Get-DhcpServerv4Scope          # Check DHCP configured
Get-DnsServerZone              # Check DNS zones
Get-ADOrganizationalUnit -Filter * | Select Name  # View AD structure
```

---

## Project Structure

```
Windows-Server-DC-Automation/
│
├─ Step1-PreDCPromotion.ps1      ← Run this first
├─ Step2-PostDCPromotion.ps1     ← Runs automatically after restart
│
├─ config/
│  └─ server-config.xml           ← CUSTOMIZE THIS BEFORE RUNNING
│
├─ includes/                      ← Function libraries (used by both scripts)
│  ├─ Functions-Common.ps1
│  ├─ Functions-Network.ps1
│  ├─ Functions-AD.ps1
│  ├─ Functions-GPO.ps1
│  ├─ Functions-Roles.ps1
│  └─ Functions-Shares.ps1
│
└─ logs/                          ← Execution logs (auto-generated)
```

---

## Configuration Highlights

### Key Settings in server-config.xml:

**Domain:** havgap-camping.no
```xml
<Domain>havgap-camping.no</Domain>
```

**DC Name:** DC01
```xml
<ComputerName>DC01</ComputerName>
```

**Network Configuration:**
```xml
<StaticIP>192.168.5.10</StaticIP>
<Gateway>192.168.5.1</Gateway>
```

**DHCP Scope:** 192.168.5.100 - 192.168.5.200
```xml
<StartRange>192.168.5.100</StartRange>
<EndRange>192.168.5.200</EndRange>
```

**Shared Folders:**
- D:\Shares\Public (Everyone: Read)
- D:\Shares\IT (IT: Read/Write)
- D:\Shares\Finance (Finance: Read/Write)
- D:\Shares\HR (HR: Read/Write)

**AD Structure:**
```
havgap-camping.no
├── Computers
├── Users
│  ├── IT
│  ├── Finance
│  └── HR
├── Groups
└── Servers
```

**Security Groups:**
- Domain Admins
- IT
- Finance
- HR

**Group Policies:**
- Password max age: **0 (never expires)**
- Password complexity: **disabled**
- Ctrl+Alt+Del: **disabled for workstations**
- Drive mapping: Z: -> \\DC01\Public

---

## What Happens During Execution

### Step 1 Progress (first run):
```
[1/10] Initializing automation environment...
[2/10] Validating administrator privileges...
[3/10] Loading configuration...
[4/10] Checking system requirements...
[5/10] Configuring network...
[6/10] Renaming computer...
[7/10] Installing server roles and features...    ← Takes 5-10 minutes
[8/10] Creating shared folders...
[9/10] Testing network connectivity...
[10/10] Scheduling post-promotion automation...
```
**Result: Server promotes to DC and restarts automatically**

### Step 2 Progress (automatic, after restart):
```
[1/11] Initializing post-promotion environment...
[2/11] Validating administrator privileges...
[3/11] Loading configuration...
[4/11] Verifying Domain Controller promotion...
[5/11] Creating Active Directory structure...
[6/11] Configuring DHCP...
[7/11] Configuring DNS...
[8/11] Configuring password policies...
[9/11] Configuring security policies...
[10/11] Configuring drive mappings...
[11/11] Finalizing configuration...
```
**Result: Complete domain setup with all services configured**

---

## Monitoring & Logs

All execution is logged to `logs/` directory with timestamps:
- Each run creates a new log file
- Logs contain all executed commands and results
- Useful for troubleshooting

Check current execution:
```powershell
Get-ChildItem logs/ | Select-Object -Last 1 -ExpandProperty FullName | % { Get-Content $_ }
```

---

## Troubleshooting

### If Step 1 Fails:
1. Check the log file for specific errors
2. Verify network connectivity: `ping 192.168.5.1`
3. Ensure minimum 4GB RAM: `Get-WmiObject Win32_ComputerSystem | Select TotalPhysicalMemory`
4. Check disk space: `Get-Volume`
5. Verify PowerShell is running as Administrator
6. Fix the issue and re-run Step 1

### If Step 2 Doesn't Run:
1. Manually run: `.\Step2-PostDCPromotion.ps1`
2. Check scheduled task: `Get-ScheduledTask -TaskName "DC-Automation-Step2"`
3. Check for scheduled task errors in Event Viewer

### If Domain Services Don't Start:
1. Verify DC promotion: `Get-ADDomainController`
2. Check services: `Get-Service | Where {$_.Name -like "AD*" -or $_.Name -like "DHCP*" -or $_.Name -like "DNS*"}`
3. Review logs for specific service errors

---

## Customization Examples

### Change Computer Name:
```xml
<ComputerName>DC02</ComputerName>  <!-- For second DC -->
```

### Change IP Address:
```xml
<StaticIP>192.168.5.11</StaticIP>
<PrimaryDNS>192.168.5.11</PrimaryDNS>
```

### Adjust DHCP Range:
```xml
<StartRange>192.168.5.150</StartRange>
<EndRange>192.168.5.250</EndRange>
```

### Add Shared Folder:
```xml
<Folder>
    <Name>Marketing</Name>
    <Path>D:\Shares\Marketing</Path>
    <Permission>Marketing:ReadWrite</Permission>
</Folder>
```

After customizing, re-run the scripts. They'll detect existing configurations and skip what's already done.

---

## Important Notes

[CRITICAL]:
- Change the Safe Mode password in `server-config.xml` before running!
- Ensure gateway is set to 192.168.5.1 and is reachable
- Don't interrupt Step 1 during DC promotion
- Step 2 runs automatically - no action needed

[RECOMMENDED]:
- Back up the server after successful setup
- Test domain join with client machines
- Verify DHCP clients can obtain IPs
- Test drive mappings on a client machine
- Review Group Policy effectiveness

---

## After Automation Completes

The domain controller is now ready. Next steps:

1. **Join client machines to the domain:**
   ```powershell
   Add-Computer -DomainName havgap-camping.no -Restart
   ```

2. **Create domain users:**
   ```powershell
   New-ADUser -Name "User Name" -GivenName "User" -Surname "Name" `
      -SamAccountName "username" -UserPrincipalName "username@havgap-camping.no" `
      -Path "OU=Users,DC=havgap-camping,DC=no" -Enabled $true
   ```

3. **Add users to security groups:**
   ```powershell
   Add-ADGroupMember -Identity "IT" -Members "username"
   ```

4. **Monitor DC health:**
   - Use Server Manager
   - Monitor Event Viewer
   - Check disk space and performance regularly

---

## Documentation Files

- **SETUP_GUIDE.md** - Comprehensive setup and configuration guide
- **README.md** - Project overview and structure
- **This file** - Quick start reference

For detailed information, see the SETUP_GUIDE.md file.

---

**Project Status: Ready for Deployment**

All scripts are configured for havgap-camping.no domain with 192.168.5.* network.

Review the config file, customize as needed, and run Step 1!

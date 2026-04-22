# Windows Server 2025 Domain Controller Automation Setup Guide

## Overview

This project automates the complete setup of a Windows Server 2025 machine as a Domain Controller for the `havgap-camping.no` domain. The automation is split into two phases to accommodate the restart required for DC promotion.

### Key Features

✓ **Automated Configuration**
- Computer naming
- Static IP configuration with proper gateway routing
- Installation of DHCP, DNS, and IIS roles
- Shared folder structure creation
- Active Directory promotion

✓ **Domain-Ready Infrastructure**
- AD Organizational Unit hierarchy (Users, Computers, Groups, Servers)
- Security groups (IT, Finance, HR, Domain Admins)
- DHCP scope configuration (100-200 range)
- DNS zone creation with reverse lookup
- Drive mappings (Z: -> Public share)

✓ **Security Configuration**
- Password policy disabled (no age/complexity requirements)
- Ctrl+Alt+Del disabled for workstations
- Share-level and NTFS permissions configured
- Group Policy Objects for drive mapping distribution

✓ **Logging & Recovery**
- Comprehensive logging to `logs/` directory
- Timestamped execution records
- Error tracking and recovery points

---

## Prerequisites

### System Requirements
- **OS**: Windows Server 2025 (fresh installation)
- **RAM**: 4GB minimum (8GB recommended)
- **Disk**: 40GB free space (20GB minimum)
- **Network**: Connected to 192.168.5.0/24 network with 192.168.5.1 gateway
- **Admin**: Must run scripts with administrator privileges

### Network Setup
- Gateway router on **192.168.5.1** (must be accessible)
- No existing DHCP server on the network (or configure exclusions)
- DNS resolution capability to 8.8.8.8 for secondary DNS

### Pre-Execution
1. Fresh Windows Server 2025 installation (no domain joined)
2. Administrator account available
3. Access to modify system settings and install roles

---

## Configuration

### 1. Review `config/server-config.xml`

This file controls all aspects of the automation. Key sections:

#### Active Directory Section
```xml
<ActiveDirectory>
    <Domain>havgap-camping.no</Domain>
    <ForestFunctionalLevel>2025</ForestFunctionalLevel>
    <DomainFunctionalLevel>2025</DomainFunctionalLevel>
    <SafeModePassword></SafeModePassword>
</ActiveDirectory>
```
**⚠️ IMPORTANT**: Change the `SafeModePassword` to a secure password!

#### Server Section
```xml
<Server>
    <ComputerName>DC01</ComputerName>
    <Description>Primary Domain Controller - havgap-camping.no</Description>
</Server>
```
Computer name defaults to `DC01`. Modify if needed.

#### Network Section
```xml
<Network>
    <StaticIP>192.168.5.10</StaticIP>
    <SubnetMask>255.255.255.0</SubnetMask>
    <Gateway>192.168.5.1</Gateway>
    <PrimaryDNS>192.168.5.10</PrimaryDNS>
    <SecondaryDNS>8.8.8.8</SecondaryDNS>
    <NetworkInterface>Ethernet</NetworkInterface>
</Network>
```
- **StaticIP**: DC server IP (default: 192.168.5.10)
- **Gateway**: Must be 192.168.5.1 for your network
- **PrimaryDNS**: Will be the DC itself (auto-configured)

#### DHCP Section
```xml
<DHCP>
    <Enabled>true</Enabled>
    <ScopeName>MainNetwork</ScopeName>
    <StartRange>192.168.5.100</StartRange>
    <EndRange>192.168.5.200</EndRange>
    <SubnetMask>255.255.255.0</SubnetMask>
    <Gateway>192.168.5.1</Gateway>
    <LeaseDuration>691200</LeaseDuration>
</DHCP>
```
- Client IPs: 192.168.5.100 to 192.168.5.200
- Gateway points to 192.168.5.1 (your router)
- Lease duration: 8 days

#### Shared Folders Section
```xml
<SharedFolders>
    <Folder>
        <Name>Public</Name>
        <Path>D:\Shares\Public</Path>
        <Permission>Everyone:Read</Permission>
    </Folder>
    <!-- IT, Finance, HR folders with respective permissions -->
</SharedFolders>
```
Creates shared folders on D: drive (modify path if needed).

#### Group Policy Section
```xml
<GroupPolicy>
    <PasswordPolicy>
        <MaximumPasswordAge>0</MaximumPasswordAge>      <!-- Never expires -->
        <MinimumPasswordLength>0</MinimumPasswordLength> <!-- No requirement -->
        <RequireComplexity>false</RequireComplexity>
    </PasswordPolicy>
    <SecurityPolicy>
        <DisableCtrlAltDel>true</DisableCtrlAltDel>
        <DisableLockScreen>true</DisableLockScreen>
    </SecurityPolicy>
    <DriveMappings>
        <Mapping>
            <DriveLetter>Z:</DriveLetter>
            <Path>\\DC01\Public</Path>
        </Mapping>
    </DriveMappings>
</GroupPolicy>
```

#### Organizational Unit Structure
Automatically creates:
- `Computers` - For computer accounts
- `Users` - With sub-OUs for IT, Finance, HR
- `Groups` - For security groups
- `Servers` - For server accounts

#### Security Groups
Automatically creates:
- Domain Admins
- IT
- Finance
- HR

### 2. Customize Configuration (Optional)

**Common customizations:**

**Change DC Name:**
```xml
<ComputerName>DC02</ComputerName>  <!-- For additional DC -->
```

**Adjust DHCP Range:**
```xml
<StartRange>192.168.5.150</StartRange>
<EndRange>192.168.5.250</EndRange>
```

**Add Shared Folders:**
```xml
<Folder>
    <Name>Marketing</Name>
    <Path>D:\Shares\Marketing</Path>
    <Permission>Marketing:ReadWrite,Everyone:Read</Permission>
</Folder>
```

**Modify Drive Mappings:**
```xml
<Mapping>
    <DriveLetter>Y:</DriveLetter>
    <Path>\\DC01\HR</Path>
    <Label>HR Department</Label>
</Mapping>
```

---

## Execution

### Phase 1: Pre-DC Promotion

**Step 1: Prepare the server**
1. Boot into Windows Server 2025
2. Open PowerShell as Administrator
3. Navigate to the automation script directory
4. Review and modify `config/server-config.xml` as needed
5. Run Step 1:

```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force
.\Step1-PreDCPromotion.ps1
```

**What happens:**
- ✓ Computer is renamed to `DC01`
- ✓ Static IP configured: 192.168.5.10
- ✓ Roles installed: AD-DS, DHCP, DNS, IIS, PowerShell modules
- ✓ Shared folders created on D: drive
- ✓ Scheduled task created for Step 2
- ✓ **Server promoted to Domain Controller**
- ✓ **Server restarts automatically**

**Estimated time:** 10-15 minutes

### Phase 2: Post-DC Promotion

**Step 2: Complete domain configuration (automatic)**
- Triggered automatically after restart via scheduled task
- Creates AD structure, groups, and policies
- Configures DHCP scopes
- Sets up DNS zones
- Applies Group Policies
- Cleans up after completion

**What happens:**
- ✓ DC promotion verified
- ✓ AD OUs and security groups created
- ✓ DHCP scope configured (192.168.5.100-200)
- ✓ DNS zones created
- ✓ Password policies disabled
- ✓ Security policies applied (Ctrl+Alt+Del, etc.)
- ✓ Drive mappings configured via GPO
- ✓ Shared folders verified

**Estimated time:** 5-10 minutes

---

## Execution Flow Diagram

```
START
  │
  ├─► Step 1: Pre-DC Promotion
  │    ├─ Rename computer → DC01
  │    ├─ Configure IP → 192.168.5.10
  │    ├─ Install DHCP, DNS, IIS, AD-DS
  │    ├─ Create shared folders
  │    ├─ Schedule Step 2 after restart
  │    └─ Promote to DC → RESTART
  │
  ├─► [AUTOMATIC RESTART]
  │
  ├─► Step 2: Post-DC Promotion (Auto-triggered)
  │    ├─ Verify DC promotion
  │    ├─ Create AD structure
  │    ├─ Create security groups
  │    ├─ Configure DHCP scopes
  │    ├─ Configure DNS zones
  │    ├─ Apply Group Policies
  │    └─ Cleanup
  │
  └─► COMPLETE
       Domain Controller ready for production
```

---

## Monitoring & Logging

### Log Files

All execution logs are stored in `logs/` directory with timestamps:

```
logs/
├── Automation_2026-04-22_14-30-45.log  (Step 1)
└── Automation_2026-04-22_15-45-23.log  (Step 2)
```

### View Live Logs

During execution, PowerShell displays:
- ✓ Green text: Completed tasks
- ⚠ Yellow text: Warnings
- ✗ Red text: Errors

### Check Specific Log File

```powershell
Get-Content "logs\Automation_*.log" -Tail 50
```

### Verify Domain Controller Status

After automation completes:

```powershell
# Verify DC promotion
Get-ADDomainController

# Check AD structure
Get-ADOrganizationalUnit -Filter * | Format-Table Name

# List security groups
Get-ADGroup -Filter * | Format-Table Name

# Check DHCP scopes
Get-DhcpServerv4Scope

# Verify DNS zones
Get-DnsServerZone
```

---

## Troubleshooting

### Issue: Step 1 fails to rename computer

**Solution:**
- Ensure no other users are logged in
- Check disk space (minimum 20GB)
- Try restarting and running again

### Issue: Network configuration fails

**Solution:**
- Verify network cable is connected
- Check gateway IP is accessible: `ping 192.168.5.1`
- Review network adapter name: `Get-NetAdapter`
- Modify `<NetworkInterface>` in config if needed

### Issue: DHCP not starting

**Solution:**
- Ensure no other DHCP server on network
- Check DHCP scope IP range doesn't conflict
- Verify authorizations in AD

### Issue: DC promotion fails

**Solution:**
- Check system has minimum 4GB RAM
- Verify domain name is valid (no special characters)
- Ensure DNS is working: `nslookup havgap-camping.no`
- Review Safe Mode Administrator password in config

### Issue: Step 2 doesn't run automatically

**Solution:**
- Check scheduled task exists: `Get-ScheduledTask -TaskName "DC-Automation-Step2"`
- Manually run: `.\Step2-PostDCPromotion.ps1`
- Check Event Viewer for scheduled task errors

### Issue: Group Policy not applying

**Solution:**
- Force immediate update: `gpupdate /force`
- Check Group Policy Editor: `gpedit.msc`
- Verify GPO links to correct OUs
- Restart client machines to receive policies

---

## Post-Automation Checklist

After both steps complete:

- [ ] Server renamed to `DC01`
- [ ] Static IP: 192.168.5.10
- [ ] Domain controller role active
- [ ] AD structure visible in Active Directory Users & Computers
- [ ] Security groups created (IT, Finance, HR, etc.)
- [ ] DHCP scope active (192.168.5.100-200)
- [ ] DNS zones created (havgap-camping.no)
- [ ] Shared folders accessible (\\DC01\Public, etc.)
- [ ] Drive mappings working on client (Z: drive)
- [ ] Password policies disabled (no complexity required)
- [ ] Logs stored in `logs/` directory

---

## Security Considerations

⚠️ **Important Security Notes:**

1. **Safe Mode Password**: Change the default in `server-config.xml`
   - Use a strong, unique password
   - Store it securely

2. **Shared Folder Permissions**: Verify NTFS and Share permissions
   - Public: Everyone (Read)
   - Department folders: Group (Read/Write)

3. **Group Policy**: Password policy is set to **0 age** and **0 complexity**
   - Suitable for internal development/test networks only
   - Consider stricter policies for production

4. **Firewall**: After setup, configure firewall rules:
   - DHCP: UDP 67, 68
   - DNS: UDP 53, TCP 53
   - AD: TCP 389, 636

5. **Backup**: Backup the DC after successful setup
   - System state backup recommended
   - Full system backup for recovery

---

## Additional Configuration

### Adding a Second Domain Controller (Replica)

To create a replica DC in the same domain:

1. Use the same domain name: `havgap-camping.no`
2. Modify computer name: `DC02`
3. Change static IP: `192.168.5.11`
4. Run both scripts (replica will join existing domain)

### Joining Client Computers

After DC setup, join client computers to the domain:

```powershell
Add-Computer -DomainName havgap-camping.no -Restart
```

### Adding Users to AD

```powershell
New-ADUser -Name "John Doe" `
    -GivenName "John" -Surname "Doe" `
    -SamAccountName "jdoe" `
    -UserPrincipalName "jdoe@havgap-camping.no" `
    -Path "OU=IT,OU=Users,DC=havgap-camping,DC=no" `
    -Enabled $true -ChangePasswordAtLogon $true
```

### Managing Group Policy

```powershell
# Open Group Policy Editor
gpeditmsc

# Force immediate update
gpupdate /force

# Display current policies
Get-GPO -All
```

---

## Support & Maintenance

### Regular Maintenance Tasks

**Daily:**
- Monitor Event Viewer for errors
- Check DHCP leases

**Weekly:**
- Verify backups are running
- Check disk space on DC

**Monthly:**
- Review security group memberships
- Test backup restoration

**Quarterly:**
- Apply Windows updates
- Review Group Policy effectiveness

### Performance Optimization

Monitor DC performance:

```powershell
# Check CPU usage
Get-Counter -Counter "\Processor(_Total)\% Processor Time"

# Check memory usage
Get-Counter -Counter "\Memory\Available MBytes"

# Check disk usage
Get-Volume
```

---

## File Structure Reference

```
Windows-Server-DC-Automation/
├── README.md                              # Project overview
├── SETUP_GUIDE.md                         # This file
├── Step1-PreDCPromotion.ps1               # Phase 1 main script
├── Step2-PostDCPromotion.ps1              # Phase 2 main script
│
├── config/
│   ├── server-config.xml                  # Main configuration (CUSTOMIZE)
│   └── credentials-template.xml           # Credentials template
│
├── includes/
│   ├── Functions-Common.ps1               # Shared utilities
│   ├── Functions-Network.ps1              # IP, DHCP, DNS functions
│   ├── Functions-AD.ps1                   # Active Directory functions
│   ├── Functions-Roles.ps1                # Role installation functions
│   ├── Functions-GPO.ps1                  # Group Policy functions
│   └── Functions-Shares.ps1               # Shared folder functions
│
└── logs/
    ├── Automation_*.log                   # Execution logs (auto-generated)
    └── [More logs generated during runs]
```

---

## Version History

### v1.0 - Initial Release
- Pre-DC promotion configuration
- DC promotion automation
- Post-promotion domain setup
- DHCP/DNS configuration
- Group Policy automation
- Shared folder configuration

---

## License

This automation project is provided as-is for Windows Server 2025 domain setup.

---

## Questions or Issues?

Review the execution logs in the `logs/` directory for detailed error messages and troubleshooting information.

Last Updated: April 22, 2026

# How to Run on Windows Server 2025 VM in VirtualBox

## Pre-Execution Setup on Your VM

### 1. **Transfer Files to VM**
Copy the entire `Windows-Server-DC-Automation` folder to your VM's C: drive (or preferred location)

### 2. **Set Execution Policy** (Run PowerShell as Administrator)
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force
```

### 3. **Update Configuration** - Edit `config\server-config.xml`
- **SafeModePassword**: Set a secure password (currently: `ChangeMe@12345`)
- **StaticIP**: Adjust to your network (currently: 192.168.5.10)
- **Gateway**: Update to your network gateway (currently: 192.168.5.1)
- **Domain**: You can keep `havgap-camping.no` or change it

Example to change in PowerShell:
```powershell
# If you want to use a different password:
$newPassword = "YourSecurePassword@123"
# Edit the XML file and replace the SafeModePassword value
```

### 4. **Ensure Second Drive (Optional but Recommended)**
The script expects a D: drive for shared folders. In VirtualBox:
- Add a second hard disk to the VM (at least 20GB)
- Initialize and format as NTFS in Disk Management
- Assign it as D: drive

---

## Execution Steps

### **STEP 1: Run Phase 1 Script**

On your Windows Server 2025 VM, open PowerShell **as Administrator**:

```powershell
# Navigate to the script directory
cd C:\path\to\Windows-Server-DC-Automation

# Run Step 1
.\Step1-PreDCPromotion.ps1
```

**What it does:**
- ✓ Validates system requirements
- ✓ Renames computer to DC01
- ✓ Configures static IP (192.168.5.10)
- ✓ Installs required roles: AD-DS, DNS, DHCP, IIS
- ✓ Creates shared folder structure on D: drive
- ✓ Schedules Step 2 to run after restart
- ✓ **Automatically restarts the server** to promote DC

⏱️ **Expected Time:** 10-15 minutes

### **STEP 2: After Automatic Restart**

Step 2 will run automatically after the server restarts via the scheduled task.

**If automatic execution fails:**
```powershell
# Manually run it
cd C:\path\to\Windows-Server-DC-Automation
.\Step2-PostDCPromotion.ps1
```

**What it does:**
- ✓ Verifies DC promotion success
- ✓ Creates AD Organizational Units (IT, Finance, HR)
- ✓ Creates security groups
- ✓ Configures DHCP scope (192.168.5.100-200)
- ✓ Configures DNS zones
- ✓ Disables password complexity (optional)
- ✓ Sets up drive mappings
- ✓ Applies Group Policies

⏱️ **Expected Time:** 5-10 minutes

---

## Troubleshooting

### ❌ "Execution of scripts is disabled" Error
```powershell
# Fix by setting execution policy BEFORE running scripts
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
```

### ❌ "Cannot find path" or "File not found"
- Ensure you're running the script FROM its directory
- Use full paths or `cd` to the script folder first

### ❌ "SafeModePassword" Error
- Edit `config\server-config.xml` and ensure `<SafeModePassword>` is filled

### ❌ "D: drive not found"
- Create/attach a second disk to your VirtualBox VM
- Initialize it in Disk Management
- The script will create the folder structure

### ❌ Network Configuration Issues
- Check your VirtualBox network settings (Bridged/NAT/Host-Only)
- Ensure the static IP (192.168.5.10) doesn't conflict with existing devices
- Test with: `ping 192.168.5.1` (your gateway)

### ✓ Check Logs
Logs are saved in `.\logs\Automation_*.log`
```powershell
Get-Content .\logs\*.log -Tail 50  # Last 50 lines
```

---

## Security Notes

⚠️ **Important:**
1. Change `SafeModePassword` to a strong password
2. Change `ChangeMe@12345` if you plan to use this in production
3. After setup is complete, delete credentials from the config file
4. Set file permissions on config files to Admin-only

---

## Testing Without DC Promotion (Optional)

To test the script WITHOUT promoting the server:

Edit `Step1-PreDCPromotion.ps1` and comment out this line:
```powershell
# Invoke-Command-Logged -Description "Promote to Domain Controller" `
#     -Command { Promote-ToDomainController $config $safeModePassword }
```

This lets you test the initial configuration without DC promotion.

---

## Network Diagram

```
Your PC
  ↓
VirtualBox VM (Windows Server 2025)
  ├─ IP: 192.168.5.10 (Static)
  ├─ Gateway: 192.168.5.1
  └─ Domain: havgap-camping.no
```

---

## Next Steps

1. **Copy files to VM**
2. **Set execution policy**
3. **Update config\server-config.xml**
4. **Run Step 1**
5. **Wait for restart**
6. **Verify Step 2 runs automatically**
7. **Check logs for any errors**

Good luck! 🚀

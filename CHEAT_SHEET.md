# ⚡ Quick Cheat Sheet - Windows Server 2025 DC Setup

## 🚀 Before You Start
```powershell
# 1. SET EXECUTION POLICY (Open PowerShell as Admin)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# 2. EDIT CONFIG (Open in Notepad)
notepad .\config\server-config.xml
# Change SafeModePassword to something secure!
```

## ✅ Configuration Checklist

- [ ] SafeModePassword changed from `ChangeMe@12345`?
- [ ] Static IP (192.168.5.10) appropriate for your network?
- [ ] Gateway (192.168.5.1) correct for your network?
- [ ] Second disk (D:) exists in VirtualBox?
- [ ] Files copied to VM at C:\Windows-Server-DC-Automation

## 🎯 Two Commands to Run Everything

```powershell
# PHASE 1: Pre-DC Promotion (15 mins + restart)
cd C:\Windows-Server-DC-Automation
.\Step1-PreDCPromotion.ps1

# ↓ SERVER RESTARTS AUTOMATICALLY ↓

# PHASE 2: Post-DC Promotion (Runs automatically after restart)
# If it doesn't run automatically, manually execute:
cd C:\Windows-Server-DC-Automation
.\Step2-PostDCPromotion.ps1
```

## 📊 What Gets Configured

### Phase 1
- Computer name → DC01
- Static IP → 192.168.5.10
- DNS configured
- Roles: AD-DS, DNS, DHCP, IIS installed
- D: drive shared folders created

### Phase 2
- AD Organizational Units created
- Security groups: IT, Finance, HR
- DHCP scope: 192.168.5.100-200
- DNS zones configured
- Group policies applied

## 🔍 Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| "Execution of scripts is disabled" | `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force` |
| "File not found" | Make sure you're in C:\Windows-Server-DC-Automation directory |
| "D: drive not found" | Add second disk in VirtualBox → Initialize in Disk Management |
| "SafeModePassword" error | Edit config\server-config.xml, fill in SafeModePassword |
| "Cannot find network path" | Check gateway/static IP in config matches your network |

## 📝 Check Logs

```powershell
# View last 50 lines of log
Get-Content .\logs\*.log -Tail 50

# List all logs
Dir .\logs\
```

## 🌐 Network Settings Reference

```
DC Server: 192.168.5.10
Gateway: 192.168.5.1
Primary DNS: 192.168.5.10 (itself)
Secondary DNS: 8.8.8.8
DHCP Scope: 192.168.5.100 - 192.168.5.200
Domain: havgap-camping.no
Computer Name: DC01
```

## 💾 Change Settings After Running

Edit `config\server-config.xml` before running Step1.

**Don't change after Step1 is running** - Server will have already been renamed and configured.

## ✨ What Happens Automatically

1. Step1 runs → Configures server → Schedules Step2 → Restarts
2. Server restarts
3. Step2 runs automatically (via scheduled task)
4. Log files saved in `.\logs\`

## 📞 Need More Help?

See **RUN_ON_VM.md** for detailed instructions

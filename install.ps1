#-------------------------------------------------------------
# OFFENSIVE SYNTAX - Automated Provisioning Script (Syntax VM)
#-------------------------------------------------------------

$Boxstarter.RebootOk = $true
$Boxstarter.AutoLogin = $true

Write-Output "[*] Starting Offensive Syntax workstation build..."

Write-Output "[*] Configuring Windows Explorer options..."
Set-ExplorerOptions -showProtectedOSFiles -showFileExtensions -showDriveLetters
Enable-RemoteDesktop

Write-Output "[*] Disabling Windows Defender protections..."
Set-MpPreference -DisableRealtimeMonitoring $true
Set-MpPreference -DisableBehaviorMonitoring $true
Set-MpPreference -DisableBlockAtFirstSee $true
Set-MpPreference -DisableIOAVProtection $true
Set-MpPreference -DisablePrivacyMode $true
Set-MpPreference -SubmitSamplesConsent 2 
Set-MpPreference -MAPSReporting 0        

Write-Output "[*] Installing Visual Studio 2022 Community (C++ Build Tools & Win 10 SDK)..."
cinst -y visualstudio2022community --package-parameters "--add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Workload.ManagedDesktop --includeRecommended --passive"

Write-Output "[*] Installing Languages (Python, Go, Rust) & Git..."
cinst -y vscode
cinst -y git
cinst -y python3
cinst -y golang
cinst -y rust

Update-SessionEnvironment

Write-Output "[*] Installing analysis and debugging suite..."
cinst -y x64dbg.fireeye
cinst -y sysinternals
cinst -y systeminformer
cinst -y ghidra
cinst -y apimonitor

Write-Output "[*] Finalizing core utility installations..."
cinst -y wireshark
cinst -y windows-terminal
cinst -y 7zip
cinst -y notepadplusplus

# 7. Pull Down and Extract "Dummy" Testing Tools
Write-Output "[*] Deploying Offensive Syntax Dummy test apps..."

$DesktopPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), "Offensive Syntax Tools")
if (-not (Test-Path $DesktopPath)) {
    New-Item -ItemType Directory -Path $DesktopPath -Force | Out-Null
}

$UrlX64 = "https://github.com/Offensive-Syntax/dummy/releases/download/1.0.0/dummy-v1.0.0-win-x64.rar"
$UrlX86 = "https://github.com/Offensive-Syntax/dummy/releases/download/1.0.0/dummy-v1.0.0-win-x86.rar"
$RarX64 = Join-Path $DesktopPath "dummy_x64.rar"
$RarX86 = Join-Path $DesktopPath "dummy_x86.rar"

Invoke-WebRequest -Uri $UrlX64 -OutFile $RarX64
Invoke-WebRequest -Uri $UrlX86 -OutFile $RarX86

$SevenZip = "C:\Program Files\7-Zip\7z.exe"
if (Test-Path $SevenZip) {
    & $SevenZip x $RarX64 "-o$DesktopPath" -y | Out-Null
    & $SevenZip x $RarX86 "-o$DesktopPath" -y | Out-Null
    Remove-Item $RarX64 -Force
    Remove-Item $RarX86 -Force
    Write-Output "[+] Dummy apps successfully extracted to Desktop\Offensive Syntax Tools"
} else {
    Write-Warning "[-] 7-Zip was not found where expected. RAR files are left intact."
}

# 8. Set Custom Offensive Syntax Desktop Background
Write-Output "[*] Applying Offensive Syntax Desktop Wallpaper..."

$WallpaperUrl = "https://raw.githubusercontent.com/Offensive-Syntax/syntax-vm/main/wallpaper.png"
$LocalWallpaperPath = "C:\Windows\offensive_syntax_wallpaper.png"

try {
    Invoke-WebRequest -Uri $WallpaperUrl -OutFile $LocalWallpaperPath
    
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $LocalWallpaperPath
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10" # 10 = Fill, 6 = Fit, 2 = Stretch
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0"
    
    Write-Output "[+] Wallpaper staged successfully."
} catch {
    Write-Warning "[-] Failed to download or configure custom wallpaper."
}

Write-Output "[+] Installations complete. Finalizing setup and rebooting..."
Invoke-Reboot
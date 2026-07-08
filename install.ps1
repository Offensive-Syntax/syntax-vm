#-------------------------------------------------------------
# OFFENSIVE SYNTAX - Automated Provisioning Script (Syntax VM)
#-------------------------------------------------------------

$Boxstarter.RebootOk = $true
$Boxstarter.AutoLogin = $true

$LogPath = "C:\syntaxvm.log"
$SummaryPath = "C:\syntaxvm-summary.txt"
$CheckpointDir = "C:\ProgramData\SyntaxVM\checkpoints"
New-Item -ItemType Directory -Path $CheckpointDir -Force | Out-Null

Add-Content -Path $SummaryPath -Value "`n===== Run started $(Get-Date) ====="

function Test-Checkpoint($Name) {
    return Test-Path (Join-Path $CheckpointDir "$Name.done")
}
function Set-Checkpoint($Name) {
    New-Item -ItemType File -Path (Join-Path $CheckpointDir "$Name.done") -Force | Out-Null
}
function Write-Log($Message) {
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
    Write-Output $line
    Add-Content -Path $LogPath -Value $line
}
function Write-Result($Status, $Name, $Detail = "") {
    $line = "{0,-6} {1}{2}" -f $Status, $Name, $(if ($Detail) { " - $Detail" } else { "" })
    Add-Content -Path $SummaryPath -Value $line
}

function Install-ChocoPackageSafe {
    param(
        [Parameter(Mandatory)][string]$PackageName,
        [string]$PackageParameters = "",
        [int]$TimeoutSeconds = 10800
    )
    $checkpointName = "pkg-$PackageName"
    if (Test-Checkpoint $checkpointName) {
        Write-Log "[=] $PackageName already installed - skipping."
        return $true
    }

    Write-Log "[*] Installing $PackageName ..."
    try {
        $args = @("install", $PackageName, "-y", "--execution-timeout=$TimeoutSeconds", "--no-progress")
        if ($PackageParameters) {
            $args += "--package-parameters"
            $args += $PackageParameters
        }
        $output = & choco @args 2>&1
        $output | Add-Content -Path $LogPath
        $code = $LASTEXITCODE

        $installedList = & choco list --local-only --exact $PackageName -r 2>$null
        $isInstalled = $installedList -match [regex]::Escape($PackageName)
        $okCodes = @(0, 1605, 1614, 1641, 3010)

        if (-not $isInstalled -and $code -and ($okCodes -notcontains $code)) {
            throw "choco reported exit code $code and package not found in local list."
        }

        Write-Log "[+] $PackageName installed OK (exit code: $code)."
        Set-Checkpoint $checkpointName
        Write-Result "OK" $PackageName
        return $true
    } catch {
        Write-Log "[-] $PackageName FAILED: $_"
        Write-Result "FAIL" $PackageName "$_"
        return $false
    }
}

function Install-PipPackageSafe {
    param([Parameter(Mandatory)][string]$PackageName)
    $checkpointName = "pip-$PackageName"
    if (Test-Checkpoint $checkpointName) {
        Write-Log "[=] pip:$PackageName already installed - skipping."
        return $true
    }
    Write-Log "[*] pip installing $PackageName ..."
    try {
        $output = & python -m pip install --no-input $PackageName 2>&1
        $output | Add-Content -Path $LogPath
        & python -m pip show $PackageName *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "package not found via 'pip show' after install attempt."
        }
        Write-Log "[+] pip:$PackageName installed OK."
        Set-Checkpoint $checkpointName
        Write-Result "OK" "pip:$PackageName"
        return $true
    } catch {
        Write-Log "[-] pip:$PackageName FAILED: $_"
        Write-Result "FAIL" "pip:$PackageName" "$_"
        return $false
    }
}

function Invoke-DownloadSafe {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$OutFile,
        [Parameter(Mandatory)][string]$CheckpointName
    )
    if (Test-Checkpoint $CheckpointName) {
        Write-Log "[=] $CheckpointName already downloaded - skipping."
        return $true
    }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
        Set-Checkpoint $CheckpointName
        Write-Result "OK" "download:$CheckpointName"
        return $true
    } catch {
        Write-Log "[-] Download FAILED for $CheckpointName ($Url): $_"
        Write-Result "FAIL" "download:$CheckpointName" "$_"
        return $false
    }
}

function Invoke-StepSafe {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if (Test-Checkpoint $Name) {
        Write-Log "[=] Step '$Name' already completed - skipping."
        return $true
    }
    Write-Log "[*] Running step: $Name"
    try {
        & $Action
        Set-Checkpoint $Name
        Write-Result "OK" $Name
        return $true
    } catch {
        Write-Log "[-] Step '$Name' FAILED: $_"
        Write-Result "FAIL" $Name "$_"
        return $false
    }
}

function Test-SyntaxVMResources {
    try {
        $sysDrive = Get-PSDrive -Name C
        $freeGB = [math]::Round($sysDrive.Free / 1GB, 1)
        $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $cpuCores = (Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors

        Write-Log "[*] Resource check: $freeGB GB free disk, $ramGB GB RAM, $cpuCores logical CPUs"

        if ($freeGB -lt 64) {
            Write-Log "[-] WARNING: Less than 64GB free on C:. Low disk is the most common cause of install failures in this script."
        }
        if ($ramGB -lt 8) {
            Write-Log "[-] WARNING: Less than 8GB RAM. Large installs (VS especially) are more likely to fail or time out."
        }
        if ($cpuCores -lt 4) {
            Write-Log "[-] WARNING: Fewer than 4 logical CPUs. Installs will be slower and more timeout-prone."
        }
    } catch {
        Write-Log "[-] Resource check itself failed (non-fatal): $_"
    }
}

function Start-SyntaxProvisioning {
    Write-Log "=============================================="
    Write-Log "    OFFENSIVE SYNTAX WORKSTATION SETUP LOG    "
    Write-Log "=============================================="

    Test-SyntaxVMResources

    Invoke-StepSafe "explorer-options" {
        Set-ExplorerOptions -showProtectedOSFiles -showFileExtensions -showDriveLetters
        Enable-RemoteDesktop
    }

    Invoke-StepSafe "disable-defender" {
        Set-MpPreference -DisableRealtimeMonitoring $true
        Set-MpPreference -DisableBehaviorMonitoring $true
        Set-MpPreference -DisableBlockAtFirstSee $true
        Set-MpPreference -DisableIOAVProtection $true
        Set-MpPreference -DisablePrivacyMode $true
        Set-MpPreference -SubmitSamplesConsent 2
        Set-MpPreference -MAPSReporting 0
    }

    Invoke-StepSafe "pause-windows-update" {
        Disable-MicrosoftUpdate
    }

    Install-ChocoPackageSafe -PackageName "visualstudio2022community" `
        -PackageParameters "--passive --norestart --includeRecommended"

    Install-ChocoPackageSafe -PackageName "visualstudio2022-workload-nativedesktop" `
        -PackageParameters "--passive --norestart"

    Install-ChocoPackageSafe -PackageName "visualstudio2022-workload-manageddesktop" `
        -PackageParameters "--passive --norestart"

    foreach ($pkg in @("vscode", "git", "python3", "golang", "rust")) {
        Install-ChocoPackageSafe -PackageName $pkg
    }
    try { Update-SessionEnvironment } catch { Write-Log "[-] Update-SessionEnvironment failed (non-fatal): $_" }

    foreach ($pkg in @("x64dbg.fireeye", "sysinternals", "systeminformer", "ghidra", "apimonitor")) {
        Install-ChocoPackageSafe -PackageName $pkg
    }

    foreach ($pkg in @("radare2", "cutter", "nasm", "llvm", "cmake", "ninja",
                        "ilspy", "explorersuite", "hxd", "reshack", "yara", "sysmon")) {
        Install-ChocoPackageSafe -PackageName $pkg
    }

    foreach ($pkg in @("nmap", "hashcat", "burp-suite-free-edition")) {
        Install-ChocoPackageSafe -PackageName $pkg
    }

    foreach ($pkg in @("wireshark", "windows-terminal", "7zip", "notepadplusplus")) {
        Install-ChocoPackageSafe -PackageName $pkg
    }

    try { Update-SessionEnvironment } catch { Write-Log "[-] Update-SessionEnvironment failed (non-fatal): $_" }
    try { & python -m pip install --upgrade pip 2>&1 | Add-Content -Path $LogPath } catch { Write-Log "[-] pip self-upgrade failed (non-fatal): $_" }
    foreach ($pkg in @("pefile", "capstone", "unicorn", "keystone-engine",
                        "frida-tools", "yara-python", "volatility3", "impacket", "netexec")) {
        Install-PipPackageSafe -PackageName $pkg
    }

    Invoke-StepSafe "dummy-apps" {
        $DesktopPath = [System.IO.Path]::Combine([Environment]::GetFolderPath("Desktop"), "Offensive Syntax Tools")
        if (-not (Test-Path $DesktopPath)) {
            New-Item -ItemType Directory -Path $DesktopPath -Force | Out-Null
        }

        $downloadedX64 = Invoke-DownloadSafe -Url "https://github.com/Offensive-Syntax/dummy/releases/download/1.0.0/dummy-v1.0.0-win-x64.rar" `
            -OutFile (Join-Path $DesktopPath "dummy_x64.rar") -CheckpointName "dummy-x64-download"
        $downloadedX86 = Invoke-DownloadSafe -Url "https://github.com/Offensive-Syntax/dummy/releases/download/1.0.0/dummy-v1.0.0-win-x86.rar" `
            -OutFile (Join-Path $DesktopPath "dummy_x86.rar") -CheckpointName "dummy-x86-download"

        $SevenZip = "C:\Program Files\7-Zip\7z.exe"
        if ((Test-Path $SevenZip) -and ($downloadedX64 -or $downloadedX86)) {
            $RarX64 = Join-Path $DesktopPath "dummy_x64.rar"
            $RarX86 = Join-Path $DesktopPath "dummy_x86.rar"
            if (Test-Path $RarX64) {
                & $SevenZip x $RarX64 "-o$DesktopPath" -y | Out-Null
                Remove-Item $RarX64 -Force -ErrorAction SilentlyContinue
            }
            if (Test-Path $RarX86) {
                & $SevenZip x $RarX86 "-o$DesktopPath" -y | Out-Null
                Remove-Item $RarX86 -Force -ErrorAction SilentlyContinue
            }
            Write-Log "[+] Dummy apps extracted to Desktop\Offensive Syntax Tools"
        } elseif (-not (Test-Path $SevenZip)) {
            throw "7-Zip not found at expected path - cannot extract dummy apps."
        }
    }

    Invoke-StepSafe "wallpaper" {
        $LocalWallpaperPath = "C:\Windows\offensive_syntax_wallpaper.png"
        $ok = Invoke-DownloadSafe -Url "https://raw.githubusercontent.com/Offensive-Syntax/syntax-vm/main/wallpaper.png" `
            -OutFile $LocalWallpaperPath -CheckpointName "wallpaper-download"
        if (-not $ok) { throw "wallpaper download failed" }
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "Wallpaper" -Value $LocalWallpaperPath
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle" -Value "10"
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper" -Value "0"
    }

    Invoke-StepSafe "resume-windows-update" {
        Enable-MicrosoftUpdate
    }

    Write-Log "===================================================="
    Write-Log "    SETUP COMPLETE"
    Write-Log "===================================================="
    $summary = Get-Content $SummaryPath
    $okCount = ($summary | Where-Object { $_ -match '^OK\s' }).Count
    $failCount = ($summary | Where-Object { $_ -match '^FAIL\s' }).Count
    Write-Log "[*] $okCount succeeded, $failCount failed this run. Full breakdown: $SummaryPath"
    if ($failCount -gt 0) {
        Write-Log "[-] Failed items:"
        $summary | Where-Object { $_ -match '^FAIL\s' } | ForEach-Object { Write-Log "    $_" }
        Write-Log "[*] Re-run the same Install-BoxstarterPackage command to retry only the failed/incomplete items - everything that already succeeded will be skipped."
    }
}

Start-SyntaxProvisioning *>&1 | Tee-Object -FilePath $LogPath -Append

Invoke-Reboot
$name = 'Lenovo Dock Manager'
$ID = 'Lenovo.DockManager'
$AppProcess = "LenovoDockMgr"
$AppExePath = "C:\Program Files\Lenovo\Dock Manager\dockmgr.exe"

function Write-Log {
    param ($Message, $Type = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp][$Type] $Message"
    if ($Type -eq "ERROR") {
        Write-Error $entry
    } elseif ($Type -eq "WARN") {
        Write-Warning $entry
    } else {
        Write-Host $entry
    }
}

try {
    $wingetexe = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe"
    if (-not $wingetexe) {
        throw "Winget executable not found in system context."
    }

    $SystemContext = $wingetexe[-1].Path
    New-Alias -Name sysget -Value "$SystemContext"

    $lines = sysget list --accept-source-agreements --Id $ID 2>&1
    if ($lines -match '\bVersion\s+Available\b') {
        $updateLine = $lines | Where-Object { $_ -match $ID }
        $verinstalled, $verAvailable = (-split $updateLine)[-3,-2]

        Write-Log "$name update found: $verinstalled -> $verAvailable"

        # Stop app if running
        $process = Get-Process -Name "$AppProcess" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Log "Stopping $AppProcess..."
            Stop-Process -Name $AppProcess -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
        }

        Write-Log "Running winget upgrade..."
        $upgrade = sysget upgrade -e --id $ID --silent --accept-package-agreements --accept-source-agreements 2>&1
        Write-Log $upgrade

        # Validate update
        $postLines = sysget list --accept-source-agreements --Id $ID 2>&1
        $updatedLine = $postLines | Where-Object { $_ -match $ID }
        $newInstalled, $stillAvailable = (-split $updatedLine)[-3,-2]

        if ($newInstalled -eq $stillAvailable) {
            Write-Log "$name updated to $newInstalled"
        } else {
            throw "$name update failed: $newInstalled still shows older version or mismatch."
        }

        # Restart app
        if (Test-Path $AppExePath) {
            Write-Log "Restarting app from $AppExePath"
            Start-Process -FilePath $AppExePath
        } else {
            throw "Executable not found at $AppExePath – cannot restart."
        }

        exit 0
    } else {
        Write-Log "$name is up to date."
        exit 0
    }
}
catch {
    Write-Log "Remediation script failed: $_" "ERROR"
    exit 1
}

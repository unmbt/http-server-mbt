param (
    [switch]$Uninstall
)

$Repo = "unmbt/http-server-mbt"
$InstallDir = "$env:USERPROFILE\.unmbt"
$BinName = "http-server-mbt.exe"
$BinPath = Join-Path $InstallDir $BinName

if ($Uninstall) {
    Write-Host "Uninstalling $BinName..." -ForegroundColor Cyan
    if (Test-Path $BinPath) {
        Remove-Item -Path $BinPath -Force
        Write-Host "Uninstalled successfully." -ForegroundColor Green
    } else {
        Write-Host "Not installed." -ForegroundColor Yellow
    }
    return
}

$Arch = $env:PROCESSOR_ARCHITECTURE.ToLower()
if ($Arch -eq "amd64") {
    $AssetArch = "amd64"
} else {
    Write-Host "Unsupported architecture: $Arch" -ForegroundColor Red
    return
}

$AssetName = "http-server-mbt-windows-$AssetArch.exe"

Write-Host "Fetching latest version info from GitHub..." -ForegroundColor Cyan
try {
    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest"
    $LatestVersion = $Release.tag_name.TrimStart('v')
    $DownloadUrl = ($Release.assets | Where-Object { $_.name -eq $AssetName }).browser_download_url
} catch {
    Write-Host "Failed to fetch release info. Please check your network or check if a Release exists." -ForegroundColor Red
    return
}

if (-not $LatestVersion -or -not $DownloadUrl) {
    Write-Host "Failed to find the asset for Windows in the latest release." -ForegroundColor Red
    return
}

if (Test-Path $BinPath) {
    # Execute to get version
    $CurrentVersion = & $BinPath -v
    if ($CurrentVersion -eq $LatestVersion) {
        Write-Host "✨ You already have the latest version ($LatestVersion) installed at $BinPath." -ForegroundColor Green
        return
    } else {
        Write-Host "🚀 Updating from $CurrentVersion to $LatestVersion..." -ForegroundColor Cyan
    }
} else {
    Write-Host "🚀 Installing version $LatestVersion..." -ForegroundColor Cyan
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

Write-Host "Downloading $AssetName..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $DownloadUrl -OutFile $BinPath

Write-Host "`n✅ Installed http-server-mbt v$LatestVersion successfully to $BinPath" -ForegroundColor Green

$UserPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($UserPath -notmatch [regex]::Escape($InstallDir)) {
    $NewPath = $UserPath
    if ($NewPath -and -not $NewPath.EndsWith(";")) {
        $NewPath += ";"
    }
    $NewPath += $InstallDir
    [Environment]::SetEnvironmentVariable("PATH", $NewPath, "User")
    Write-Host "✅ Automatically added $InstallDir to your system PATH!" -ForegroundColor Green
    Write-Host "💡 Note: You may need to restart your terminal for the changes to take effect." -ForegroundColor Yellow
} else {
    Write-Host "✅ $InstallDir is already in your PATH." -ForegroundColor Green
}

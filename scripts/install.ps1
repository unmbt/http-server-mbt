param (
    [switch]$Uninstall,
    [switch]$Min
)

$Repo = "unmbt/http-server-mbt"
$InstallDir = "$env:USERPROFILE\.unmbt"
$BinName = "http-server-mbt.exe"
$BinPath = Join-Path $InstallDir $BinName
$MinBinPath = Join-Path $InstallDir "http-server-min.exe"

if ($Uninstall) {
    Write-Host "Uninstalling $BinName..." -ForegroundColor Cyan
    if (Test-Path $BinPath) {
        Remove-Item -Path $BinPath -Force
    }
    if (Test-Path $MinBinPath) {
        Remove-Item -Path $MinBinPath -Force
    }
    Write-Host "Uninstalled successfully." -ForegroundColor Green
    return
}

$Arch = $env:PROCESSOR_ARCHITECTURE.ToLower()
if ($Arch -eq "amd64") {
    $AssetArch = "amd64"
} else {
    Write-Host "Unsupported architecture: $Arch" -ForegroundColor Red
    return
}

$AssetPrefix = if ($Min) { "http-server-min" } else { "http-server-mbt" }
$VariantDesc = if ($Min) { " (min variant)" } else { "" }
$AssetName = "$AssetPrefix-windows-$AssetArch.exe"

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
    Write-Host "Failed to find the asset $AssetName for Windows in the latest release." -ForegroundColor Red
    return
}

if (Test-Path $BinPath) {
    # Execute to get version
    $CurrentVersion = & $BinPath -v
    if ($CurrentVersion -eq $LatestVersion) {
        Write-Host "✨ You already have the latest version ($LatestVersion$VariantDesc) installed at $BinPath." -ForegroundColor Green
        if ($Min -and -not (Test-Path $MinBinPath)) {
            Copy-Item -Path $BinPath -Destination $MinBinPath -Force -ErrorAction SilentlyContinue
        }
        return
    } else {
        Write-Host "🚀 Updating from $CurrentVersion to $LatestVersion$VariantDesc..." -ForegroundColor Cyan
    }
} else {
    Write-Host "🚀 Installing version $LatestVersion$VariantDesc..." -ForegroundColor Cyan
}

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
}

Write-Host "Downloading $AssetName..." -ForegroundColor Cyan
$TempPath = Join-Path $InstallDir "$BinName.download"
try {
    Remove-Item -Path $TempPath -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempPath -ErrorAction Stop
    if (-not (Test-Path $TempPath) -or (Get-Item $TempPath).Length -eq 0) {
        throw "The downloaded file is empty."
    }
    Move-Item -Path $TempPath -Destination $BinPath -Force -ErrorAction Stop
    if ($Min) {
        Copy-Item -Path $BinPath -Destination $MinBinPath -Force -ErrorAction SilentlyContinue
    }
} catch {
    Remove-Item -Path $TempPath -Force -ErrorAction SilentlyContinue
    Write-Host "Failed to download $AssetName. The existing installation was not changed." -ForegroundColor Red
    throw
}

if ($Min) {
    Write-Host "`n✅ Installed http-server-mbt (min) v$LatestVersion successfully to $BinPath" -ForegroundColor Green
    Write-Host "   (also available as http-server-min.exe)" -ForegroundColor Cyan
} else {
    Write-Host "`n✅ Installed http-server-mbt v$LatestVersion successfully to $BinPath" -ForegroundColor Green
}

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

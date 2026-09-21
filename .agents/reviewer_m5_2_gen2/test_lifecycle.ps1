$exe = ".\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe"
$port = 18099

Write-Host "=== Testing Server Lifecycle & Request Serving ==="
# 1. Start server in background
$proc = Start-Process -FilePath $exe -ArgumentList @("-p", $port.ToString(), "--silent") -NoNewWindow -PassThru
Write-Host "Server process started with PID: $($proc.Id)"

# 2. Wait 1 second for listener to bind
Start-Sleep -Milliseconds 800

# 3. Make HTTP request
$client = New-Object System.Net.WebClient
try {
    $resp = $client.DownloadString("http://127.0.0.1:$port/moon.mod")
    Write-Host "HTTP GET successful, received bytes: $($resp.Length)"
    Write-Host "Response preview: $($resp.Substring(0, [Math]::Thin(50, $resp.Length)))"
} catch {
    Write-Host "HTTP request failed: $_"
}

# 4. Stop the process gracefully
Write-Host "Stopping process $($proc.Id)..."
Stop-Process -Id $proc.Id -Force
$proc.WaitForExit(3000)
Write-Host "Process exited: $($proc.HasExited)"

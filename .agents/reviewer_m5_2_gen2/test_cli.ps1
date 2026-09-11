$exe = ".\_build\native\release\build\cmd\http-server-mbt\http-server-mbt.exe"

function Run-Test($name, $argsList) {
    Write-Host "=== $name ==="
    $stdoutFile = [System.IO.Path]::GetTempFileName()
    $stderrFile = [System.IO.Path]::GetTempFileName()
    $proc = Start-Process -FilePath $exe -ArgumentList $argsList -NoNewWindow -PassThru -Wait -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
    $stdout = Get-Content $stdoutFile -Raw -ErrorAction SilentlyContinue
    $stderr = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
    Remove-Item $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
    Write-Host "ExitCode: $($proc.ExitCode)"
    if ($stdout) { Write-Host "Stdout: $stdout" }
    if ($stderr) { Write-Host "Stderr: $stderr" }
}

Run-Test "Test 1: Help (-h)" @("-h")
Run-Test "Test 2: Version (-v)" @("-v")
Run-Test "Test 3: Invalid Port 0 (-p 0)" @("-p", "0")
Run-Test "Test 4: Invalid Port 99999 (-p 99999)" @("-p", "99999")
Run-Test "Test 5: Non-numeric Port (-p abc)" @("-p", "abc")
Run-Test "Test 6: Non-existent root directory" @("./non_existent_folder_98765")
Run-Test "Test 7: Mutual exclusion (--spa vs --try-files)" @("--spa", "--try-files", "index.html")
Run-Test "Test 8: Invalid Flag (--unknown)" @("--unknown")
Run-Test "Test 9: Invalid cache (-c -2)" @("-c", "-2")
Run-Test "Test 10: Invalid basic auth (-a :pass)" @("-a", ":pass")
Run-Test "Test 11: BaseURL conflict" @("--base-url", "/app", "--base-dir", "/other")

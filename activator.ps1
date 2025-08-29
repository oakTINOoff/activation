if (-not $args) {
    Write-Host "`nNeed help? Check our repo: " -NoNewline
    Write-Host "https://github.com/oakTINOoff/activation" -ForegroundColor Green
    Write-Host ""
}

& {
    $psv = (Get-Host).Version.Major

    # --- Language Mode Check ---
    if ($ExecutionContext.SessionState.LanguageMode.value__ -ne 0) {
        Write-Host $ExecutionContext.SessionState.LanguageMode
        Write-Host "PowerShell is not running in Full Language Mode."
        return
    }

    # --- .NET Functionality Check ---
    try {
        [void][System.AppDomain]::CurrentDomain.GetAssemblies()
        [void][System.Math]::Sqrt(144)
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "PowerShell failed to load .NET commands."
        return
    }

    # --- Functions ---
    function Check3rdAV {
        $cmd = if ($psv -ge 3) { 'Get-CimInstance' } else { 'Get-WmiObject' }
        $avList = & $cmd -Namespace root\SecurityCenter2 -Class AntiVirusProduct |
                  Where-Object { $_.displayName -notlike '*windows*' } |
                  Select-Object -ExpandProperty displayName

        if ($avList) {
            Write-Host '3rd party Antivirus might be blocking the script - ' -ForegroundColor White -BackgroundColor Blue -NoNewline
            Write-Host " $($avList -join ', ')" -ForegroundColor DarkRed -BackgroundColor White
        }
    }

    function CheckFile([string]$FilePath) {
        if (-not (Test-Path $FilePath)) {
            Check3rdAV
            Write-Host "Failed to create temp file, aborting!"
            throw
        }
    }

    # --- Ensure TLS 1.2 ---
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

    # --- Download Script (your repo only) ---
    $URL = 'https://raw.githubusercontent.com/oakTINOoff/activation/refs/heads/main/MAS_AIO.bat'

    Write-Progress -Activity "Downloading..." -Status "Please wait"
    try {
        $response = if ($psv -ge 3) {
            Invoke-RestMethod $URL
        } else {
            (New-Object Net.WebClient).DownloadString($URL)
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Failed to retrieve file from: $URL"
        return
    }
    Write-Progress -Activity "Downloading..." -Status "Done" -Completed

    if (-not $response) {
        Check3rdAV
        Write-Host "Failed to retrieve file, aborting!"
        return
    }

    # --- Autorun Registry Check ---
    $autorunPaths = "HKCU:\SOFTWARE\Microsoft\Command Processor", "HKLM:\SOFTWARE\Microsoft\Command Processor"
    foreach ($path in $autorunPaths) {
        if (Get-ItemProperty -Path $path -Name "Autorun" -ErrorAction SilentlyContinue) {
            Write-Warning "Autorun registry found, CMD may crash! `nRun:`nRemove-ItemProperty -Path '$path' -Name 'Autorun'"
        }
    }

    # --- Save Script ---
    $rand     = [Guid]::NewGuid().Guid
    $isAdmin  = [bool]([Security.Principal.WindowsIdentity]::GetCurrent().Groups -match 'S-1-5-32-544')
    $FilePath = if ($isAdmin) { "$env:SystemRoot\Temp\MAS_$rand.bat" } else { "$env:USERPROFILE\AppData\Local\Temp\MAS_$rand.bat" }

    Set-Content -Path $FilePath -Value "@::: $rand `r`n$response"
    CheckFile $FilePath

    # --- CMD Check ---
    $env:ComSpec = "$env:SystemRoot\system32\cmd.exe"
    $chkcmd = & $env:ComSpec /c "echo CMD is working"
    if ($chkcmd -notcontains "CMD is working") {
        Write-Warning "cmd.exe is not working."
    }

    # --- Run Script ---
    if ($psv -lt 3) {
        if (Test-Path "$env:SystemRoot\Sysnative") {
            Write-Warning "Running under x86 PowerShell. Use x64 PowerShell instead..."
            return
        }
        $p = Start-Process -FilePath $env:ComSpec -ArgumentList "/c """"$FilePath"" -el -qedit $args""" -Verb RunAs -PassThru
        $p.WaitForExit()
    }
    else {
        Start-Process -FilePath $env:ComSpec -ArgumentList "/c """"$FilePath"" -el $args""" -Wait -Verb RunAs
    }

    # --- Cleanup ---
    CheckFile $FilePath
    $FilePaths = @("$env:SystemRoot\Temp\MAS*.bat", "$env:USERPROFILE\AppData\Local\Temp\MAS*.bat")
    foreach ($FilePath in $FilePaths) { Get-Item $FilePath -ErrorAction SilentlyContinue | Remove-Item }
} @args

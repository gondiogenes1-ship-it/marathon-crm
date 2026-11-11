param([int]$Port = 8123, [switch]$NoBrowser)
$ErrorActionPreference = 'Stop'
try {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    $publicRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'public')).ToLowerInvariant()
    $serverFile = Join-Path $PSScriptRoot 'servidor.cjs'
    $localUrl = 'http://127.0.0.1:' + $Port + '/'
    $logFolder = Join-Path $PSScriptRoot 'logs'
    New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
    function Get-MarathonHealth {
        try { return Invoke-RestMethod -Uri ($localUrl + '__marathon_local_health') -TimeoutSec 1 } catch { return $null }
    }
    function Test-MarathonHealth($value) {
        return ($null -ne $value -and $value.application -eq 'marathon-crm-local' -and $value.root -eq $publicRoot)
    }
    $health = Get-MarathonHealth
    if (-not (Test-MarathonHealth $health)) {
        $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
        if ($listener) { throw "El puerto $Port esta ocupado por otra aplicacion. No se inicio Marathon." }
        $nodeExe = Join-Path $projectRoot 'runtime\node.exe'
        if (-not (Test-Path -LiteralPath $nodeExe)) { throw 'Falta el componente incluido. Extrae el ZIP completo y reinstala Marathon.' }
        Start-Process -FilePath $nodeExe -ArgumentList @(('"' + $serverFile + '"'), $Port.ToString()) -WorkingDirectory $projectRoot -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logFolder "servidor-$Port.log") -RedirectStandardError (Join-Path $logFolder "errores-$Port.log") | Out-Null
        for ($attempt = 0; $attempt -lt 25; $attempt++) {
            $health = Get-MarathonHealth
            if (Test-MarathonHealth $health) { break }
            Start-Sleep -Milliseconds 160
        }
        if (-not (Test-MarathonHealth $health)) { throw "No se pudo iniciar Marathon. Revisa local\logs\errores-$Port.log." }
    }
    [IO.File]::WriteAllText((Join-Path $logFolder "servidor-$Port.pid"), [string]$health.pid)
    if (-not $NoBrowser) {
        $browsers = @(
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe')
        )
        $browserExe = $browsers | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($browserExe) { Start-Process -FilePath $browserExe -ArgumentList @(('--app=' + $localUrl), '--new-window') }
        else { Start-Process $localUrl }
    }
    Write-Output ('Marathon listo: ' + $localUrl + ' | version ' + $health.version)
} catch {
    if ($NoBrowser) { throw }
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Marathon CRM local', 'OK', 'Error') | Out-Null
    exit 1
}

param([int]$Port = 8123)
$ErrorActionPreference = 'Stop'
$pidFile = Join-Path $PSScriptRoot "logs\servidor-$Port.pid"
if (-not (Test-Path -LiteralPath $pidFile)) { Write-Output 'Marathon local ya esta detenido.'; exit 0 }
$serverProcessId = [int]([IO.File]::ReadAllText($pidFile).Trim())
$expectedServer = Join-Path $PSScriptRoot 'servidor.cjs'
$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $serverProcessId" -ErrorAction SilentlyContinue
if ($processInfo) {
    if ($processInfo.Name -ne 'node.exe' -or -not $processInfo.CommandLine.Contains(('"' + $expectedServer + '"')) -or $processInfo.CommandLine -notmatch ('\s' + [regex]::Escape([string]$Port) + '\s*$')) {
        throw 'El proceso guardado no corresponde a este servidor. No se detuvo ningun proceso.'
    }
    Stop-Process -Id $serverProcessId
    Wait-Process -Id $serverProcessId -Timeout 5 -ErrorAction SilentlyContinue
}
Remove-Item -LiteralPath $pidFile
Write-Output 'Servidor de Marathon local detenido.'

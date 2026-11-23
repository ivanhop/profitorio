# Start (or stop) an isolated headless copy of the colin save. Never touches %APPDATA%\Factorio.
#   .\instance.ps1 -Dir <empty dir> -Slot 1            # RCON 127.0.0.1:27120+Slot, game port 34290+Slot
#   .\instance.ps1 -Dir <dir> -Stop                    # stops only the PID this script started
#   -Save <path>  : save to copy (default colin0.2.7). Loading takes ~15 s.
param(
  [Parameter(Mandatory)][string]$Dir,
  [int]$Slot = 1,
  [string]$Save = "$env:APPDATA\Factorio\saves\colin0.2.7.zip",
  [switch]$Stop
)
$ErrorActionPreference = 'Stop'
if ($Stop) {
  $id = Get-Content "$Dir\pid.txt"
  Stop-Process -Id $id -ErrorAction SilentlyContinue
  # Wait for the exit: a restart straight after Stop-Process can otherwise race the old server for
  # the ports, and RCON may still reach the old process (round 3 saw a "fresh" copy with H defined).
  Wait-Process -Id $id -Timeout 30 -ErrorAction SilentlyContinue
  return
}
$exe = "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
New-Item -ItemType Directory -Force "$Dir\mods","$Dir\saves","$Dir\config" | Out-Null
if (-not (Test-Path "$Dir\mods\mod-list.json")) {
  # Hardlinks, not copies: ~3.7 GB of mods. Factorio never writes into mod zips.
  Get-ChildItem "$env:APPDATA\Factorio\mods" -File -Filter *.zip | ForEach-Object {
    New-Item -ItemType HardLink -Path "$Dir\mods\$($_.Name)" -Target $_.FullName | Out-Null }
  Copy-Item "$env:APPDATA\Factorio\mods\mod-list.json","$env:APPDATA\Factorio\mods\mod-settings.dat" "$Dir\mods\"
}
Copy-Item $Save "$Dir\saves\colin.zip" -Force
$wf = $Dir -replace '\\','/'
"[path]`nread-data=C:/Program Files (x86)/Steam/steamapps/common/Factorio/data`nwrite-data=$wf" |
  Set-Content "$Dir\config\config.ini" -Encoding utf8
# A minimal server-settings file fails (Key "description" not found); start from the example.
Get-Content "C:\Program Files (x86)\Steam\steamapps\common\Factorio\data\server-settings.example.json" -Raw |
  ConvertFrom-Json | ForEach-Object { $_.auto_pause=$false; $_.visibility.public=$false
  $_.visibility.lan=$false; $_.require_user_verification=$false; $_ } |
  ConvertTo-Json -Depth 5 | Set-Content "$Dir\server-settings.json"
Remove-Item "$Dir\out.txt" -ErrorAction SilentlyContinue
$rcon = 27120 + $Slot; $port = 34290 + $Slot
$p = Start-Process $exe -PassThru -NoNewWindow -RedirectStandardOutput "$Dir\out.txt" -RedirectStandardError "$Dir\err.txt" `
  -ArgumentList @("--config","$Dir\config\config.ini","--start-server","$Dir\saves\colin.zip",
  "--server-settings","$Dir\server-settings.json","--rcon-bind","127.0.0.1:$rcon",
  "--rcon-password","probe","--port","$port","--disable-audio")
$p.Id | Set-Content "$Dir\pid.txt"
$deadline = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $deadline) {
  if ((Test-Path "$Dir\out.txt") -and (Select-String -Path "$Dir\out.txt" -Pattern 'Starting RCON' -Quiet)) {
    "ready pid=$($p.Id) rcon=127.0.0.1:$rcon password=probe"; return }
  if ($p.HasExited) { throw "factorio exited; see $Dir\out.txt" }
  Start-Sleep -Milliseconds 500
}
throw "RCON not up after 90 s; see $Dir\out.txt"

# Запуск сетевого стенда: хост + (прокси) + клиенты, затем анализ.
# Пример: powershell -File tests/net/run.ps1 -Players 2 -Scenario pull -Latency 50 -Jitter 10 -Loss 1
param(
	[int]$Players = 2,
	[string]$Scenario = "walk",
	[double]$Duration = 12,
	[double]$Latency = 0,   # задержка в одну сторону, мс (RTT ≈ 2×)
	[double]$Jitter = 0,
	[double]$Loss = 0,      # потери, %
	[string]$Out = "",
	[int]$Floors = 3,
	[string]$Godot = $env:GODOT_CONSOLE
)
$ErrorActionPreference = "Stop"
$project = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Godot) { $Godot = Join-Path $env:USERPROFILE "Documents\Godot_v4.8-dev5\Godot_v4.8-dev5_win64_console.exe" } # версия команды
if (-not $Out) { $Out = Join-Path $env:TEMP ("sworm_net_{0}_{1}p_{2}ms_{3}" -f $Scenario, $Players, [int]($Latency * 2), (Get-Date -Format "HHmmss")) }
New-Item -ItemType Directory -Force $Out | Out-Null
$scene = "res://tests/net/net_harness.tscn"
$common = @("--path", $project, "--resolution", "640x360")
$procs = @()

function Start-Role([string]$tag, [string[]]$userArgs, [int]$x) {
	$log = Join-Path $Out "$tag.log"
	$a = $common + @("--position", "$x,40", $scene, "--") + $userArgs + @("out=$Out", "tag=$tag", "players=$Players", "scenario=$Scenario", "duration=$Duration", "floors=$Floors", "timeout=$([int](60 + $Floors * 25))")
	return Start-Process $Godot -ArgumentList $a -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
}

$procs += Start-Role "host" @("role=host", "class=0") 0
$clientPort = 7010
if ($Latency -gt 0 -or $Jitter -gt 0 -or $Loss -gt 0) {
	$clientPort = 7011
	$proxy = Start-Role "proxy" @("role=proxy", "listen=7011", "target=7010", "latency=$Latency", "jitter=$Jitter", "loss=$Loss", "lifetime=150") -1000
}
for ($i = 1; $i -lt $Players; $i++) {
	$cls = @(2, 1, 3)[($i - 1) % 3]
	$procs += Start-Role "c$i" @("role=client", "port=$clientPort", "class=$cls", "delay=$(0.8 + 0.4 * $i)") (650 * $i)
}

$game = $procs | Where-Object { $_ -ne $null } # прокси не ждём — закрываем после игры
if ($proxy) { $procs += $proxy }
$deadline = (Get-Date).AddSeconds(150)
foreach ($p in $game) { $left = [int](($deadline - (Get-Date)).TotalMilliseconds); if ($left -lt 1 -or -not $p.WaitForExit($left)) { try { $p.Kill() } catch {} } }
Get-Process -Id ($procs.Id) -ErrorAction SilentlyContinue | Stop-Process -Force
Get-ChildItem $Out -Filter *.err | ForEach-Object {
	$errs = Get-Content $_.FullName | Select-String "SCRIPT ERROR|^ERROR" | Where-Object { $_ -notmatch "never freed|still in use" }
	if ($errs) { "--- ошибки $($_.Name):"; $errs | Select-Object -First 8 }
}
python "$PSScriptRoot\analyze.py" $Out

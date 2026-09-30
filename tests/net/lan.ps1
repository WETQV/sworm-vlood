# Замер на реальной сети (LAN / Radmin VPN): каждый участник запускает скрипт на своём компьютере.
#
# Хост (запускать первым):
#   powershell -ExecutionPolicy Bypass -File tests/net/lan.ps1 -Role host -Players 2 -Scenario combat
# Клиент (IP хоста — из лобби игры или Radmin VPN):
#   powershell -ExecutionPolicy Bypass -File tests/net/lan.ps1 -Role client -HostIp 26.x.x.x -Players 2 -Scenario combat -Tag c1
#
# После прогона каждый клиент отправляет хосту свою папку (путь печатается в конце); хост складывает
# все папки в одну и запускает: python tests/net/analyze.py <общая_папка>
# Часы разных компьютеров выравниваются автоматически (CLOCK_OFFSET по пингу).
param(
	[Parameter(Mandatory = $true)][ValidateSet("host", "client")][string]$Role,
	[string]$HostIp = "",
	[int]$Players = 2,
	[ValidateSet("walk", "pull", "combat", "integrity", "floors")][string]$Scenario = "combat",
	[double]$Duration = 15,
	[int]$Floors = 3,
	[string]$Tag = "",
	[string]$Out = "",
	[string]$Godot = $env:GODOT_CONSOLE
)
$ErrorActionPreference = "Stop"
$project = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $Godot) { $Godot = Join-Path $env:USERPROFILE "Documents\Godot_v4.8-dev5\Godot_v4.8-dev5_win64_console.exe" }
if (-not (Test-Path $Godot)) { throw "Не найден Godot: $Godot (укажите -Godot или переменную GODOT_CONSOLE)" }
if ($Role -eq "client" -and -not $HostIp) { throw "Для клиента нужен -HostIp" }
if (-not $Tag) { $Tag = if ($Role -eq "host") { "host" } else { "c_" + $env:COMPUTERNAME.ToLower() } }
if (-not $Out) { $Out = Join-Path $env:TEMP ("sworm_lan_{0}_{1}p_{2}_{3}" -f $Scenario, $Players, $Tag, (Get-Date -Format "HHmmss")) }
New-Item -ItemType Directory -Force $Out | Out-Null

$userArgs = @("role=$Role", "tag=$Tag", "out=$Out", "players=$Players", "scenario=$Scenario",
	"duration=$Duration", "floors=$Floors", "timeout=$([int](90 + $Floors * 25 + $Duration))", "class=$(if ($Role -eq 'host') { 0 } else { 2 })")
if ($Role -eq "client") { $userArgs += @("ip=$HostIp", "port=7010", "delay=0.5") }
$log = Join-Path $Out "$Tag.log"
Write-Host "Запуск ($Role, $Scenario, игроков $Players)... Хост ждёт подключения всех до 30 с."
$p = Start-Process $Godot -ArgumentList (@("--path", $project, "--resolution", "960x540", "res://tests/net/net_harness.tscn", "--") + $userArgs) `
	-RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
$p.WaitForExit()
Get-Content "$log.err" | Select-String "SCRIPT ERROR|^ERROR" | Where-Object { $_ -notmatch "never freed|still in use" } | Select-Object -First 10
Write-Host ""
Write-Host "Готово. Логи: $Out"
if ($Role -eq "client") { Write-Host "Отправьте эту папку хосту." } else { Write-Host "Сложите сюда папки клиентов и запустите: python tests/net/analyze.py `"$Out`"" }

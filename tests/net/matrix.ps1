# Матрица замеров P0: сценарии × профили сети × число игроков. Результат — один текстовый отчёт.
# Пример: powershell -File tests/net/matrix.ps1 -Report docs/net_reports/baseline.txt
param(
	[string]$Report = "",
	[int[]]$PlayerCounts = @(2, 3, 4),
	[string[]]$Scenarios = @("walk", "pull", "combat", "integrity")
)
$profiles = @(
	@{ Name = "localhost"; Latency = 0; Jitter = 0; Loss = 0 },
	@{ Name = "100ms+jitter/1%"; Latency = 50; Jitter = 10; Loss = 1 },
	@{ Name = "200ms+jitter/3%"; Latency = 100; Jitter = 25; Loss = 3 }
)
$lines = @("# SwormVlood — сетевые замеры, $(Get-Date -Format 'yyyy-MM-dd HH:mm'), ревизия $(git -C "$PSScriptRoot\..\.." rev-parse --short HEAD)", "")
foreach ($n in $PlayerCounts) {
	foreach ($s in $Scenarios) {
		if ($n -gt 2 -and $s -eq "walk") { continue } # ходьбу достаточно проверить вдвоём
		foreach ($p in $profiles) {
			$lines += "########## игроков=$n сценарий=$s профиль=$($p.Name)"
			$lines += (& "$PSScriptRoot\run.ps1" -Players $n -Scenario $s -Duration 10 -Latency $p.Latency -Jitter $p.Jitter -Loss $p.Loss 2>&1 | Out-String)
		}
	}
}
if ($Report) {
	New-Item -ItemType Directory -Force (Split-Path $Report) | Out-Null
	[IO.File]::WriteAllText($Report, ($lines -join "`n"), (New-Object Text.UTF8Encoding $false))
}
$lines

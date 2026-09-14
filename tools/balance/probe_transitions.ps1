param([string]$Godot = 'godot')
$ErrorActionPreference = 'Stop'
$BalanceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$BalanceResults = @()
foreach ($BalanceBoss in 1..6) {
    $BalanceRow = [ordered]@{boss=$BalanceBoss}
    foreach ($BalanceStage in @(($BalanceBoss-1),$BalanceBoss)) {
        $BalanceLog = Join-Path $BalanceRoot ".godot/balance_transition_${BalanceBoss}_${BalanceStage}.log"
        & $Godot --headless --path $BalanceRoot --log-file $BalanceLog --script res://tools/balance/simulate_campaign.gd -- --seed=102 --probe-from=res://artifacts/balance/v2_auction_102_100.json --probe-boss=$BalanceBoss --probe-stage=$BalanceStage --probe-mining --probe-bulk
        if ($LASTEXITCODE -ne 0) { throw "Transition probe failed: $BalanceBoss / $BalanceStage" }
        $BalanceLines = Get-Content -LiteralPath $BalanceLog -Encoding UTF8
        if ($BalanceLines | Select-String 'SCRIPT ERROR|Parse Error') { throw "Script error in $BalanceLog" }
        $BalanceLine = $BalanceLines | Where-Object { $_.StartsWith('BUILD_PROBE ') } | Select-Object -Last 1
        if (-not $BalanceLine) { throw "Missing result in $BalanceLog" }
        $BalanceSide = if ($BalanceStage -eq $BalanceBoss) { 'after' } else { 'before' }
        $BalanceRow[$BalanceSide] = $BalanceLine.Substring(12) | ConvertFrom-Json
    }
    $BalanceResults += $BalanceRow
}
$BalanceJson = ConvertTo-Json -InputObject $BalanceResults -Depth 20
[IO.File]::WriteAllText((Join-Path $BalanceRoot 'docs/balance/transitions.json'),$BalanceJson,(New-Object System.Text.UTF8Encoding($false)))
Write-Output 'BALANCE_TRANSITIONS_OK'

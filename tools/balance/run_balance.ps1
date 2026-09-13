param(
    [string]$Godot = 'godot',
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$BalanceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$BalanceLogs = Join-Path $BalanceRoot '.godot'
New-Item -ItemType Directory -Path $BalanceLogs -Force | Out-Null
function Invoke-BalanceGodot([string]$Script, [string]$Tag, [string[]]$Arguments = @()) {
    $BalanceLog = Join-Path $BalanceLogs ($Tag + '.log')
    & $Godot --headless --path $BalanceRoot --log-file $BalanceLog --script $Script -- @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Godot failed: $Tag" }
    if (Select-String -LiteralPath $BalanceLog -Pattern 'SCRIPT ERROR|Parse Error|failures=[1-9]|FAILED|TIMEOUT' -Quiet) {
        throw "Validation error in $BalanceLog"
    }
}
Invoke-BalanceGodot 'res://tests/validate_balance.gd' 'balance_check_balance'
$BalanceCases = @(
    @('balanced', '101', '1.0'), @('balanced', '404', '1.0'),
    @('economy', '303', '1.0'), @('auction', '606', '1.0'),
    @('balanced', '202', '0.85'), @('balanced', '505', '1.15')
)
foreach ($BalanceCase in $BalanceCases) {
    Invoke-BalanceGodot 'res://tools/balance/simulate_campaign.gd' ("balance_final_{0}_{1}" -f $BalanceCase[0],$BalanceCase[1]) @(
        "--policy=$($BalanceCase[0])", "--seed=$($BalanceCase[1])", "--efficiency=$($BalanceCase[2])"
    )
}
Invoke-BalanceGodot 'res://tools/balance/export_balance.gd' 'balance_export'
& $Python (Join-Path $PSScriptRoot 'write_report.py')
if ($LASTEXITCODE -ne 0) { throw 'Balance report generation failed' }

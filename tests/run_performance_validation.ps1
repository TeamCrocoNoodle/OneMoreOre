param(
    [ValidateSet('Core','Capture','All')][string]$Suite = 'Core',
    [string]$Godot = 'godot'
)
$ErrorActionPreference = 'Stop'
$PerformanceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
function Invoke-PerformanceCheck([string]$Script) {
    $PerformanceLog = Join-Path $PerformanceRoot ('.godot/performance_' + $Script + '.log')
    & $Godot --headless --path $PerformanceRoot --log-file $PerformanceLog --script "res://tests/$Script.gd"
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $PerformanceLog -Pattern 'SCRIPT ERROR|Parse Error|failures=[1-9]|FAILED|TIMEOUT|Leaked instance|RID allocations' -Quiet)) {
        throw "Failed: $Script; inspect $PerformanceLog"
    }
}
if ($Suite -ne 'Capture') {
    foreach ($PerformanceTest in @('validate_extreme_mining','validate_ore_preparation','validate_ore_progression','validate_mining','validate_skills','validate_aux_tools','validate_bosses','validate_round','validate_attack_range','validate_crack_wrap','validate_gems')) {
        Invoke-PerformanceCheck $PerformanceTest
    }
}
if ($Suite -ne 'Core') {
    $PerformanceCaptureLog = Join-Path $PerformanceRoot '.godot/extreme_gpu_after.log'
    & $Godot --path $PerformanceRoot --log-file $PerformanceCaptureLog --script res://tests/profile_extreme_mining.gd -- --tag=gpu_after
    if ($LASTEXITCODE -ne 0 -or (Select-String -LiteralPath $PerformanceCaptureLog -Pattern 'SCRIPT ERROR|Parse Error|FAILED|TIMEOUT|Leaked instance|RID allocations' -Quiet)) {
        throw "Capture failed; inspect $PerformanceCaptureLog"
    }
}

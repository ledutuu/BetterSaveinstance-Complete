param([Parameter(Mandatory)][string]$LuauCLI)
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$generated = Join-Path $repo 'build/regressions'
New-Item -ItemType Directory -Path $generated -Force | Out-Null
foreach ($name in @('core','extra','performance','startup','discovery')) {
    $builder = Join-Path $PSScriptRoot "Build-$name.ps1"
    $script = Join-Path $generated "$name.luau"
    & $builder -Repo $repo -Out $script
    & $LuauCLI $script
    if ($LASTEXITCODE -ne 0) { throw "$name regressions failed: exit $LASTEXITCODE" }
}

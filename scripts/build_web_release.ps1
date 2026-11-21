param(
    [string]$FlutterCommand = 'flutter'
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$definesPath = Join-Path $projectRoot 'flutter_defines.env'
if (-not (Test-Path -LiteralPath $definesPath -PathType Leaf)) {
    throw 'The Flutter environment file is missing.'
}

$publicValues = @{}
foreach ($line in Get-Content -LiteralPath $definesPath) {
    if ($line -match '^\s*([^#=\s]+)\s*=\s*(.*)$') {
        $publicValues[$Matches[1]] = $Matches[2].Trim()
    }
}
$supabaseUrl = $publicValues['SUPABASE_URL']
$publishableKey = $publicValues['SUPABASE_PUBLISHABLE_KEY']
$parsedUrl = $null
if (-not [Uri]::TryCreate($supabaseUrl, [UriKind]::Absolute, [ref]$parsedUrl) -or
    $parsedUrl.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($publishableKey) -or
    $publishableKey.StartsWith('sb_secret_')) {
    throw 'A public HTTPS Supabase URL and publishable key are required.'
}

Push-Location -LiteralPath $projectRoot
try {
    & $FlutterCommand build web --release --no-pub `
        '--dart-define-from-file=flutter_defines.env' `
        '--dart-define=GAME_REMOTE_ENABLED=true' `
        '--dart-define=GAME_DRAW_ENABLED=true' `
        '--dart-define=GAME_STAGE_REWARDS_ENABLED=true' `
        '--dart-define=GOAL_SYNC_ENABLED=true' `
        '--dart-define=DAILY_SYNC_ENABLED=true'
    if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed.' }

    $config = @{
        supabaseUrl = $supabaseUrl
        publishableKey = $publishableKey
    } | ConvertTo-Json -Compress
    $configPath = Join-Path $projectRoot 'build/web/delete-account-config.js'
    [System.IO.File]::WriteAllText(
        $configPath,
        "window.GROWUP_ACCOUNT_DELETE_CONFIG = $config;",
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Output 'Web release and account deletion page are ready in build/web.'
} finally {
    Pop-Location
}

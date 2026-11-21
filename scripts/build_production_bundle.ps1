param(
    [string]$FlutterCommand = 'flutter',
    [switch]$AccountDeletionVerified
)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path

if (-not $AccountDeletionVerified) {
    throw 'Verify the deployed in-app and external account deletion flows, then pass -AccountDeletionVerified.'
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'flutter_defines.env') -PathType Leaf)) {
    throw 'The Flutter environment file is missing.'
}

& (Join-Path $PSScriptRoot 'release_preflight.ps1')

$appId = $env:ORG_GRADLE_PROJECT_GROWUP_APPLICATION_ID
$env:ORG_GRADLE_PROJECT_GROWUP_REQUIRE_PRODUCTION_SIGNING = 'true'
Push-Location -LiteralPath $projectRoot
try {
    & $FlutterCommand build appbundle --release --no-pub `
        '--dart-define-from-file=flutter_defines.env' `
        "--dart-define=LOGIN_REDIRECT_SCHEME=$appId" `
        "--dart-define=PRIVACY_POLICY_URL=$env:GROWUP_PRIVACY_POLICY_URL" `
        "--dart-define=ACCOUNT_DELETION_URL=$env:GROWUP_ACCOUNT_DELETION_URL" `
        '--dart-define=ACCOUNT_DELETION_ENABLED=true' `
        '--dart-define=GAME_REMOTE_ENABLED=true' `
        '--dart-define=GAME_DRAW_ENABLED=true' `
        '--dart-define=GAME_STAGE_REWARDS_ENABLED=true' `
        '--dart-define=DAILY_SYNC_ENABLED=true'
    if ($LASTEXITCODE -ne 0) { throw 'Flutter app bundle build failed.' }
} finally {
    Pop-Location
}

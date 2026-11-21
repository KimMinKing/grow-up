param(
    [string]$ApplicationId = $env:ORG_GRADLE_PROJECT_GROWUP_APPLICATION_ID,
    [string]$PrivacyPolicyUrl = $env:GROWUP_PRIVACY_POLICY_URL,
    [string]$AccountDeletionUrl = $env:GROWUP_ACCOUNT_DELETION_URL
)

$ErrorActionPreference = 'Stop'
$issues = [System.Collections.Generic.List[string]]::new()

if ($ApplicationId -eq 'com.example.growup' -or
    $ApplicationId -notmatch '^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$') {
    $issues.Add('Choose a permanent, non-example Android application ID.')
}

if ([string]::IsNullOrWhiteSpace($env:GROWUP_RELEASE_STORE_FILE) -or
    -not (Test-Path -LiteralPath $env:GROWUP_RELEASE_STORE_FILE -PathType Leaf)) {
    $issues.Add('Set GROWUP_RELEASE_STORE_FILE to an existing upload keystore.')
}
if (-not [string]::IsNullOrWhiteSpace($env:GROWUP_RELEASE_STORE_FILE) -and
    (Split-Path -Path $env:GROWUP_RELEASE_STORE_FILE -Leaf) -ieq 'debug.keystore') {
    $issues.Add('Use a separate upload keystore instead of Android Debug.')
}

foreach ($name in @('GROWUP_RELEASE_STORE_PASSWORD', 'GROWUP_RELEASE_KEY_ALIAS',
                    'GROWUP_RELEASE_KEY_PASSWORD')) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        $issues.Add("Set $name before building a release.")
    }
}

foreach ($item in @(
    @{ Name = 'privacy policy'; Value = $PrivacyPolicyUrl },
    @{ Name = 'external account deletion'; Value = $AccountDeletionUrl }
)) {
    $uri = $null
    if (-not [Uri]::TryCreate($item.Value, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or [string]::IsNullOrWhiteSpace($uri.Host)) {
        $issues.Add("Set a public HTTPS URL for $($item.Name).")
    }
}

if ($issues.Count -gt 0) {
    throw "Release configuration needs:`n- $($issues -join "`n- ")"
}
Write-Output 'Local release configuration is present. Check hosted pages and deletion service before publishing.'

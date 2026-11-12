<#
.SYNOPSIS
  Registers the four PayamYar Android release-signing secrets in GitHub Actions — safely.

.DESCRIPTION
  * Reads the permanent keystore (payamyar-release.p12) and the private JSON file that
    came with it, or asks for any missing value with a hidden prompt.
  * BEFORE writing anything to GitHub it checks that:
      - GitHub CLI is installed and logged in with admin rights on the repository;
      - the keystore opens with the given password;
      - the certificate SHA-256 equals the pinned public value
        A82C3ACB328F3D6DE57D60297F8E2DCBD7384AAAE5172B5FBEEC38B3E31BBE0F
        (so a wrong or new key can never be uploaded by mistake).
  * Secrets are sent to `gh secret set` through standard input (no trailing newline,
    never on the command line, never written to a temp file, never printed).

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Set-PayamYar-GitHub-Secrets.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\Set-PayamYar-GitHub-Secrets.ps1 -RunWorkflow
#>
[CmdletBinding()]
param(
    [string]$KeystorePath = (Join-Path $PSScriptRoot 'payamyar-release.p12'),
    [string]$SecretsJson  = (Join-Path $PSScriptRoot 'PayamYar-RELEASE-SECRETS-PRIVATE.json'),
    [string]$Repo         = 'seyedebrahim0211-oss/PayamYar',
    [string]$ExpectedSha256 = 'A82C3ACB328F3D6DE57D60297F8E2DCBD7384AAAE5172B5FBEEC38B3E31BBE0F',
    [switch]$VerifyOnly,
    [switch]$RunWorkflow
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

function Step($text) { Write-Host "`n» $text" -ForegroundColor Cyan }
function Ok($text)   { Write-Host "  ✓ $text" -ForegroundColor Green }
function Fail($text) { Write-Host "  ✗ $text" -ForegroundColor Red; exit 1 }

function ConvertTo-Plain([Security.SecureString]$secure) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

# Finds a value in the private JSON under any of several common key spellings.
function Get-JsonValue($json, [string[]]$names) {
    if ($null -eq $json) { return $null }
    foreach ($prop in $json.PSObject.Properties) {
        $normalized = ($prop.Name -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
        foreach ($n in $names) {
            if ($normalized -eq (($n -replace '[^a-zA-Z0-9]', '').ToLowerInvariant())) {
                $v = [string]$prop.Value
                if ($v.Trim().Length -gt 0) { return $v }
            }
        }
        if ($prop.Value -is [System.Management.Automation.PSCustomObject]) {
            $nested = Get-JsonValue $prop.Value $names
            if ($nested) { return $nested }
        }
    }
    return $null
}

function Set-GhSecret([string]$name, [string]$value) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'gh'
    $psi.Arguments = "secret set $name --repo $Repo"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($value)   # no newline appended
    $p.StandardInput.Close()
    $null = $p.StandardOutput.ReadToEnd()
    $err = $p.StandardError.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { Fail "ثبت $name ناموفق بود: $($err.Trim())" }
    Ok "$name ثبت شد"
}

Write-Host 'پیامیار — ثبت امن کلید امضای دائمی در GitHub Actions' -ForegroundColor Yellow
Write-Host 'هیچ رمز یا کلیدی روی صفحه نمایش داده نمی‌شود.'

Step 'بررسی GitHub CLI و دسترسی مدیر مخزن'
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Fail 'GitHub CLI نصب نیست. اجرا کنید: winget install --id GitHub.cli -e'
}
& gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host '  ورود به GitHub لازم است؛ پنجره مرورگر باز می‌شود. فقط ورود را تأیید کنید.'
    & gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Fail 'ورود به GitHub انجام نشد.' }
}
$admin = (& gh api "repos/$Repo" --jq '.permissions.admin' 2>$null)
if ("$admin".Trim() -ne 'true') { Fail "حساب واردشده دسترسی Admin روی $Repo ندارد." }
Ok "دسترسی Admin روی $Repo تأیید شد"

Step 'خواندن فایل کلید و مشخصات محرمانه'
if (-not (Test-Path -LiteralPath $KeystorePath)) {
    $picked = Read-Host 'مسیر فایل payamyar-release.p12 را وارد کنید'
    $KeystorePath = $picked.Trim('"', ' ')
}
if (-not (Test-Path -LiteralPath $KeystorePath)) { Fail 'فایل کلید پیدا نشد.' }
$keystoreBytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $KeystorePath))
if ($keystoreBytes.Length -lt 512 -or $keystoreBytes.Length -gt 64KB) { Fail 'فایل کلید معتبر به نظر نمی‌رسد.' }
Ok "فایل کلید خوانده شد ($($keystoreBytes.Length) بایت)"

$json = $null
if (Test-Path -LiteralPath $SecretsJson) {
    try { $json = Get-Content -LiteralPath $SecretsJson -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { Fail 'فایل JSON محرمانه قابل خواندن نیست (ساختار نامعتبر).' }
    Ok 'فایل JSON محرمانه پیدا شد'
} else {
    Write-Host '  فایل JSON پیدا نشد؛ مقادیر به‌صورت پنهان پرسیده می‌شوند.' -ForegroundColor DarkYellow
}

$storePass = Get-JsonValue $json @('PAYAMYAR_KEYSTORE_PASSWORD','keystorePassword','storePassword','store_password','keystore_password','storepass')
$alias     = Get-JsonValue $json @('PAYAMYAR_KEY_ALIAS','keyAlias','key_alias','alias')
$keyPass   = Get-JsonValue $json @('PAYAMYAR_KEY_PASSWORD','keyPassword','key_password','keypass')
if (-not $storePass) { $storePass = ConvertTo-Plain (Read-Host 'رمز Keystore' -AsSecureString) }
if (-not $alias)     { $alias = (Read-Host 'نام مستعار کلید (Key alias)').Trim() }
if (-not $keyPass)   {
    $entered = ConvertTo-Plain (Read-Host 'رمز کلید (اگر با رمز Keystore یکی است Enter بزنید)' -AsSecureString)
    $keyPass = if ($entered) { $entered } else { $storePass }
}
if (-not $storePass -or -not $alias -or -not $keyPass) { Fail 'هر چهار مقدار لازم است.' }
Ok 'چهار مقدار آماده است (نمایش داده نمی‌شوند)'

Step 'تطبیق اثر انگشت گواهی با مقدار ثبت‌شده در مخزن'
try {
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
} catch {
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet
}
$collection = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
try { $collection.Import($keystoreBytes, $storePass, $flags) }
catch { Fail 'رمز Keystore نادرست است یا فایل کلید خراب است.' }
$cert = $collection | Where-Object { $_.HasPrivateKey } | Select-Object -First 1
if (-not $cert) { $cert = $collection | Select-Object -First 1 }
if (-not $cert) { Fail 'گواهی داخل فایل کلید پیدا نشد.' }
$sha = [System.Security.Cryptography.SHA256]::Create()
$actual = ([BitConverter]::ToString($sha.ComputeHash($cert.RawData))).Replace('-', '')
if ($actual -ne $ExpectedSha256.ToUpperInvariant()) {
    Fail "این کلید، کلید دائمی پیامیار نیست (اثر انگشت: $actual). هیچ Secretی ثبت نشد."
}
Ok "گواهی دائمی تأیید شد: $actual"

$keytool = $null
foreach ($candidate in @("$env:JAVA_HOME\bin\keytool.exe",
                         "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
                         "$env:ProgramFiles\Android\Android Studio\jre\bin\keytool.exe")) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { $keytool = $candidate; break }
}
if (-not $keytool) { $cmd = Get-Command keytool -ErrorAction SilentlyContinue; if ($cmd) { $keytool = $cmd.Source } }
if ($keytool) {
    # Confirms the alias exists; passwords are passed via environment variables, not arguments.
    $env:PY_SP = $storePass
    try {
        & $keytool -list -storetype PKCS12 -keystore $KeystorePath -alias $alias -storepass:env PY_SP *> $null
        if ($LASTEXITCODE -ne 0) { Fail "نام مستعار «$alias» در فایل کلید وجود ندارد." }
        Ok 'نام مستعار کلید با keytool تأیید شد'
    } finally { Remove-Item Env:\PY_SP -ErrorAction SilentlyContinue }
} else {
    Write-Host '  keytool پیدا نشد؛ نام مستعار در اولین ساخت GitHub بررسی می‌شود.' -ForegroundColor DarkYellow
}

if ($VerifyOnly) { Write-Host "`nبررسی کامل شد؛ با -VerifyOnly چیزی در GitHub ثبت نشد." -ForegroundColor Yellow; exit 0 }

Step 'ثبت رمزگذاری‌شده چهار Secret در GitHub'
Set-GhSecret 'PAYAMYAR_KEYSTORE_BASE64'   ([Convert]::ToBase64String($keystoreBytes))
Set-GhSecret 'PAYAMYAR_KEYSTORE_PASSWORD' $storePass
Set-GhSecret 'PAYAMYAR_KEY_ALIAS'         $alias
Set-GhSecret 'PAYAMYAR_KEY_PASSWORD'      $keyPass
$storePass = $null; $keyPass = $null; [GC]::Collect()

Step 'نام Secretهای موجود (بدون مقدار)'
& gh secret list --repo $Repo

if ($RunWorkflow) {
    Step 'اجرای ساخت رسمی روی main'
    & gh workflow run build.yml --repo $Repo --ref main
    if ($LASTEXITCODE -eq 0) { Ok "ساخت آغاز شد: https://github.com/$Repo/actions" }
}
Write-Host "`nتمام شد. فایل کلید و JSON را در دو محل امن آفلاین پشتیبان بگیرید و در هیچ مخزن یا پیامی قرار ندهید." -ForegroundColor Yellow

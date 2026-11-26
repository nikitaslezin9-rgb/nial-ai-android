$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$secretPath = Join-Path $env:LOCALAPPDATA "NialAI\gigachat.credential"

if (-not (Test-Path $secretPath)) {
    throw "Нет сохраненного ключа. Повтори настройку."
}

$oldCredential = $env:GIGACHAT_CREDENTIALS

try {
    $secure = ConvertTo-SecureString -String ((Get-Content -LiteralPath $secretPath -Raw -Encoding UTF8).Trim())
    $env:GIGACHAT_CREDENTIALS =
        [System.Net.NetworkCredential]::new("", $secure).Password.Trim()

    Write-Host "Nial AI запускается. Открой http://127.0.0.1:3000"
    & "C:\Program Files\nodejs\node.exe" --use-system-ca .\server.mjs
}
finally {
    if ($null -eq $oldCredential) {
        Remove-Item Env:\GIGACHAT_CREDENTIALS -ErrorAction SilentlyContinue
    }
    else {
        $env:GIGACHAT_CREDENTIALS = $oldCredential
    }

    Remove-Variable secure, oldCredential -ErrorAction SilentlyContinue
}

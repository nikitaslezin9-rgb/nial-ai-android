$ErrorActionPreference = "Stop"

$Project = $PSScriptRoot
$env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr"
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"

$JavaBin = "$env:JAVA_HOME\bin"
$Gradle = "C:\dev\tools\gradle-9.3.1\bin\gradle.bat"
$Tools = "$env:ANDROID_HOME\build-tools\36.0.0"

$KeyDir = "$env:USERPROFILE\.nial-ai-signing"
$KeyFile = "$KeyDir\nial-release.jks"
$PasswordFile = "$KeyDir\signing-password.protected"

$Release = "$Project\app\build\outputs\apk\release"
$Unsigned = "$Release\app-release-unsigned.apk"
$Aligned = "$Release\app-release-aligned.apk"
$Final = "$Release\Nial-Ai-release.apk"

$Pointer = [IntPtr]::Zero
$Plain = $null
$Secure = $null
$FirstSave = $false

try {
    foreach ($Required in @(
        $KeyFile,
        $Gradle,
        "$JavaBin\keytool.exe",
        "$Tools\zipalign.exe",
        "$Tools\apksigner.bat"
    )) {
        if (!(Test-Path $Required)) {
            throw "Не найден файл: $Required"
        }
    }

    if (Test-Path $PasswordFile) {
        $Protected = [System.IO.File]::ReadAllText($PasswordFile).Trim()
        $Secure = ConvertTo-SecureString -String $Protected
    } else {
        $Secure = Read-Host `
            "Один раз введи пароль существующего ключа подписи APK" `
            -AsSecureString
        $FirstSave = $true
    }

    $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    $Plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)

    if ([string]::IsNullOrEmpty($Plain)) {
        throw "Введён пустой пароль."
    }

    $env:NIAL_SIGN_PASS = $Plain

    & "$JavaBin\keytool.exe" -list `
        -keystore $KeyFile `
        -alias nial-release `
        -storepass:env NIAL_SIGN_PASS

    if ($LASTEXITCODE -ne 0) {
        throw "Пароль ключа не принят. Неверный новый пароль не сохраняется. Если ошибочен уже сохранённый пароль — смотри инструкцию под блоком."
    }

    if ($FirstSave) {
        $Protected = ConvertFrom-SecureString -SecureString $Secure
        $Utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($PasswordFile, $Protected, $Utf8)
        Write-Host "Пароль подписи сохранён в защищённом виде."
    }

    $Main = "$Project\app\src\main\java\app\nial\ai\MainActivity.java"
    $MainText = [System.IO.File]::ReadAllText($Main)

    # NIAL_VOICE_BUILD_CHECK
    if (!$MainText.Contains("NIAL_VOICE_V1") -or
        !$MainText.Contains("nialVoice.onReply(result, error)")) {
        throw "Голосовой патч не найден в MainActivity.java."
    }

    $VoiceSource = "$Project\app\src\main\java\app\nial\ai\NialVoice.java"
    if (!(Test-Path -LiteralPath $VoiceSource)) {
        throw "Не найден NialVoice.java. Сборка остановлена."
    }

    Set-Location $Project

    & $Gradle --no-daemon --console=plain :app:assembleRelease

    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка сборки. Подпись не запущена."
    }

    if (!(Test-Path $Unsigned)) {
        throw "Не найден собранный APK."
    }

    & "$Tools\zipalign.exe" -P 16 -f 4 $Unsigned $Aligned

    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка выравнивания."
    }

    & "$Tools\apksigner.bat" sign `
        --ks $KeyFile `
        --ks-key-alias nial-release `
        --ks-pass env:NIAL_SIGN_PASS `
        --key-pass env:NIAL_SIGN_PASS `
        --out $Final `
        $Aligned

    if ($LASTEXITCODE -ne 0) {
        throw "Ошибка подписи APK."
    }

    & "$Tools\apksigner.bat" verify --verbose $Final

    if ($LASTEXITCODE -ne 0) {
        throw "Проверка подписи не пройдена."
    }

    Get-Item $Final | Select-Object FullName, Length, LastWriteTime
    Write-Host "Готово: релизный APK собран и подпись проверена."

    Start-Process explorer.exe -ArgumentList "/select,`"$Final`""
}
finally {
    Remove-Item Env:\NIAL_SIGN_PASS -ErrorAction SilentlyContinue
    $Plain = $null

    if ($Pointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
    }

    if ($null -ne $Secure) {
        $Secure.Dispose()
    }
}
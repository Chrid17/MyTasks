# My Tasks - one-time project setup (Windows PowerShell)
#
# Run from the project folder:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# What it does:
#   1. Checks Flutter is new enough (3.38.1+) and offers to upgrade it.
#   2. Removes the old version's code (Supabase, Firebase, old notification services).
#   3. Recreates the android/ios/web/windows/macos/linux folders so they match
#      your Flutter version.
#   4. Adds what Android needs for reminders (desugaring, permissions, receivers).
#   5. Sets the app name to "My Tasks", generates app icons, then analyzes and tests.

$ErrorActionPreference = 'Stop'
Set-Location -Path $PSScriptRoot

function Step($text) { Write-Host ''; Write-Host "==> $text" -ForegroundColor Cyan }
function Info($text) { Write-Host "    $text" }
function Warn($text) { Write-Host "    $text" -ForegroundColor Yellow }

function Read-Text($path) { return [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $path)) }
function Write-Text($path, $content) {
    # UTF-8 without BOM (Gradle and Xcode files must not have a BOM)
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $path), $content, $enc)
}
function Replace-InFile($path, $old, $new) {
    if (Test-Path $path) {
        $text = Read-Text $path
        if ($text.Contains($old)) { Write-Text $path ($text.Replace($old, $new)) }
    }
}
function Run($exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "'$exe $($arguments -join ' ')' failed (exit code $LASTEXITCODE)." }
}

if (-not (Test-Path 'lib\src\app.dart')) {
    throw 'Run this script from the My Tasks project folder (lib\src\app.dart was not found).'
}

# ---------------------------------------------------------------------------
Step 'Checking Flutter'
$versionLine = (& flutter --version | Out-String)
if ($versionLine -match 'Flutter (\d+)\.(\d+)\.(\d+)') {
    $current = [version]("{0}.{1}.{2}" -f $Matches[1], $Matches[2], $Matches[3])
    Info "Found Flutter $current"
    if ($current -lt [version]'3.38.1') {
        Warn 'My Tasks needs Flutter 3.38.1 or newer. Upgrading Flutter now...'
        Run 'flutter' @('upgrade')
    }
} else {
    throw 'Flutter was not found. Install it from https://docs.flutter.dev/get-started/install and try again.'
}

# ---------------------------------------------------------------------------
Step 'Removing the old version (Supabase, Firebase, old services and platform folders)'
$old = @(
    'lib\services', 'lib\ui', 'lib\utils', 'lib\models', 'lib\firebase_options.dart',
    'android', 'ios', 'macos', 'windows', 'linux', 'web',
    'supabase', 'firebase.json', 'deploy_temp.ps1', 'devtools_options.yaml',
    'FIREBASE_PUSH_SETUP.md', 'IOS_NOTIFICATIONS_CHECKLIST.md', 'NOTIFICATION_SOUND_SETUP.md',
    'OVERDUE_AND_NOTIFICATIONS.md', 'PUSH_NOTIFICATIONS_SETUP.md',
    'pubspec.lock', 'build', '.dart_tool', '.flutter-plugins', '.flutter-plugins-dependencies'
)
foreach ($p in $old) {
    if (Test-Path $p) {
        try {
            Remove-Item $p -Recurse -Force
            Info "removed $p"
        } catch {
            throw "Could not delete '$p'. Close Android Studio, VS Code terminals and any running app, then run this script again. ($($_.Exception.Message))"
        }
    }
}

# ---------------------------------------------------------------------------
Step 'Creating platform folders for Android, iOS, web, Windows, macOS and Linux'
Run 'flutter' @('create', '--org', 'com.chrisbwendo', '--project-name', 'my_tasks',
    '--platforms=android,ios,web,windows,macos,linux', '.')

# ---------------------------------------------------------------------------
Step 'Configuring Android for reminders'
$gradle = 'android\app\build.gradle.kts'
$g = Read-Text $gradle
if (-not $g.Contains('isCoreLibraryDesugaringEnabled')) {
    $re = New-Object System.Text.RegularExpressions.Regex('compileOptions\s*\{')
    if (-not $re.IsMatch($g)) { throw "Could not find compileOptions in $gradle" }
    $g = $re.Replace($g, "compileOptions {`n        isCoreLibraryDesugaringEnabled = true", 1)
    $g = $g.TrimEnd() + "`n`ndependencies {`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`n}`n"
    Write-Text $gradle $g
    Info 'enabled core library desugaring'
}

$manifest = 'android\app\src\main\AndroidManifest.xml'
$m = Read-Text $manifest
if (-not $m.Contains('POST_NOTIFICATIONS')) {
    $permissions = @"

    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
    <uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
"@
    $receivers = @"
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>

"@
    $re = New-Object System.Text.RegularExpressions.Regex('(<manifest[^>]*>)')
    $m = $re.Replace($m, '$1' + $permissions, 1)
    $m = $m.Replace('</application>', $receivers + '    </application>')
    Write-Text $manifest $m
    Info 'added notification permissions and receivers'
}

# ---------------------------------------------------------------------------
Step 'Setting the app name to "My Tasks"'
Replace-InFile $manifest 'android:label="my_tasks"' 'android:label="My Tasks"'
Replace-InFile 'web\index.html' 'my_tasks' 'My Tasks'
Replace-InFile 'web\manifest.json' '"my_tasks"' '"My Tasks"'
Replace-InFile 'windows\runner\main.cpp' 'L"my_tasks"' 'L"My Tasks"'
Replace-InFile 'linux\runner\my_application.cc' '"my_tasks"' '"My Tasks"'
Replace-InFile 'macos\Runner\Configs\AppInfo.xcconfig' 'PRODUCT_NAME = my_tasks' 'PRODUCT_NAME = My Tasks'
Replace-InFile 'ios\Runner\Info.plist' '<string>my_tasks</string>' '<string>My Tasks</string>'

# ---------------------------------------------------------------------------
Step 'Getting packages'
Run 'flutter' @('pub', 'get')

Step 'Generating app icons'
try {
    Run 'dart' @('run', 'flutter_launcher_icons')
} catch {
    Warn "Icons were not generated ($($_.Exception.Message)). The app still works with the default icon."
}

# ---------------------------------------------------------------------------
Step 'Checking the code'
$problems = $false
try { Run 'flutter' @('analyze', '--no-fatal-infos') } catch { $problems = $true; Warn $_.Exception.Message }
try { Run 'flutter' @('test') } catch { $problems = $true; Warn $_.Exception.Message }
if ($problems) {
    Warn 'Some checks reported problems (see above). Copy the output and send it to Claude to fix.'
}

Write-Host ''
Write-Host 'All done! My Tasks is ready.' -ForegroundColor Green
Write-Host ''
Write-Host 'Run it:'
Write-Host '  flutter run -d windows      (Windows desktop)'
Write-Host '  flutter run -d chrome       (web)'
Write-Host '  flutter run                 (connected Android phone or emulator)'
Write-Host ''
Write-Host 'Then commit and push. GitHub builds every platform and publishes the web app:'
Write-Host '  git add -A'
Write-Host '  git commit -m "My Tasks 2.0"'
Write-Host '  git push'

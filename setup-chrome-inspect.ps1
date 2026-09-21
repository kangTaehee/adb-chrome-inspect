# ============================================================
# setup-chrome-inspect.ps1
# Chrome 원격 디버깅(chrome://inspect) 환경 자동 세팅 스크립트
# 호환: Windows PowerShell 3.0+ (Win8/Server2012 이상 기본 탑재) / PowerShell 7
#
# 사용법 (PowerShell에서):
#   powershell -ExecutionPolicy Bypass -File .\setup-chrome-inspect.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

function Write-Step($msg)  { Write-Host "`n[단계] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)    { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Write-Warn2($msg) { Write-Host "  [!] $msg" -ForegroundColor Yellow }
function Write-Err($msg)   { Write-Host "  [X] $msg" -ForegroundColor Red }

# ------------------------------------------------------------
# 0. 구버전 호환 준비: TLS 1.2 활성화 (PS 5.1 이하는 기본 TLS 1.0이라
#    dl.google.com 다운로드가 실패함)
# ------------------------------------------------------------
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    Write-Warn2 "TLS 1.2 설정 실패 — .NET Framework 4.5 이상이 필요할 수 있습니다."
}

# 구버전에도 동작하는 압축 해제 함수 (Expand-Archive는 PS 5.0+ 전용)
function Expand-ZipCompat($zipPath, $destDir) {
    if (Get-Command Expand-Archive -ErrorAction SilentlyContinue) {
        Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
    } else {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        # ZipFile은 대상에 파일이 이미 있으면 실패하므로 기존 폴더 정리
        $target = Join-Path $destDir 'platform-tools'
        if (Test-Path $target) { Remove-Item $target -Recurse -Force }
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $destDir)
    }
}

# ------------------------------------------------------------
# 1. adb 찾기 (PATH → 흔한 설치 경로 순)
# ------------------------------------------------------------
Write-Step "adb 실행 파일 탐색"

$adb = $null
$cmd = Get-Command adb -ErrorAction SilentlyContinue
if ($cmd) {
    # .Source는 PS 5.0+ 전용이므로 .Path → .Definition 순으로 폴백
    if ($cmd.Path) { $adb = $cmd.Path } else { $adb = $cmd.Definition }
}

if (-not $adb) {
    $candidates = @(
        "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
        "$env:LOCALAPPDATA\Android\platform-tools\adb.exe",
        "C:\platform-tools\adb.exe",
        "C:\adb\adb.exe",
        "$env:USERPROFILE\platform-tools\adb.exe",
        "C:\Program Files (x86)\Android\android-sdk\platform-tools\adb.exe",
        "$env:USERPROFILE\scoop\shims\adb.exe",
        "C:\ProgramData\chocolatey\bin\adb.exe"
    )
    $adb = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}

# ------------------------------------------------------------
# 2. 없으면 platform-tools 다운로드 및 설치
# ------------------------------------------------------------
if (-not $adb) {
    Write-Warn2 "adb를 찾지 못했습니다. Google platform-tools를 다운로드합니다."

    $installDir = "$env:LOCALAPPDATA\Android"
    $zipUrl  = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
    $zipPath = "$env:TEMP\platform-tools.zip"

    Write-Step "platform-tools 다운로드 중... ($zipUrl)"
    try {
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    } catch {
        # Invoke-WebRequest 실패 시(구버전/프록시 등) WebClient로 재시도
        Write-Warn2 "Invoke-WebRequest 실패 — WebClient로 재시도합니다."
        (New-Object System.Net.WebClient).DownloadFile($zipUrl, $zipPath)
    }

    Write-Step "압축 해제 중... → $installDir\platform-tools"
    New-Item -ItemType Directory -Force -Path $installDir | Out-Null
    Expand-ZipCompat $zipPath $installDir
    Remove-Item $zipPath -Force

    $adb = "$installDir\platform-tools\adb.exe"
    if (-not (Test-Path $adb)) {
        Write-Err "설치에 실패했습니다. 수동으로 platform-tools를 설치해주세요."
        exit 1
    }
    Write-Ok "platform-tools 설치 완료"
} else {
    Write-Ok "adb 발견: $adb"
}

$adbDir = Split-Path $adb -Parent

# ------------------------------------------------------------
# 3. 사용자 PATH에 등록 (없는 경우만)
# ------------------------------------------------------------
Write-Step "PATH 등록 확인"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (-not $userPath) { $userPath = '' }
if ($userPath -notlike "*$adbDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$adbDir", 'User')
    Write-Ok "사용자 PATH에 추가됨: $adbDir (새 터미널부터 적용)"
} else {
    Write-Ok "이미 PATH에 등록되어 있습니다."
}
# 현재 세션에도 즉시 적용
$env:Path = "$env:Path;$adbDir"

# ------------------------------------------------------------
# 4. adb 서버 재시작
#    (구버전 PS는 $ErrorActionPreference=Stop 상태에서 네이티브 stderr
#     리다이렉트 시 오류를 던질 수 있어 잠시 Continue로 전환)
# ------------------------------------------------------------
Write-Step "adb 서버 재시작"
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& $adb kill-server 2>&1 | Out-Null
& $adb start-server 2>&1 | Out-Null
$ErrorActionPreference = $prevEap
Write-Ok "adb 데몬 실행 중 (tcp:5037)"

# ------------------------------------------------------------
# 5. 디바이스 연결 상태 진단
# ------------------------------------------------------------
Write-Step "디바이스 연결 상태 확인"

$lines = (& $adb devices) | Select-Object -Skip 1 | Where-Object { $_.Trim() -ne '' }

if (-not $lines) {
    Write-Err "연결된 디바이스가 없습니다."
    Write-Host @"

  점검 사항:
   1. USB 케이블이 데이터 전송용인지 확인 (충전 전용 케이블 X)
   2. 휴대폰에서 [설정 > 개발자 옵션 > USB 디버깅] 활성화
      - 개발자 옵션이 없으면: [설정 > 휴대전화 정보 > 소프트웨어 정보]에서
        '빌드번호' 7회 연타
   3. 휴대폰 USB 연결 모드를 '파일 전송(MTP)'으로 변경
   4. 삼성 기기는 USB 드라이버 필요 시 Smart Switch 설치
"@ -ForegroundColor Yellow
    exit 1
}

$allOk = $true
foreach ($line in @($lines)) {
    $parts  = $line -split '\s+'
    $serial = $parts[0]
    $state  = $parts[1]

    switch ($state) {
        'device' {
            Write-Ok "$serial : 정상 연결됨"
        }
        'unauthorized' {
            $allOk = $false
            Write-Warn2 "$serial : 미승인(unauthorized) 상태"
            Write-Host @"

  휴대폰 화면을 잠금 해제하면 'USB 디버깅을 허용하시겠습니까?' 팝업이 떠 있습니다.
  → '이 컴퓨터에서 항상 허용' 체크 후 [허용]을 누르세요.
  팝업이 없으면 케이블을 뺐다 다시 꽂거나,
  [개발자 옵션 > USB 디버깅 허용 취소] 후 재연결하세요.
  허용 후 이 스크립트를 다시 실행하면 됩니다.
"@ -ForegroundColor Yellow
        }
        'offline' {
            $allOk = $false
            Write-Warn2 "$serial : offline 상태 — 케이블을 재연결한 뒤 스크립트를 다시 실행하세요."
        }
        default {
            $allOk = $false
            Write-Warn2 "$serial : 알 수 없는 상태($state)"
        }
    }
}

# ------------------------------------------------------------
# 6. 완료 안내 및 chrome://inspect 열기
# ------------------------------------------------------------
if ($allOk) {
    Write-Step "완료"
    Write-Ok "Chrome에서 chrome://inspect#devices 를 열면 기기가 표시됩니다."
    Write-Host "  (Discover USB devices 체크박스가 켜져 있어야 합니다)`n"

    $openChrome = Read-Host "지금 Chrome에서 inspect 페이지를 열까요? (y/N)"
    if ($openChrome -eq 'y') {
        try {
            Start-Process "chrome" "chrome://inspect/#devices"
        } catch {
            Write-Warn2 "Chrome 실행 실패 — 주소창에 chrome://inspect#devices 를 직접 입력하세요."
        }
    }
} else {
    Write-Host "`n위 안내를 따른 뒤 스크립트를 다시 실행해주세요." -ForegroundColor Yellow
}

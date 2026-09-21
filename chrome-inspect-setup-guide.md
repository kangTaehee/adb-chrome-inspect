# Chrome inspect 디바이스 연결 세팅 가이드 (Windows)

Android 기기를 USB로 연결해 Chrome 개발자 도구(`chrome://inspect`)로 원격 디버깅하기 위한 세팅 방법입니다.

- **자동 세팅**: `setup-chrome-inspect.ps1` 스크립트 실행 (아래 [자동 세팅](#자동-세팅-스크립트) 참고)
- **수동 세팅**: 아래 1~5단계를 순서대로 진행

---

## 자동 세팅 (스크립트)

`setup-chrome-inspect.ps1`을 PC에 복사한 뒤 PowerShell에서 실행:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-chrome-inspect.ps1
```

adb 탐색/설치, PATH 등록, adb 서버 기동, 연결 진단까지 자동으로 수행합니다.
(Windows PowerShell 3.0 이상 지원. 관리자 권한 불필요)

---

## 수동 세팅

### 1. ADB(platform-tools) 설치

1. 다운로드: <https://dl.google.com/android/repository/platform-tools-latest-windows.zip>
   - 공식 안내 페이지: <https://developer.android.com/tools/releases/platform-tools>
2. 압축을 원하는 위치에 해제. 예: `C:\Users\<사용자명>\AppData\Local\Android`
   - 해제하면 `...\Android\platform-tools\adb.exe`가 생깁니다.

### 2. PATH 등록 (선택이지만 권장)

1. `Win + R` → `sysdm.cpl` 입력 → **고급** 탭 → **환경 변수**
2. 상단 "사용자 변수"에서 `Path` 선택 → **편집** → **새로 만들기**
3. `C:\Users\<사용자명>\AppData\Local\Android\platform-tools` 추가 → 확인
4. **열려 있던 터미널을 모두 닫고 새로 열어야** 적용됩니다.

또는 PowerShell 한 줄로:

```powershell
[Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path','User') + ';' + "$env:LOCALAPPDATA\Android\platform-tools", 'User')
```

### 3. 휴대폰 설정

1. **개발자 옵션 활성화**: 설정 → 휴대전화 정보 → 소프트웨어 정보 → **빌드번호 7회 연타**
2. 설정 → 개발자 옵션 → **USB 디버깅** 켜기
3. **데이터 전송용** USB 케이블로 PC에 연결 (충전 전용 케이블은 인식 안 됨)
4. 연결 모드를 **파일 전송(MTP)** 으로 선택

### 4. 연결 확인

새 터미널에서:

```powershell
adb devices
```

| 결과 | 의미 / 조치 |
|---|---|
| `device` | 정상 연결. 다음 단계로 진행 |
| `unauthorized` | 휴대폰 잠금 해제 → "USB 디버깅을 허용하시겠습니까?" 팝업에서 **"이 컴퓨터에서 항상 허용"** 체크 후 허용 → 다시 `adb devices` |
| 아무것도 없음 | 케이블 재연결, USB 디버깅 재확인. 삼성 기기는 **Smart Switch** 설치(USB 드라이버 포함) |

### 5. Chrome에서 확인

1. Chrome 주소창에 `chrome://inspect/#devices` 입력
2. **Discover USB devices** 체크박스가 켜져 있는지 확인
3. 잠시 기다리면 기기명과 열린 탭/WebView 목록이 표시됨 → **inspect** 클릭

---

## 문제 발생 시 체크리스트

| 증상 | 조치 |
|---|---|
| inspect에 기기가 안 뜸 | 터미널에서 `adb kill-server` → `adb start-server` 후 Chrome 재시작 |
| `unauthorized` 지속 | 개발자 옵션 → **USB 디버깅 허용 취소** 후 케이블 재연결 → 팝업 다시 허용 |
| `offline` | 케이블 재연결, 다른 USB 포트 시도 |
| 탭 목록이 안 뜸 | 휴대폰 Chrome이 실행 중인지, 앱 WebView라면 디버깅 빌드인지 확인 |

## 참고: 다른 OS용 platform-tools

- macOS: <https://dl.google.com/android/repository/platform-tools-latest-darwin.zip>
- Linux: <https://dl.google.com/android/repository/platform-tools-latest-linux.zip>

<#
  BSP 플랫폼 — 매니저(백그라운드 런처) 설치
  관리자 권한도, 서비스 등록도, 설치 프로그램도 쓰지 않는다. 파일 복사 + 바로가기 하나.

    .\install.ps1                                     오프라인으로 설치 (서버 나중에)
    .\install.ps1 -ManifestUrl https://…/catalog.json -Token …
    .\install.ps1 -Force                              이미 도는 매니저를 정리하고 다시
    .\install.ps1 -NoStart                            깔기만 하고 띄우지 않음
    .\install.ps1 -Remove                             자동 시작 해제 + 매니저 정지

  설치 위치 : %AppData%\BSP\Platform\   (자동 시작 = 시작프로그램 바로가기)
#>
param(
  [string]$ManifestUrl = "",
  [string]$UsageUrl = "",
  [string]$Token = "",
  [string]$AuthHeader = "x-bsp-key",
  [string]$RevitYear = "2024",
  [string]$Dir = "",
  [string]$StartupDir = "",
  [switch]$Force, [switch]$NoStart, [switch]$NoAutostart, [switch]$Remove
)

$ErrorActionPreference = "Stop"
if (-not $Dir) { $Dir = Join-Path $env:APPDATA "BSP\Platform" }
if (-not $StartupDir) { $StartupDir = [Environment]::GetFolderPath("Startup") }
$sdkBin = Join-Path (Split-Path $PSScriptRoot -Parent) "bin"
$exe = Join-Path $Dir "bsp-launcher.exe"
$lnk = Join-Path $StartupDir "BSP 매니저.lnk"

function Running() { @(Get-CimInstance Win32_Process -Filter "Name='bsp-launcher.exe'" -ErrorAction SilentlyContinue) }

if ($Remove) {
  Remove-Item $lnk -Force -ErrorAction SilentlyContinue
  Running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Write-Host "자동 시작 해제 · 매니저 정지 (설치 파일과 기록은 남겨 둡니다 : $Dir)" -ForegroundColor Yellow
  exit 0
}

# 1) 이미 도는 것 확인 — 한 대에 하나만 돈다
$live = @(Running)
if ($live.Count -and -not $Force) {
  Write-Host "이미 매니저가 돌고 있습니다 ($($live.Count)개) :" -ForegroundColor Yellow
  $live | ForEach-Object { Write-Host ("  pid {0}  {1}" -f $_.ProcessId, $_.CommandLine.Trim()) }
  Write-Host "정리하고 다시 깔려면 -Force 를 붙이세요." -ForegroundColor Yellow
  exit 3
}
if ($live.Count -and $Force) {
  $live | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  Start-Sleep -Milliseconds 800
  Write-Host "기존 매니저 $($live.Count)개 정지"
}

# 2) 복사
New-Item -ItemType Directory -Force $Dir | Out-Null
Copy-Item (Join-Path $sdkBin "bsp-launcher.exe") $exe -Force
Write-Host "설치 : $exe"

# 3) 설정 — 이미 있으면 덮지 않는다 (현장 설정을 지우지 않는다)
$cfgPath = Join-Path $Dir "config.json"
if (Test-Path $cfgPath) { Write-Host "설정 유지 : $cfgPath (이미 있음)" }
else {
  $cfg = [ordered]@{
    server = ""; manifestUrl = $ManifestUrl; usageUrl = $UsageUrl; memberUrl = ""
    authHeader = $AuthHeader; token = $Token; tenant = "bsp-internal"
    revitYear = $RevitYear; pollSeconds = 60; requireMember = $false
  } | ConvertTo-Json
  [IO.File]::WriteAllText($cfgPath, $cfg, (New-Object Text.UTF8Encoding($false)))
  Write-Host "설정 : $cfgPath" $(if ($ManifestUrl) { "" } else { " (서버 없음 — 세션 관리만)" })
}

# 4) 자동 시작 — 로그온할 때 뜬다. 서비스도 관리자 권한도 아니다
if (-not $NoAutostart) {
  $ws = New-Object -ComObject WScript.Shell
  $sc = $ws.CreateShortcut($lnk)
  $sc.TargetPath = $exe
  $sc.Arguments = "watch-revit"
  $sc.WorkingDirectory = $Dir
  $sc.WindowStyle = 7                      # 최소화 — 화면을 가리지 않는다
  $sc.Description = "BSP 플랫폼 백그라운드 매니저"
  $sc.Save()
  Write-Host "자동 시작 : $lnk"
}

# 5) 지금 띄운다
if (-not $NoStart) {
  Start-Process $exe -ArgumentList "watch-revit" -WindowStyle Hidden
  Start-Sleep -Seconds 2
  $now = @(Running)
  if ($now.Count -eq 1) { Write-Host "매니저 시작 : pid $($now[0].ProcessId)" -ForegroundColor Green }
  elseif ($now.Count -eq 0) {
    Write-Host "매니저가 뜨지 않았습니다 — $Dir\agent.err.log 를 확인하세요" -ForegroundColor Red; exit 1
  }
  else { Write-Host "매니저가 $($now.Count)개입니다 — 하나만 돌아야 합니다" -ForegroundColor Red; exit 1 }
}

Write-Host "`n확인 :  .\AI\healthcheck.ps1" -ForegroundColor Cyan

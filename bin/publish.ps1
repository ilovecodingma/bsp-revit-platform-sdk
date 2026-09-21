# 한 줄 배포 — 검사 → 업로드 → 심사 기록 → (선택) 승인
#
#   .\publish.ps1 -Path ..\plugin\bin -Id bsp.platform -Version 0.9.0 -Target 2024 -Kind platform -Approve
#
# 흐름
#   1) bsp-verify 로 정적 검사 (참조 API 연도·런타임·서명·동봉금지·내부충돌)
#   2) FAIL 이면 여기서 멈춘다 (-Force 로 무시 가능, 권장하지 않음)
#   3) 서버에 올린다 (자산 + 해시 발행)
#   4) 검사 결과를 /api/verdict 로 기록
#   5) -Approve 면 승인까지. 그 순간부터 런처가 내려받는다
#      (적용은 리빗이 꺼질 때. 런처 watch-revit 가 알아서 한다)
param(
  [Parameter(Mandatory=$true)][string]$Path,
  [Parameter(Mandatory=$true)][string]$Id,
  [Parameter(Mandatory=$true)][string]$Version,
  [string]$Target = "2024",
  [string]$Kind = "platform",
  [string]$Name = "",
  [string]$Publisher = "BSP ENGINEERING",
  [string]$Server = "",
  [string]$Key = "",
  [switch]$Approve,
  [switch]$Force
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
if (-not $Server) {
  $lc = Join-Path $root "launcher\cs\config.json"
  if (Test-Path $lc) { $Server = (Get-Content $lc -Raw | ConvertFrom-Json).server }
}
if (-not $Key) {
  $tf = Join-Path $root "server\.token"
  if (Test-Path $tf) { $Key = (Get-Content $tf -Raw).Trim() }
}
if (-not $Name) { $Name = $Id }
if (-not (Test-Path $Path)) { throw "없는 경로: $Path" }

$files = @(Get-ChildItem $Path -File -Recurse)
if (-not $files) { throw "올릴 파일이 없습니다: $Path" }

Write-Host "배포 : $Id @ $Version  ($Kind · Revit $Target · 파일 $($files.Count)개)" -ForegroundColor Cyan
Write-Host "서버 : $Server"
Write-Host ("-" * 92)

# ---------- 1) 정적 검사
$verify = Join-Path $PSScriptRoot "bsp-verify.exe"
if (-not (Test-Path $verify)) { throw "bsp-verify.exe 가 없습니다. tools\BspVerify.cs 를 먼저 빌드하세요" }
& $verify $Path --id $Id --version $Version --target $Target | Write-Host
$verifyCode = $LASTEXITCODE
Write-Host ("-" * 92)

if ($verifyCode -ne 0 -and -not $Force) {
  Write-Host "검사 FAIL — 배포를 멈춥니다. 고치고 다시 하십시오." -ForegroundColor Red
  Write-Host "  (그래도 올리려면 -Force · 단 심사에서 승인되지 않습니다)"
  exit 1
}

# ---------- 2) 업로드
$args = @("-s","-X","POST","$Server/upload",
          "-H","x-bsp-key: $Key",
          "-F","id=$Id","-F","name=$Name","-F","version=$Version",
          "-F","kind=$Kind","-F","minRevit=$Target","-F","publisher=$Publisher")
foreach ($f in $files) { $args += @("-F","files=@$($f.FullName)") }
$args += @("-o","NUL","-w","%{http_code}")
$code = & curl.exe @args
if ($code -ne "303" -and $code -ne "200") { Write-Host "[업로드] 실패 HTTP $code" -ForegroundColor Red; exit 1 }
Write-Host "[업로드] 완료 (HTTP $code)"

# ---------- 3) 검사 결과 기록
& $verify $Path --id $Id --version $Version --target $Target --post $Server --key $Key |
  Select-String "서버 :" | ForEach-Object { Write-Host "[심사] $($_.Line.Trim())" }

# ---------- 4) 승인
if ($Approve) {
  if ($verifyCode -ne 0) {
    Write-Host "[승인] 건너뜀 — 검사 FAIL 인 버전은 승인할 수 없습니다" -ForegroundColor Yellow
  } else {
    $body = "id=$([uri]::EscapeDataString($Id))&version=$([uri]::EscapeDataString($Version))&status=approved&by=publish.ps1"
    $r = & curl.exe -s -X POST "$Server/api/review?key=$Key" -H "content-type: application/x-www-form-urlencoded" -d $body -o NUL -w "%{http_code}"
    if ($r -eq "303" -or $r -eq "200") { Write-Host "[승인] 완료" -ForegroundColor Green }
    else { Write-Host "[승인] 실패 HTTP $r" -ForegroundColor Red }
  }
}

Write-Host ""
Write-Host "이제 각 PC 의 런처가 «리빗이 꺼질 때» 적용합니다 (bsp-launcher watch-revit)."
Write-Host "콘솔 : $Server/?key=$Key"

<#
  bsp-wizard — 몇 가지 묻고, 바로 적용한다.

     .\AI\wizard.ps1          물어보면서 (엔터만 쳐도 되게 기본값을 찾아 둔다)
     .\AI\wizard.ps1 -Auto    묻지 않고 찾은 기본값으로 바로

  묻는 것은 넷뿐이다.
     1. 애드인 프로젝트 어디에 있나        (찾아서 후보를 보여 준다)
     2. 리빗 몇 년도                        (깔린 것을 찾아 둔다)
     3. 업데이트 서버 주소 있나             (없으면 오프라인으로 깔고 나중에 주소만 채우면 된다)
     4. 애드온 폴더에 바로 설치할까         (리빗이 꺼져 있을 때만)

  답을 받으면 apply.ps1 이 나머지를 전부 한다 — 점검·보관·두 줄 삽입·참조·빌드·검증.
#>
param(
  [string]$Project = "", [string]$RevitYear = "", [string]$ManifestUrl = "",
  [string]$Token = "", [string]$AuthHeader = "x-bsp-key", [string]$InstallTo = "",
  [switch]$Auto
)

$ErrorActionPreference = "Stop"
$sdk = Split-Path $PSScriptRoot -Parent

function Ask($question, $default) {
  if ($Auto) { Write-Host ("  {0}  →  {1}" -f $question, $(if ($default) { $default } else { "(없음)" })); return $default }
  $hint = if ($default) { " [$default]" } else { "" }
  $a = Read-Host ("  " + $question + $hint)
  if ([string]::IsNullOrWhiteSpace($a)) { return $default }
  return $a.Trim()
}

Write-Host "`nBSP 플랫폼 — 붙이기 마법사" -ForegroundColor Cyan
Write-Host ("=" * 92)

# ── 1. 리빗 연도 ────────────────────────────────────────────────────
$years = @(Get-ChildItem "C:\Program Files\Autodesk" -Directory -ErrorAction SilentlyContinue |
           Where-Object Name -match '^Revit (\d{4})$' | ForEach-Object { $Matches[1] } | Sort-Object -Descending)
if (-not $RevitYear) {
  $def = if ($years.Count) { $years[0] } else { "2024" }
  Write-Host ("  깔려 있는 리빗 : " + $(if ($years.Count) { $years -join ", " } else { "찾지 못함" })) -ForegroundColor DarkGray
  $RevitYear = Ask "리빗 몇 년도에 붙일까요?" $def
}

# ── 2. 프로젝트 ────────────────────────────────────────────────────
if (-not $Project) {
  $roots = @("$env:USERPROFILE\source\repos", "$env:USERPROFILE\Documents", "$env:USERPROFILE\Desktop", "C:\") |
           Where-Object { Test-Path $_ }
  $found = @()
  foreach ($r in $roots) {
    $depth = if ($r -eq "C:\") { 2 } else { 4 }
    $found += Get-ChildItem $r -Filter *.csproj -Recurse -Depth $depth -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\(obj|bin|node_modules|\.git)\\' } |
              Where-Object {
                $dir = Split-Path $_.FullName -Parent
                @(Get-ChildItem $dir -Filter *.cs -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                  Select-Object -First 40 |
                  Where-Object { (Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue) -match 'IExternalApplication' }).Count -gt 0
              } | Select-Object -First 5
    if ($found.Count -ge 3) { break }
  }
  if ($found.Count) {
    Write-Host "  찾은 애드인 프로젝트 :" -ForegroundColor DarkGray
    $i = 1; foreach ($f in $found) { Write-Host ("    {0}) {1}" -f $i, $f.FullName); $i++ }
    $pick = Ask "번호 또는 경로를 넣으세요" "1"
    $Project = if ($pick -match '^\d+$' -and [int]$pick -le $found.Count) { $found[[int]$pick - 1].FullName } else { $pick }
  }
  else {
    Write-Host "  애드인 프로젝트를 자동으로 못 찾았습니다." -ForegroundColor Yellow
    $Project = Ask "프로젝트 폴더 또는 .csproj 경로" ""
  }
}
if (-not $Project -or -not (Test-Path $Project)) { Write-Host "`n경로가 없습니다. 멈춥니다." -ForegroundColor Red; exit 1 }

# ── 3. 서버 ────────────────────────────────────────────────────────
if (-not $ManifestUrl) {
  Write-Host "  업데이트 서버 — 목록(JSON) 주소 하나면 됩니다. 없으면 그냥 엔터(나중에 채워도 됩니다)." -ForegroundColor DarkGray
  $ManifestUrl = Ask "카탈로그 주소" ""
}
if ($ManifestUrl -and -not $Token) { $Token = Ask "인증 토큰 (없으면 엔터)" "" }
if ($Token) { $AuthHeader = Ask "인증 헤더 이름" $AuthHeader }

# ── 4. 설치 위치 ───────────────────────────────────────────────────
if (-not $InstallTo) {
  $addins = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$RevitYear"
  $cands = @(Get-ChildItem $addins -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
  $revitUp = [bool](Get-Process Revit -ErrorAction SilentlyContinue)
  if ($revitUp) { Write-Host "  리빗이 켜져 있어 설치 단계는 건너뜁니다 (파일이 잠깁니다)." -ForegroundColor Yellow }
  elseif ($cands.Count) {
    Write-Host "  애드온 폴더 후보 :" -ForegroundColor DarkGray
    $cands | ForEach-Object { Write-Host "    · $_" }
    $InstallTo = Ask "어디에 에이전트·매니저를 같이 둘까요? (엔터=안 함)" ""
  }
}

# ── 5. 확인하고 실행 ───────────────────────────────────────────────
Write-Host ("-" * 92)
Write-Host "  프로젝트 : $Project"
Write-Host "  리빗     : $RevitYear"
Write-Host "  서버     : $(if ($ManifestUrl) { $ManifestUrl } else { '(오프라인 — 나중에 config.json 의 manifestUrl 만 채우면 됩니다)' })"
Write-Host "  설치     : $(if ($InstallTo) { $InstallTo } else { '(안 함)' })"
Write-Host ("-" * 92)
if (-not $Auto) {
  $go = Read-Host "  이대로 붙일까요? (Y/n)"
  if ($go -and $go -notmatch '^[Yy]') { Write-Host "  멈췄습니다. 아무것도 바꾸지 않았습니다."; exit 0 }
}

# $args 는 파워셸 예약 변수다 — 여기에 담으면 조용히 비워진다 (실측)
$call = @{ Project = $Project; RevitYear = $RevitYear; AuthHeader = $AuthHeader }
if ($ManifestUrl) { $call.ManifestUrl = $ManifestUrl }
if ($Token) { $call.Token = $Token }
if ($InstallTo) { $call.InstallTo = $InstallTo }

& (Join-Path $PSScriptRoot "apply.ps1") @call
exit $LASTEXITCODE

<#
  BSP 플랫폼 — 되돌릴 수 있게 만들어 두는 장치
  전환 작업을 시작하기 전에 한 번, 그리고 언제든 원래대로.

    .\snapshot.ps1                  지금 상태를 보관한다
    .\snapshot.ps1 -List            보관본 목록
    .\snapshot.ps1 -Restore         가장 최근 보관본으로 되돌린다
    .\snapshot.ps1 -Restore -Name bsp-snap-2026...   지정 보관본으로

  보관 대상 : Addins\<연도> 폴더 전체 + %AppData%\BSP\Platform 상태
  리빗이 켜져 있으면 파일이 잠겨 있어 되돌릴 수 없다 — 먼저 닫는다.
#>
param([switch]$List, [switch]$Restore, [string]$Name = "", [string]$RevitYear = "2024")

$ErrorActionPreference = "Stop"
$vault = Join-Path $env:LOCALAPPDATA "BSP\Snapshots"
$addins = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$RevitYear"
$state = Join-Path $env:APPDATA "BSP\Platform"
New-Item -ItemType Directory -Force $vault | Out-Null

function Snaps() { Get-ChildItem $vault -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending }

if ($List) {
  $s = @(Snaps)
  if (-not $s.Count) { Write-Host "보관본 없음 : $vault"; exit 0 }
  foreach ($x in $s) {
    $n = @(Get-ChildItem $x.FullName -Recurse -File).Count
    Write-Host ("{0}   파일 {1}개   {2}" -f $x.Name, $n, $x.CreationTime.ToString("MM-dd HH:mm"))
  }
  exit 0
}

if ($Restore) {
  if (Get-Process Revit -ErrorAction SilentlyContinue) {
    Write-Host "리빗이 켜져 있습니다 — 닫고 다시 실행하세요 (파일이 잠깁니다)." -ForegroundColor Yellow
    exit 2
  }
  $target = if ($Name) { Join-Path $vault $Name } else { (Snaps | Select-Object -First 1).FullName }
  if (-not $target -or -not (Test-Path $target)) { throw "보관본을 찾지 못함" }

  # 지금 것을 한 번 더 보관해 두고 되돌린다 (되돌리기도 되돌릴 수 있게)
  & $PSCommandPath -RevitYear $RevitYear | Out-Null

  Remove-Item $addins -Recurse -Force -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force $addins | Out-Null
  $src = Join-Path $target "Addins"
  if (Test-Path $src) { Copy-Item "$src\*" $addins -Recurse -Force }

  $ss = Join-Path $target "Platform"
  if (Test-Path $ss) {
    New-Item -ItemType Directory -Force $state | Out-Null
    Copy-Item "$ss\*" $state -Recurse -Force
  }
  Write-Host "되돌렸습니다 : $target" -ForegroundColor Green
  exit 0
}

# 기본 동작 — 보관
$name = "bsp-snap-" + (Get-Date -f "yyyyMMdd-HHmmss")
$dst = Join-Path $vault $name
New-Item -ItemType Directory -Force (Join-Path $dst "Addins"), (Join-Path $dst "Platform") | Out-Null
if (Test-Path $addins) { Copy-Item "$addins\*" (Join-Path $dst "Addins") -Recurse -Force -ErrorAction SilentlyContinue }
if (Test-Path $state) {
  foreach ($f in @("state.json", "config.json", "agent.json", "runlog.jsonl", "runlog.sent")) {
    $p = Join-Path $state $f
    if (Test-Path $p) { Copy-Item $p (Join-Path $dst "Platform") -Force -ErrorAction SilentlyContinue }
  }
}
$n = @(Get-ChildItem $dst -Recurse -File).Count
Write-Host ("보관 완료 : {0}  (파일 {1}개)" -f $dst, $n) -ForegroundColor Green
Write-Host "되돌리려면 :  .\snapshot.ps1 -Restore"

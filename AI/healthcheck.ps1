<#
  BSP 플랫폼 — 이 PC 지금 상태 (사실만 찍는다. 고치지 않는다)
    .\healthcheck.ps1                2024 기준
    .\healthcheck.ps1 -RevitYear 2025
  단계마다 이것을 돌려 «무엇이 바뀌었는지» 를 눈으로 확인한다.
#>
param([string]$RevitYear = "2024")

$state = Join-Path $env:APPDATA "BSP\Platform"
$addins = Join-Path $env:APPDATA "Autodesk\Revit\Addins\$RevitYear"
$line = "-" * 88

function Say($k, $v) { Write-Host ("{0,-16} {1}" -f $k, $v) }

Write-Host "`nBSP 플랫폼 · 현재 상태   ($(Get-Date -f 'yyyy-MM-dd HH:mm'))" -ForegroundColor Cyan
Write-Host $line

# 1. 리빗
$rv = @(Get-Process Revit -ErrorAction SilentlyContinue)
Say "리빗" $(if ($rv.Count) { "$($rv.Count)개 실행 중 (pid " + (($rv | ForEach-Object { $_.Id }) -join ",") + ")" } else { "꺼짐" })

# 2. 매니저
$mg = @(Get-CimInstance Win32_Process -Filter "Name='bsp-launcher.exe'" -ErrorAction SilentlyContinue)
Say "매니저" $(if ($mg.Count -eq 1) { "돌고 있음 (pid $($mg[0].ProcessId))" }
              elseif ($mg.Count -eq 0) { "꺼짐" }
              else { "$($mg.Count)개 — 하나만 돌아야 한다" })
$beat = Join-Path $state "agent.json"
if (Test-Path $beat) {
  $age = [int]((Get-Date) - (Get-Item $beat).LastWriteTime).TotalSeconds
  Say "심장박동" "$age 초 전"
}

# 3. 설치 상태
$sf = Join-Path $state "state.json"
if (Test-Path $sf) {
  try {
    $s = [IO.File]::ReadAllText($sf) | ConvertFrom-Json
    Say "서버" $(if ($s.server.ok) { "연결됨 $($s.server.url)" } else { "끊김 / 오프라인" })
    Say "갱신" $s.updated
    Write-Host ""
    Write-Host ("  {0,-24} {1,-22} {2,-10} {3}" -f "제품", "버전", "종류", "상태")
    foreach ($p in $s.installed.PSObject.Properties) {
      $v = $p.Value
      Write-Host ("  {0,-24} {1,-22} {2,-10} {3}" -f $v.id, $v.version, $v.kind, $v.status)
    }
    if ($s.pending.Count) { Write-Host "`n  대기 :"; $s.pending | ForEach-Object { Write-Host "    · $_" } }
    if ($s.alerts.Count) { Write-Host "`n  경고 :"; $s.alerts | ForEach-Object { Write-Host "    · $_" -ForegroundColor Yellow } }
  } catch { Say "상태파일" "읽기 실패 : $($_.Exception.Message)" }
} else { Say "상태파일" "없음 (아직 한 번도 동기화 안 함)" }

# 4. Addins 폴더 — 누가 리빗에 직접 꽂혀 있나
Write-Host "`n$line"
Write-Host "Addins\$RevitYear  (여기 있는 .addin 만 리빗이 기동 때 읽는다)"
if (Test-Path $addins) {
  $files = @(Get-ChildItem $addins -Filter *.addin -ErrorAction SilentlyContinue)
  if (-not $files.Count) { Write-Host "  (없음)" }
  foreach ($f in $files) {
    $asm = ""
    try { $asm = ([xml](Get-Content $f.FullName -Raw)).RevitAddIns.AddIn.Assembly } catch { }
    Write-Host ("  {0,-34} {1}" -f $f.Name, $asm)
  }
} else { Write-Host "  폴더 없음" }

# 5. 기록
Write-Host "`n$line"
$log = Join-Path $state "runlog.jsonl"
if (Test-Path $log) {
  $all = @(Get-Content $log -Encoding UTF8)
  Say "기록" "$($all.Count)줄"
  $all | Select-Object -Last 5 | ForEach-Object {
    try { $o = $_ | ConvertFrom-Json; Write-Host ("  {0}  {1,-18} {2,-10} {3}ms" -f $o.t.Substring(11), $o.tool, $o.outcome, $o.ms) } catch { }
  }
} else { Say "기록" "없음" }

$mem = Join-Path $state "memory.json"
if (Test-Path $mem) {
  try {
    $m = [IO.File]::ReadAllText($mem) | ConvertFrom-Json
    Say "메모리" ("{0}MB · 모듈 {1}(+{2}) · {3} · {4}분" -f $m.ws, $m.modules, $m.grown, $m.level, $m.minutes)
  } catch { }
}
$err = Join-Path $state "agent.err.log"
if (Test-Path $err) { Write-Host "`n매니저 오류 기록 있음 : $err" -ForegroundColor Yellow }
Write-Host $line

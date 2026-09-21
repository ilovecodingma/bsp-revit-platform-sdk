<#
  BSP 플랫폼 — 배포 합격 시험
  사람 눈으로 판정하지 않는다. 6개 항목 전부 PASS 여야 «된다» 고 말할 수 있다.

    .\selftest.ps1                                   로컬 고정물만 (서버 없이 런처 검증)
    .\selftest.ps1 -ManifestUrl https://…/catalog.json -Token … -AuthHeader x-bsp-key

  시험은 격리된 상태 폴더에서 돈다 (APPDATA 를 임시 폴더로 바꿔 자식에게 물려준다).
  현장 PC 의 설치 상태를 건드리지 않는다.
#>
param(
  [string]$ManifestUrl = "",
  [string]$Token = "",
  [string]$AuthHeader = "x-bsp-key",
  [string]$Exe = "",
  [string]$RevitYear = "2024"
)

$ErrorActionPreference = "Stop"
if (-not $Exe) { $Exe = Join-Path (Split-Path $PSScriptRoot -Parent) "bin\bsp-launcher.exe" }
if (-not (Test-Path $Exe)) { throw "런처를 찾지 못함 : $Exe" }

$rows = @()
function Check([string]$name, [bool]$ok, [string]$detail) {
  $script:rows += [pscustomobject]@{ 항목 = $name; 판정 = $(if ($ok) { "PASS" } else { "FAIL" }); 내용 = $detail }
  $c = if ($ok) { "Green" } else { "Red" }
  Write-Host ("{0,-6} {1,-18} {2}" -f $(if ($ok) { "PASS" } else { "FAIL" }), $name, $detail) -ForegroundColor $c
}
function Sha256([string]$p) { (Get-FileHash $p -Algorithm SHA256).Hash.ToLower() }

# ── 격리된 무대 ────────────────────────────────────────────────────────
$stage = Join-Path ([IO.Path]::GetTempPath()) ("bsp-selftest-" + [Guid]::NewGuid().ToString("N").Substring(0, 8))
$appdata = Join-Path $stage "AppData"
$agent = Join-Path $stage "agent"
$srv = Join-Path $stage "srv"
New-Item -ItemType Directory -Force $appdata, $agent, $srv, "$srv\blobs" | Out-Null
Copy-Item $Exe (Join-Path $agent "bsp-launcher.exe") -Force
$agentExe = Join-Path $agent "bsp-launcher.exe"
$state = Join-Path $appdata "BSP\Platform"

function WriteConfig([string]$url) {
  $cfg = @{ server = ""; manifestUrl = $url; usageUrl = ""; memberUrl = ""; authHeader = $AuthHeader
            token = $Token; tenant = "selftest"; revitYear = $RevitYear; pollSeconds = 60 } | ConvertTo-Json
  [IO.File]::WriteAllText((Join-Path $agent "config.json"), $cfg, (New-Object Text.UTF8Encoding($false)))
}
function Sync() {
  # 상태 폴더를 통째로 옮겨 시험한다 — 현장 설치 상태를 건드리지 않는다
  $env:BSP_STATE_DIR = $state
  $env:BSP_ADDINS_DIR = Join-Path $appdata "Addins"
  try { & $agentExe sync 2>&1 | Out-String }
  finally { Remove-Item Env:BSP_STATE_DIR, Env:BSP_ADDINS_DIR -ErrorAction SilentlyContinue }
}
function MakeCatalog([string]$ver, [string]$blob, [string]$sha) {
  $size = (Get-Item $blob).Length
  $u = ([Uri]$blob).AbsoluteUri
  $j = @"
{"schema":2,"generated":"$(Get-Date -f s)","products":[
 {"id":"selftest.demo","name":"자체 시험","publisher":"BSP","kind":"tool","minRevit":"$RevitYear",
  "latest":"$ver","versions":[{"version":"$ver","files":[
   {"path":"demo/payload.txt","size":$size,"sha256":"$sha","url":"$u"}]}]}]}
"@
  $p = Join-Path $srv "catalog.json"
  [IO.File]::WriteAllText($p, $j, (New-Object Text.UTF8Encoding($false)))
  return ([Uri]$p).AbsoluteUri
}

Write-Host "`n무대 : $stage" -ForegroundColor DarkGray
Write-Host ("-" * 92)

# ── A. 런처 쪽 계약 (서버 없이 · 파일 URL 고정물) ──────────────────────
$blob1 = Join-Path $srv "blobs\payload-1.txt"
[IO.File]::WriteAllText($blob1, "version-one", (New-Object Text.UTF8Encoding($false)))
$sha1 = Sha256 $blob1
$dest = Join-Path $state "Tools\selftest.demo\demo\payload.txt"

WriteConfig (MakeCatalog "1.0.0" $blob1 $sha1)
$null = Sync
Check "설치" (Test-Path $dest) $(if (Test-Path $dest) { "선언한 경로에 놓임" } else { "놓이지 않음 : $dest" })
Check "해시" ((Test-Path $dest) -and ((Sha256 $dest) -eq $sha1)) "카탈로그 값과 대조"

# 변조 — 해시를 틀리게 선언하면 배치되면 안 된다
$blob2 = Join-Path $srv "blobs\payload-2.txt"
[IO.File]::WriteAllText($blob2, "tampered-content", (New-Object Text.UTF8Encoding($false)))
WriteConfig (MakeCatalog "2.0.0" $blob2 ("0" * 64))
$null = Sync
$after = if (Test-Path $dest) { Get-Content $dest -Raw } else { "" }
Check "변조 거부" ($after -eq "version-one") "해시 불일치본이 배치되지 않음"

# 새 버전 — 옛 파일을 지우고 새것을 놓는다
$sha2 = Sha256 $blob2
WriteConfig (MakeCatalog "2.0.0" $blob2 $sha2)
$null = Sync
$after = if (Test-Path $dest) { Get-Content $dest -Raw } else { "" }
Check "새 버전" ($after -eq "tampered-content") "2.0.0 으로 교체됨"

# 서버 정지 — 없어져도 죽지 않고 마지막 상태를 유지한다
Remove-Item (Join-Path $srv "catalog.json") -Force
$out = Sync
Check "서버 정지" ((Test-Path $dest) -and ($LASTEXITCODE -eq 0)) "런처 정상 종료 · 설치물 유지"

# ── B. 그쪽 서버 (주소를 준 경우에만) ──────────────────────────────────
if ($ManifestUrl) {
  Write-Host ("-" * 92)
  $ok = $false; $detail = ""
  try {
    $h = @{}; if ($Token) { $h[$AuthHeader] = $Token }
    $r = Invoke-WebRequest -Uri $ManifestUrl -Headers $h -UseBasicParsing
    $m = $r.Content | ConvertFrom-Json
    $bad = @()
    foreach ($p in $m.products) {
      if (-not ($p.versions | Where-Object { $_.version -eq $p.latest })) { $bad += "$($p.id) latest=$($p.latest) 없음" }
      foreach ($v in $p.versions) { foreach ($f in $v.files) {
        if (-not $f.sha256 -or $f.sha256.Length -ne 64) { $bad += "$($p.id) $($f.path) sha256 형식" }
        if (-not $f.url) { $bad += "$($p.id) $($f.path) url 없음" } } }
    }
    $ok = ($bad.Count -eq 0)
    $detail = if ($ok) { "제품 $($m.products.Count)개 · 형식 정상" } else { ($bad -join " / ") }
  } catch { $detail = $_.Exception.Message }
  Check "카탈로그" $ok $detail

  Remove-Item (Join-Path $state "Tools") -Recurse -Force -ErrorAction SilentlyContinue
  WriteConfig $ManifestUrl
  $out = Sync
  $placed = @(Get-ChildItem (Join-Path $state "Tools") -Recurse -File -ErrorAction SilentlyContinue)
  Check "실제 배포" ($placed.Count -gt 0) "$($placed.Count)개 파일 배치"
}

Write-Host ("-" * 92)
$fail = @($rows | Where-Object { $_.판정 -eq "FAIL" }).Count
Write-Host ("결과 : {0} PASS · {1} FAIL" -f ($rows.Count - $fail), $fail) -ForegroundColor $(if ($fail) { "Red" } else { "Green" })
Write-Host "무대는 남겨 둔다 (확인용) : $stage" -ForegroundColor DarkGray
exit $(if ($fail) { 1 } else { 0 })

<#
  bsp-apply — 한 번 실행하면 끝난다.
    점검 → 붙이기 → 고치기 → 빌드 → 검증 → 결과표

    .\AI\apply.ps1 -Project C:\내플랫폼\MyAddin            (폴더 또는 .csproj)
    .\AI\apply.ps1 -Project ... -ManifestUrl https://…     서버까지 같이 점검
    .\AI\apply.ps1 -Project ... -Check                     건드리지 않고 점검만

  하는 일
    1. 보관        snapshot (언제든 -Restore 로 되돌림)
    2. 코드 점검    IExternalApplication · OnStartup/OnShutdown · 이미 붙었나
    3. 참조 점검    RevitAPI 연도 일치 · 같은 어셈블리 두 버전 · 런타임 계열 · 서명
    4. 붙이기      OnStartup 에 Attach, OnShutdown 에 Detach (기존 코드는 안 지운다)
    5. 참조 추가    BSP.Platform.Agent.dll (+ 출력 폴더에 bsp-launcher.exe)
    6. 빌드        csproj 면 msbuild/dotnet, 아니면 건너뛴다
    7. 검증        bsp-probe cycle + 서버 점검
#>
param(
  [Parameter(Mandatory = $true)][string]$Project,
  [string]$ManifestUrl = "", [string]$Token = "", [string]$AuthHeader = "x-bsp-key",
  [string]$RevitYear = "2024",
  [string]$InstallTo = "",
  [switch]$Check, [switch]$NoBuild
)

$ErrorActionPreference = "Stop"
$sdk = Split-Path $PSScriptRoot -Parent
$rows = @()
function Row($step, $ok, $detail) {
  $script:rows += [pscustomobject]@{ 단계 = $step; 판정 = $(if ($ok -eq $null) { "—" } elseif ($ok) { "OK" } else { "FAIL" }); 내용 = $detail }
  $c = if ($ok -eq $null) { "DarkGray" } elseif ($ok) { "Green" } else { "Red" }
  Write-Host ("{0,-5} {1,-14} {2}" -f $(if ($ok -eq $null) { "  · " } elseif ($ok) { "OK" } else { "FAIL" }), $step, $detail) -ForegroundColor $c
}

Write-Host "`nbsp-apply · $Project" -ForegroundColor Cyan
Write-Host ("-" * 92)

# ── 1. 대상 파악 ────────────────────────────────────────────────────
if (-not (Test-Path $Project)) { Row "대상" $false "경로가 없습니다"; exit 1 }
$isProj = $Project -like "*.csproj"
$root = if ($isProj) { Split-Path $Project -Parent } else { (Resolve-Path $Project).Path }
$csproj = if ($isProj) { $Project } else { (Get-ChildItem $root -Filter *.csproj -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1).FullName }
$sources = @(Get-ChildItem $root -Filter *.cs -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(obj|bin)\\' })
Row "대상" $true ("소스 {0}개 · {1}" -f $sources.Count, $(if ($csproj) { Split-Path $csproj -Leaf } else { "csproj 없음 (빌드는 건너뜀)" }))

# ── 2. 진입점 찾기 ──────────────────────────────────────────────────
$entry = $null
foreach ($f in $sources) {
  $t = [IO.File]::ReadAllText($f.FullName)
  if ($t -match 'IExternalApplication' -and $t -match 'OnStartup') { $entry = $f; break }
}
if (-not $entry) { Row "진입점" $false "IExternalApplication 구현을 못 찾음 — 경로를 확인하세요"; exit 1 }
$src = [IO.File]::ReadAllText($entry.FullName)
$already = $src -match 'BspAgent\.Attach'
Row "진입점" $true ("{0}{1}" -f $entry.Name, $(if ($already) { "  (이미 붙어 있음)" } else { "" }))

# ── 3. 참조 점검 ────────────────────────────────────────────────────
$built = @(Get-ChildItem $root -Filter *.dll -Recurse -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -match '\\bin\\' -and $_.Name -notmatch '^(Revit|AdWindows|System\.)' })
$verdict = $true; $notes = @()
foreach ($d in $built) {
  try {
    # ★ ReflectionOnlyLoadFrom 은 그 파일을 **프로세스가 끝날 때까지 잠근다.**
    #   그러면 바로 다음 «빌드» 칸이 그 DLL 을 덮지 못해 실패한다 (실측).
    #   바이트로 읽어 로드하면 파일 손잡이가 바로 닫힌다.
    $bytes = [IO.File]::ReadAllBytes($d.FullName)
    $a = [Reflection.Assembly]::ReflectionOnlyLoad($bytes)
    $refs = $a.GetReferencedAssemblies()
    $dupes = $refs | Group-Object Name | Where-Object Count -gt 1
    foreach ($g in $dupes) { $verdict = $false; $notes += "$($d.Name) : $($g.Name) 가 $($g.Count)개 버전" }
    $api = @($refs | Where-Object Name -match '^RevitAPI')
    foreach ($r in $api) {
      $major = $r.Version.Major
      if ($major -ne ([int]$RevitYear - 2000)) {
        $verdict = $false
        $notes += "$($d.Name) : $($r.Name) $($r.Version) — 선언 $RevitYear 와 불일치 (누르는 순간 죽는 사고 유형)"
      }
    }
  } catch { }
}
if ($built.Count -eq 0) { Row "참조 점검" $null "빌드 산출물이 없어 건너뜀 (빌드 후 다시 확인됩니다)" }
else { Row "참조 점검" $verdict $(if ($verdict) { "$($built.Count)개 DLL · 충돌 없음 · API $RevitYear 일치" } else { ($notes | Select-Object -First 3) -join " / " }) }

if ($Check) {
  Write-Host ("-" * 92)
  Write-Host "점검만 했습니다. 붙이려면 -Check 를 빼고 다시 실행하세요." -ForegroundColor Yellow
  exit $(if ($verdict) { 0 } else { 1 })
}

# ── 4. 보관 ────────────────────────────────────────────────────────
& (Join-Path $PSScriptRoot "snapshot.ps1") -RevitYear $RevitYear | Out-Null
$stash = Join-Path ([IO.Path]::GetTempPath()) ("bsp-apply-" + (Get-Date -f "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Force $stash | Out-Null
Copy-Item $entry.FullName $stash -Force
if ($csproj) { Copy-Item $csproj $stash -Force }
Row "보관" $true $stash

# ── 5. 두 줄 붙이기 ────────────────────────────────────────────────
if ($already) { Row "붙이기" $null "이미 붙어 있어 건너뜀" }
else {
  $new = $src
  if ($new -notmatch 'using\s+BSP\.Platform\.Agent\s*;') {
    $new = [regex]::Replace($new, '(using\s+Autodesk\.Revit\.UI\s*;)', "`$1`r`nusing BSP.Platform.Agent;", 1)
  }
  # OnStartup 의 여는 중괄호 바로 뒤에 Attach — 기존 코드보다 먼저 세션을 남긴다
  $new = [regex]::Replace($new,
    '(?s)(Result\s+OnStartup\s*\([^)]*\)\s*\{)',
    "`$1`r`n            BSP.Platform.Agent.BspAgent.Attach(a.ControlledApplication.VersionNumber, System.Diagnostics.Process.GetCurrentProcess().Id);   // BSP SDK", 1)
  $new = [regex]::Replace($new,
    '(?s)(Result\s+OnShutdown\s*\([^)]*\)\s*\{)',
    "`$1`r`n            BSP.Platform.Agent.BspAgent.Detach();   // BSP SDK", 1)

  if ($new -eq $src) { Row "붙이기" $false "OnStartup/OnShutdown 서명을 찾지 못함 — 수동으로 두 줄 넣으세요" }
  else {
    [IO.File]::WriteAllText($entry.FullName, $new, (New-Object Text.UTF8Encoding($false)))
    Row "붙이기" $true "$($entry.Name) 에 Attach/Detach 두 줄 (기존 코드는 그대로)"
  }
}

# ── 6. 참조·파일 배치 ──────────────────────────────────────────────
$agent = Join-Path $sdk "bin\BSP.Platform.Agent.dll"
$mgr = Join-Path $sdk "bin\bsp-launcher.exe"
$lib = Join-Path $root "lib"
New-Item -ItemType Directory -Force $lib | Out-Null
Copy-Item $agent, $mgr $lib -Force
if ($csproj) {
  $x = [xml](Get-Content $csproj)
  $ns = $x.Project.NamespaceURI
  $has = $x.SelectNodes("//*[local-name()='Reference']") | Where-Object { $_.Include -like "BSP.Platform.Agent*" }
  if (-not $has) {
    $ig = $x.CreateElement("ItemGroup", $ns)
    $ref = $x.CreateElement("Reference", $ns)
    $ref.SetAttribute("Include", "BSP.Platform.Agent")
    $hp = $x.CreateElement("HintPath", $ns); $hp.InnerText = "lib\BSP.Platform.Agent.dll"
    $pv = $x.CreateElement("Private", $ns); $pv.InnerText = "true"
    $ref.AppendChild($hp) | Out-Null; $ref.AppendChild($pv) | Out-Null
    $ig.AppendChild($ref) | Out-Null; $x.Project.AppendChild($ig) | Out-Null
    $x.Save($csproj)
    Row "참조 추가" $true "csproj 에 BSP.Platform.Agent (lib\)"
  }
  else { Row "참조 추가" $null "이미 있음" }
}
else { Row "참조 추가" $null "csproj 가 없어 lib\ 에 파일만 놓음 — 빌드 스크립트에 /r: 로 추가하세요" }

# ── 6-1. 서버 연결 — 한 번 확인하고 설정에 박아 둔다 ────────────────
#   이게 되면 리빗을 켤 때마다 매니저가 알아서 받아 둔다. 사람이 할 일은 없다.
$cfgPath = Join-Path $lib "config.json"
if ($ManifestUrl) {
  $ok = $false; $detail = ""
  try {
    $h = @{}; if ($Token) { $h[$AuthHeader] = $Token }
    $r = Invoke-WebRequest -Uri $ManifestUrl -Headers $h -UseBasicParsing -TimeoutSec 20
    $m = $r.Content | ConvertFrom-Json
    $bad = @()
    foreach ($pr in $m.products) {
      if (-not ($pr.versions | Where-Object { $_.version -eq $pr.latest })) { $bad += "$($pr.id): latest 없음" }
      foreach ($v in $pr.versions) { foreach ($f in $v.files) {
        if (-not $f.sha256 -or $f.sha256.Length -ne 64) { $bad += "$($pr.id)/$($f.path): sha256" }
        if (-not $f.url) { $bad += "$($pr.id)/$($f.path): url" } } }
    }
    $ok = ($bad.Count -eq 0)
    $detail = if ($ok) { "제품 $($m.products.Count)개 · 형식 정상" } else { ($bad | Select-Object -First 2) -join " / " }
  } catch { $detail = $_.Exception.Message }
  Row "서버 연결" $ok $detail
}
else { Row "서버 연결" $null "주소를 주지 않아 오프라인 설정 (나중에 config.json 의 manifestUrl 만 채우면 된다)" }

$cfg = [ordered]@{
  server = ""; manifestUrl = $ManifestUrl; usageUrl = ""; memberUrl = ""
  authHeader = $AuthHeader; token = $Token; tenant = "bsp-internal"
  revitYear = $RevitYear; pollSeconds = 60; requireMember = $false
  lifetime = "addon"; exitGraceSeconds = 60
} | ConvertTo-Json
[IO.File]::WriteAllText($cfgPath, $cfg, (New-Object Text.UTF8Encoding($false)))
Row "설정" $true $cfgPath

# ── 6-2. 설치 (원하면) — 애드온 폴더에 네 파일을 나란히 ─────────────
if ($InstallTo) {
  if (Get-Process Revit -ErrorAction SilentlyContinue) {
    Row "설치" $false "리빗이 켜져 있습니다 — 닫고 다시 실행하세요"
  }
  else {
    New-Item -ItemType Directory -Force $InstallTo | Out-Null
    Copy-Item $agent, $mgr, $cfgPath $InstallTo -Force
    Row "설치" $true "$InstallTo (에이전트·매니저·설정)"
  }
}

# ── 7. 빌드 ────────────────────────────────────────────────────────
if ($NoBuild -or -not $csproj) { Row "빌드" $null "건너뜀" }
else {
  $msb = (Get-Command msbuild -ErrorAction SilentlyContinue)
  $log = Join-Path $stash "build.log"
  if ($msb) { & msbuild $csproj /v:m /nologo > $log 2>&1 }
  else { & dotnet build $csproj -v m > $log 2>&1 }

  if ($LASTEXITCODE -eq 0) { Row "빌드" $true "성공" }
  else {
    # ★ «컴파일 실패» 와 «복사 실패» 를 구분한다.
    #   리빗이 켜져 있으면 프로젝트의 배포 복사(Addins 로)가 막힌다 — 컴파일은 된 것이다.
    #   그 배치는 원래 매니저가 리빗 종료 때 하는 일이므로 여기서 실패로 셀 이유가 없다.
    $logTxt = Get-Content $log -Raw -ErrorAction SilentlyContinue
    $copyOnly = ($logTxt -match 'MSB302[17]') -and ($logTxt -notmatch '\): error CS')
    $revitLock = $logTxt -match 'Revit'
    if ($copyOnly -and $revitLock) {
      Row "빌드" $null "컴파일 성공 · 배치는 리빗이 물고 있어 보류 (종료 때 매니저가 넣습니다)"
    }
    else { Row "빌드" $false "실패 — $log" }
  }
}

# ── 8. 검증 ────────────────────────────────────────────────────────
$probe = Join-Path $sdk "bin\bsp-probe.exe"
if (Test-Path $probe) {
  $out = & $probe cycle 2>&1 | Out-String
  # 요약 줄만 믿는다 — 본문에도 PASS/FAIL 이라는 낱말이 나온다
  $m = [regex]::Match($out, "결과 : (\d+) PASS . (\d+) FAIL")
  if ($m.Success) {
    $pass = [int]$m.Groups[1].Value; $fail = [int]$m.Groups[2].Value
    Row "코어 검증" ($fail -eq 0) "bsp-probe cycle : $pass PASS · $fail FAIL"
  }
  else { Row "코어 검증" $false "probe 결과를 읽지 못함" }
}

if ($ManifestUrl) {
  $st = & (Join-Path $PSScriptRoot "selftest.ps1") -ManifestUrl $ManifestUrl -Token $Token -AuthHeader $AuthHeader 2>&1 | Out-String
  $m2 = [regex]::Match($st, "결과 : (\d+) PASS . (\d+) FAIL")
  $sf = if ($m2.Success) { [int]$m2.Groups[2].Value } else { 1 }
  Row "서버 점검" ($sf -eq 0) $(if ($m2.Success) { $m2.Value } else { "selftest 결과를 읽지 못함" })
}
else { Row "서버 점검" $null "주소를 주지 않아 건너뜀 (-ManifestUrl)" }

Write-Host ("-" * 92)
$bad = @($rows | Where-Object 판정 -eq "FAIL").Count
Write-Host ("결과 : {0} OK · {1} FAIL" -f @($rows | Where-Object 판정 -eq "OK").Count, $bad) -ForegroundColor $(if ($bad) { "Red" } else { "Green" })
if ($bad -eq 0) {
  Write-Host "" 
  Write-Host "끝났습니다. 이제 리빗을 켜면 :" -ForegroundColor Cyan
  Write-Host "   · 매니저가 자동으로 뜨고(별도 프로세스), 리빗을 닫으면 같이 정리됩니다"
  Write-Host "   · 서버에 새 버전이 올라오면 받아 두었다가 다음 기동 때 적용됩니다"
  Write-Host "   · 사용·멈춤·사고 기록이 남습니다.  확인 :  .\AI\healthcheck.ps1"
}
Write-Host "되돌리기 : 리빗 닫고  .\AI\snapshot.ps1 -Restore   (코드는 $stash 에 원본 보관)" -ForegroundColor DarkGray
exit $(if ($bad) { 1 } else { 0 })

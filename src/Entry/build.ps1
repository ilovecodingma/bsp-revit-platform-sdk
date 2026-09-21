# BSP 플랫폼 엔트리포인트 빌드 (net48 · 리빗 설치 없이도 NuGet 참조로 대체 가능)
#   .\build.ps1                    빌드만
#   .\build.ps1 -Install           빌드 + Addins 폴더 설치 (리빗 꺼져 있어야 함)
#   .\build.ps1 -RevitYear 2023    다른 연도
param([switch]$Install, [string]$RevitYear = "2024")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$out  = Join-Path $here "bin"
$csc  = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$rev  = "C:\Program Files\Autodesk\Revit $RevitYear"

if (-not (Test-Path $csc)) { throw "csc 없음 : $csc" }
if (-not (Test-Path "$rev\RevitAPI.dll")) { throw "RevitAPI 없음 : $rev  (NuGet Nice3point.Revit.Api.RevitAPI 로 대체 가능)" }
New-Item -ItemType Directory -Force $out | Out-Null

$refs = @(
  "$rev\RevitAPI.dll", "$rev\RevitAPIUI.dll",
  "$here\..\Agent\bin\BSP.Platform.Agent.dll",
  "System.dll", "System.Core.dll", "System.Management.dll"
) | ForEach-Object { "/r:`"$_`"" }

$dll = Join-Path $out "BSP.Platform.Entry.dll"
& $csc /nologo /target:library /platform:x64 /optimize+ /codepage:65001 `
       /out:"$dll" $refs "$here\Entry.cs"
if ($LASTEXITCODE -ne 0) { throw "컴파일 실패" }
Write-Host ("[빌드] {0}  ({1} KB)" -f $dll, [int]((Get-Item $dll).Length/1KB))

# .addin — 이 파일 하나만 Addins 폴더에 둔다. 도구들은 각자 매니페스트를 두지 않는다.
$addin = @"
<?xml version="1.0" encoding="utf-8"?>
<RevitAddIns>
  <AddIn Type="Application">
    <Name>BSP Platform</Name>
    <Assembly>BSP.Platform.Entry\BSP.Platform.Entry.dll</Assembly>
    <AddInId>5C7D1E92-3A46-4B08-9F21-6D4E8B3A7C55</AddInId>
    <FullClassName>BSP.Platform.Entry.App</FullClassName>
    <VendorId>BSPE</VendorId>
    <VendorDescription>BSP ENGINEERING CO., Ltd</VendorDescription>
  </AddIn>
</RevitAddIns>
"@
$addinPath = Join-Path $out "BSP.Platform.Entry.addin"
[IO.File]::WriteAllText($addinPath, $addin, (New-Object Text.UTF8Encoding($false)))
Write-Host "[빌드] $addinPath"

if ($Install) {
  if (Get-Process Revit -ErrorAction SilentlyContinue) {
    Write-Host "[설치] 리빗이 실행 중입니다 — DLL 이 잠겨 설치할 수 없습니다." -ForegroundColor Yellow
    exit 2
  }
  $dest = "$env:APPDATA\Autodesk\Revit\Addins\$RevitYear"
  New-Item -ItemType Directory -Force (Join-Path $dest "BSP.Platform.Entry") | Out-Null
  Copy-Item $dll (Join-Path $dest "BSP.Platform.Entry\BSP.Platform.Entry.dll") -Force
  Copy-Item "$here\..\Agentin\BSP.Platform.Agent.dll" (Join-Path $dest "BSP.Platform.Entry\") -Force
  Copy-Item $addinPath (Join-Path $dest "BSP.Platform.Entry.addin") -Force

  # 매니저 본체는 애드온 옆에 둔다 — 애드온이 가장 먼저 찾는 자리
  $lax = Join-Path (Split-Path $here -Parent) "..\bin\bsp-launcher.exe" | Resolve-Path -ErrorAction SilentlyContinue
  if ($lax) { Copy-Item $lax (Join-Path $dest "BSP.Platform.Entry\bsp-launcher.exe") -Force }
  Write-Host "[설치] $dest"
}

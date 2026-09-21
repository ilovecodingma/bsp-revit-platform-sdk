# 샘플 도구 빌드 — 이 스크립트가 도구 빌드의 최소 형태다.
#   .\build.ps1            빌드
#   .\build.ps1 -Verify    빌드 + 적합성 검사 (bsp-verify)
param([switch]$Verify, [string]$RevitYear = "2024")

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$sdk  = (Resolve-Path (Join-Path $here "..\..")).Path
$out  = Join-Path $here "bin"
$csc  = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$rev  = "C:\Program Files\Autodesk\Revit $RevitYear"
$fw   = "${env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.8"

if (-not (Test-Path "$rev\RevitAPI.dll")) { throw "RevitAPI 없음 : $rev" }
New-Item -ItemType Directory -Force $out | Out-Null

$refs = @(
  "$rev\RevitAPI.dll", "$rev\RevitAPIUI.dll",
  "$sdk\bin\BSP.Contracts.dll",                     # ← 참조만. 결과물에 **동봉하지 않는다**
  "System.dll", "System.Core.dll",
  "$fw\PresentationCore.dll", "$fw\WindowsBase.dll"
) | ForEach-Object { "/r:`"$_`"" }

$dll = Join-Path $out "BSP.Sample.HelloTool.dll"
& $csc /nologo /target:library /platform:x64 /optimize+ /codepage:65001 `
       /out:"$dll" $refs "$here\HelloTool.cs"
if ($LASTEXITCODE -ne 0) { throw "컴파일 실패" }
Copy-Item (Join-Path $here "product.json") $out -Force
Write-Host ("[빌드] {0}  ({1} KB)" -f $dll, [int]((Get-Item $dll).Length/1KB))

if ($Verify) {
  & "$sdk\bin\bsp-verify.exe" $out --id bsp.sample.hello --version 1.0.0 --target $RevitYear
}

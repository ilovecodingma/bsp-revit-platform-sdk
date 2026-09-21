# BSP.Platform.Agent.dll — 이미 있는 애드온에 끼우는 라이브러리
#   리빗을 참조하지 않는다 → 리빗이 안 깔린 PC 에서도 빌드된다. 연도에 묶이지 않는다.
param([switch]$Net8)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot
$out = Join-Path $here "bin"
New-Item -ItemType Directory -Force $out | Out-Null

$src = @("$here\Agent.cs", "$here\LauncherHost.cs", "$here\Requests.cs")

if ($Net8) {
  # Revit 2025+ (.NET 8) — dotnet SDK 가 필요하다
  $proj = Join-Path $out "net8"
  New-Item -ItemType Directory -Force $proj | Out-Null
  @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0-windows</TargetFramework>
    <AssemblyName>BSP.Platform.Agent</AssemblyName>
    <RootNamespace>BSP.Platform.Agent</RootNamespace>
    <Nullable>disable</Nullable>
    <LangVersion>latest</LangVersion>
  </PropertyGroup>
  <ItemGroup>
    <Compile Remove="**/*.cs" />
"@ + (($src | ForEach-Object { "    <Compile Include=`"$_`" />" }) -join "`n") + @"

    <PackageReference Include="System.Management" Version="8.0.0" />
  </ItemGroup>
</Project>
"@ | Set-Content (Join-Path $proj "Agent.csproj") -Encoding UTF8
  & dotnet build (Join-Path $proj "Agent.csproj") -c Release -o $out
  if ($LASTEXITCODE -ne 0) { throw "net8 빌드 실패" }
}
else {
  $csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
  $dll = Join-Path $out "BSP.Platform.Agent.dll"
  & $csc /nologo /target:library /platform:x64 /optimize+ /codepage:65001 `
         /out:"$dll" /r:System.dll /r:System.Core.dll /r:System.Management.dll $src
  if ($LASTEXITCODE -ne 0) { throw "컴파일 실패" }
  Write-Host ("[빌드] {0}  ({1} KB · net48 · 리빗 참조 없음)" -f $dll, [int]((Get-Item $dll).Length / 1KB))
}

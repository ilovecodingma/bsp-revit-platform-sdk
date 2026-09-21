<#
  카탈로그 생성기 — «파일만 있는 서버» 를 배포 서버로 만든다.

  서버가 우리 것이 아니어도 된다. 파일을 올려 둘 수만 있으면 된다.
  이 스크립트가 폴더를 훑어 SHA-256 을 계산하고 catalog.json 한 장을 만든다.
  그 파일을 같이 올려 두고 런처의 manifestUrl 을 그 주소로 가리키면 끝이다.

    .\make-catalog.ps1 -Root .\배포할폴더 -Id bsp.hts -Version 2026.09.21 -BaseUrl https://내서버/files
    .\make-catalog.ps1 -Root . -Id a -Version 1 -BaseUrl file://\\파일서버\bsp   # 공유 폴더도 된다
    .\make-catalog.ps1 -Root . -Id a -Version 2 -BaseUrl https://…  -Merge .\catalog.json

  -Merge 를 주면 기존 카탈로그에 이 제품/버전을 얹는다 (다른 제품은 그대로 둔다).
#>
param(
  [Parameter(Mandatory = $true)][string]$Root,
  [Parameter(Mandatory = $true)][string]$Id,
  [Parameter(Mandatory = $true)][string]$Version,
  [Parameter(Mandatory = $true)][string]$BaseUrl,
  [string]$Name = "", [string]$Publisher = "", [string]$Kind = "tool",
  [string]$MinRevit = "2024", [string]$Out = "catalog.json", [string]$Merge = ""
)

$ErrorActionPreference = "Stop"
$Root = (Resolve-Path $Root).Path
if (-not $Name) { $Name = $Id }
$BaseUrl = $BaseUrl.TrimEnd('/')

$files = @()
foreach ($f in Get-ChildItem $Root -Recurse -File) {
  $rel = $f.FullName.Substring($Root.Length).TrimStart('\', '/').Replace('\', '/')
  $files += [ordered]@{
    path   = $rel
    size   = $f.Length
    sha256 = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
    # 주소 체계는 서버 것이다. 여기서는 «기준 주소 + 버전 + 상대경로» 로 짐작해 만든다.
    url    = "$BaseUrl/$Id/$Version/$rel"
  }
}
if (-not $files.Count) { throw "파일이 없습니다 : $Root" }

$product = [ordered]@{
  id = $Id; name = $Name; publisher = $Publisher; kind = $Kind
  minRevit = $MinRevit; channel = "stable"; latest = $Version
  versions = @([ordered]@{ version = $Version; files = $files })
}

if ($Merge -and (Test-Path $Merge)) {
  $cat = [IO.File]::ReadAllText($Merge) | ConvertFrom-Json
  $keep = @($cat.products | Where-Object { $_.id -ne $Id })
  # 같은 제품의 옛 버전은 살려 둔다 — 되돌리기(롤백) 수단이 된다
  $old = @($cat.products | Where-Object { $_.id -eq $Id })
  if ($old.Count) {
    $vers = @($old[0].versions | Where-Object { $_.version -ne $Version })
    $product.versions = @($product.versions) + $vers
  }
  $products = @($keep) + @($product)
}
else { $products = @($product) }

$catalog = [ordered]@{
  schema    = 2
  generated = (Get-Date -f "yyyy-MM-ddTHH:mm:ss")
  products  = @($products)
}
if (-not [IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location).Path $Out }
[IO.File]::WriteAllText($Out, ($catalog | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))

Write-Host ("카탈로그 : {0}" -f (Resolve-Path $Out).Path) -ForegroundColor Green
Write-Host ("  제품 {0}개 · 이번 제품 {1}@{2} · 파일 {3}개" -f $catalog.products.Count, $Id, $Version, $files.Count)
Write-Host ""
Write-Host "다음 : 이 파일과 $Root 의 파일들을 서버에 올린 뒤" -ForegroundColor Cyan
Write-Host "       config.json 의 manifestUrl 을 catalog.json 주소로 맞추세요."
Write-Host "       확인 :  .\AI\selftest.ps1 -ManifestUrl <그 주소>"

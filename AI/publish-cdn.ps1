<#
  publish-cdn — 어느 CDN 에도 그대로 올릴 수 있는 정적 묶음을 만든다.

     .\AI\publish-cdn.ps1 -Assets <제품폴더> -CdnBase https://cdn.회사.com/bsp
     .\AI\publish-cdn.ps1 -Assets ... -CdnBase ... -CatalogBase https://api.회사.com/bsp   (목록만 다른 곳)

  왜 이렇게 만드나 — **파일 이름을 내용(SHA-256)으로 짓는다.**

    assets/<제품>/<버전>/BSP.Hub.dll     →   blobs/9f3a…c1/BSP.Hub.dll
                                              └ 내용이 같으면 주소도 같다

    · 같은 파일은 제품·버전이 달라도 **한 번만** 올라간다 (중복 제거)
    · 주소가 내용이므로 **영원히 캐시**해도 안전하다 (immutable, max-age 1년)
    · 되돌리기는 옛 카탈로그만 도로 올리면 끝 — 파일은 이미 CDN 에 있다
    · CDN 을 바꿔도 catalog.json 의 앞부분만 바뀐다

  만들어지는 것
    dist/catalog.json      런처가 읽는 목록 (여기만 캐시 금지)
    dist/blobs/<sha>/<이름>  실제 파일 (영구 캐시)
    dist/UPLOAD.md         제공업체별 올리는 한 줄
#>
param(
  [Parameter(Mandatory = $true)][string]$Assets,      # <제품>/<버전>/... 구조의 폴더
  [Parameter(Mandatory = $true)][string]$CdnBase,     # 예: https://cdn.회사.com/bsp
  [string]$CatalogBase = "",                          # 목록을 다른 호스트에 둘 때
  [string]$Out = "",
  [string]$Meta = ""                                  # 기존 catalog.json (이름·종류·도구 메타를 가져온다)
)

$ErrorActionPreference = "Stop"
$Assets = (Resolve-Path $Assets).Path
if (-not $Out) { $Out = Join-Path (Split-Path $Assets -Parent) "dist" }
$CdnBase = $CdnBase.TrimEnd('/')
New-Item -ItemType Directory -Force $Out, (Join-Path $Out "blobs") | Out-Null

# 기존 카탈로그에서 제품 메타(이름·종류·도구 목록)를 가져온다 — 없으면 기본값
$meta = @{}
if ($Meta -and (Test-Path $Meta)) {
  $old = [IO.File]::ReadAllText($Meta) | ConvertFrom-Json
  foreach ($p in $old.products) { $meta[$p.id] = $p }
}

$products = @()
$blobCount = 0; $dedupe = 0; $bytes = 0
foreach ($pdir in Get-ChildItem $Assets -Directory) {
  $id = $pdir.Name
  $versions = @()
  foreach ($vdir in Get-ChildItem $pdir.FullName -Directory | Sort-Object Name) {
    $files = @()
    foreach ($f in Get-ChildItem $vdir.FullName -Recurse -File) {
      $rel = $f.FullName.Substring($vdir.FullName.Length).TrimStart('\', '/').Replace('\', '/')
      $sha = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
      $dst = Join-Path $Out ("blobs\" + $sha)
      if (Test-Path (Join-Path $dst $f.Name)) { $dedupe++ }
      else {
        New-Item -ItemType Directory -Force $dst | Out-Null
        Copy-Item $f.FullName (Join-Path $dst $f.Name) -Force
        $blobCount++; $bytes += $f.Length
      }
      $files += [ordered]@{
        path = $rel; size = $f.Length; sha256 = $sha
        url = "$CdnBase/blobs/$sha/$($f.Name)"       # ← 내용 주소. 영구 캐시 가능
      }
    }
    if ($files.Count) { $versions += [ordered]@{ version = $vdir.Name; files = $files } }
  }
  if (-not $versions.Count) { continue }

  $m = $meta[$id]
  $p = [ordered]@{
    id = $id
    name = $(if ($m) { $m.name } else { $id })
    publisher = $(if ($m) { $m.publisher } else { "" })
    kind = $(if ($m) { $m.kind } else { "tool" })
    minRevit = $(if ($m) { $m.minRevit } else { "2024" })
    channel = "stable"
    latest = ($versions | Select-Object -Last 1).version
    versions = @($versions)
  }
  if ($m -and $m.PSObject.Properties.Name -contains "tools") { $p.tools = $m.tools; $p.toolCount = $m.toolCount; $p.shows = $m.shows }
  $products += $p
}

$catalog = [ordered]@{
  schema = 2
  generated = (Get-Date -f "yyyy-MM-ddTHH:mm:ss")
  cdn = $CdnBase
  products = @($products)
}
$catPath = Join-Path $Out "catalog.json"
[IO.File]::WriteAllText($catPath, ($catalog | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))

$catUrl = $(if ($CatalogBase) { $CatalogBase.TrimEnd('/') + "/catalog.json" } else { "$CdnBase/catalog.json" })
@"
# 올리는 법 — 어느 CDN 이든 «정적 파일 두 종류» 뿐이다

| 무엇 | 캐시 |
|---|---|
| ``blobs/<sha256>/<이름>`` | **영구** — ``Cache-Control: public, max-age=31536000, immutable`` |
| ``catalog.json`` | **금지** — ``Cache-Control: no-cache`` (또는 짧은 max-age + ETag) |

내용이 주소이므로 blobs 는 절대 바뀌지 않는다. 목록만 신선하면 된다.

## 제공업체별 한 줄

``````
# AWS S3 + CloudFront
aws s3 sync blobs/ s3://<버킷>/bsp/blobs/ --cache-control "public,max-age=31536000,immutable"
aws s3 cp   catalog.json s3://<버킷>/bsp/catalog.json --cache-control "no-cache"

# Cloudflare R2 (rclone)
rclone copy blobs/ r2:<버킷>/bsp/blobs/ --header-upload "Cache-Control: public,max-age=31536000,immutable"
rclone copy catalog.json r2:<버킷>/bsp/ --header-upload "Cache-Control: no-cache"

# Azure Blob + Front Door
az storage blob upload-batch -d '<컨테이너>/bsp/blobs' -s blobs --content-cache "public,max-age=31536000,immutable"
az storage blob upload -c '<컨테이너>' -n bsp/catalog.json -f catalog.json --content-cache "no-cache" --overwrite

# 사내 IIS / nginx — 그냥 폴더째 복사
robocopy . \\\\파일서버\\wwwroot\\bsp /E
``````

## 런처 설정

``````json
{ "manifestUrl": "$catUrl" }
``````

인증이 필요하면 ``authHeader`` · ``token`` 을, 헤더가 더 필요하면 ``headers`` 를 채운다.
**CDN 을 바꿔도 런처는 고치지 않는다** — 이 파일을 다시 만들어 올리면 끝이다.
"@ | Set-Content (Join-Path $Out "UPLOAD.md") -Encoding UTF8

Write-Host ("[묶음] {0}" -f $Out) -ForegroundColor Green
Write-Host ("  제품 {0}개 · 새 blob {1}개 ({2} KB) · 중복 제거 {3}개" -f $products.Count, $blobCount, [int]($bytes / 1KB), $dedupe)
Write-Host ("  목록 주소 : {0}" -f $catUrl)
Write-Host "  올리는 법 : $Out\UPLOAD.md"

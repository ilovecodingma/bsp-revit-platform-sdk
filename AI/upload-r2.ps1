<#
  upload-r2 — Cloudflare R2 에 올린다. **Node·wrangler 없이** 순수 PowerShell (S3 호환 API · SigV4).

     .\AI\upload-r2.ps1 -Dist <dist폴더> -Account <계정ID> -Bucket <버킷> `
                        -AccessKey <키> -SecretKey <비밀키> [-Prefix bsp]

  R2 준비 (대시보드에서 3분)
     1. R2 → 버킷 만들기            (예: bsp-catalog)
     2. R2 → Manage API Tokens → Create  (Object Read & Write)
        → Access Key ID · Secret Access Key 를 받는다
     3. 버킷 → Settings → Public access 또는 Custom domain 연결
        (예: https://cdn.회사.com  →  그 주소가 CdnBase 가 된다)

  올리는 규칙
     blobs/**      Cache-Control: public, max-age=31536000, immutable   ← 내용이 주소라 영구 캐시
     catalog.json  Cache-Control: no-cache                              ← 이것만 신선해야 한다
#>
param(
  [Parameter(Mandatory = $true)][string]$Dist,
  [Parameter(Mandatory = $true)][string]$Account,
  [Parameter(Mandatory = $true)][string]$Bucket,
  [Parameter(Mandatory = $true)][string]$AccessKey,
  [Parameter(Mandatory = $true)][string]$SecretKey,
  [string]$Prefix = "bsp",
  [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$Dist = (Resolve-Path $Dist).Path
$host_ = "$Account.r2.cloudflarestorage.com"
$region = "auto"
$service = "s3"

function Hex([byte[]]$b) { ($b | ForEach-Object { $_.ToString("x2") }) -join "" }
function Sha256Hex([byte[]]$b) { Hex ([Security.Cryptography.SHA256]::Create().ComputeHash($b)) }
function HmacRaw([byte[]]$key, [string]$msg) {
  $h = New-Object Security.Cryptography.HMACSHA256
  $h.Key = $key
  $h.ComputeHash([Text.Encoding]::UTF8.GetBytes($msg))
}

function Put([string]$key, [string]$file, [string]$cache, [string]$type) {
  $body = [IO.File]::ReadAllBytes($file)
  $payload = Sha256Hex $body
  $now = [DateTime]::UtcNow
  $amz = $now.ToString("yyyyMMddTHHmmssZ")
  $day = $now.ToString("yyyyMMdd")
  $uri = "/$Bucket/$key"

  # 서명 대상 헤더는 이름순으로 정렬해야 한다 (SigV4 규칙)
  $canonHeaders = "cache-control:$cache`nhost:$host_`nx-amz-content-sha256:$payload`nx-amz-date:$amz`n"
  $signed = "cache-control;host;x-amz-content-sha256;x-amz-date"
  $canon = "PUT`n$uri`n`n$canonHeaders`n$signed`n$payload"
  $scope = "$day/$region/$service/aws4_request"
  $sts = "AWS4-HMAC-SHA256`n$amz`n$scope`n" + (Sha256Hex ([Text.Encoding]::UTF8.GetBytes($canon)))

  $k = HmacRaw ([Text.Encoding]::UTF8.GetBytes("AWS4$SecretKey")) $day
  $k = HmacRaw $k $region
  $k = HmacRaw $k $service
  $k = HmacRaw $k "aws4_request"
  $sig = Hex (HmacRaw $k $sts)

  $headers = @{
    "Authorization"        = "AWS4-HMAC-SHA256 Credential=$AccessKey/$scope, SignedHeaders=$signed, Signature=$sig"
    "x-amz-date"           = $amz
    "x-amz-content-sha256" = $payload
    "Cache-Control"        = $cache
  }
  if ($WhatIf) { Write-Host ("  (모의) {0}  {1} KB" -f $key, [int]($body.Length / 1KB)); return }
  Invoke-WebRequest -Uri "https://$host_$uri" -Method Put -Headers $headers -Body $body -ContentType $type -UseBasicParsing | Out-Null
}

$files = @(Get-ChildItem (Join-Path $Dist "blobs") -Recurse -File)
Write-Host ("R2 업로드 : {0} · 버킷 {1} · blob {2}개" -f $host_, $Bucket, $files.Count)

$n = 0
foreach ($f in $files) {
  $rel = $f.FullName.Substring($Dist.Length).TrimStart('\').Replace('\', '/')
  Put "$Prefix/$rel" $f.FullName "public, max-age=31536000, immutable" "application/octet-stream"
  $n++
  if ($n % 10 -eq 0) { Write-Host "  … $n / $($files.Count)" }
}

# 목록은 **맨 마지막에** 올린다 — 파일보다 목록이 먼저 올라가면 잠깐 404 가 난다
Put "$Prefix/catalog.json" (Join-Path $Dist "catalog.json") "no-cache" "application/json"
Write-Host ("완료 : blob {0}개 + catalog.json" -f $n) -ForegroundColor Green
Write-Host ("런처 설정 : manifestUrl = <공개주소>/$Prefix/catalog.json")
Write-Host "확인 : .\AI\selftest.ps1 -ManifestUrl <그 주소>"

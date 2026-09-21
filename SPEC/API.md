# 서버 API v2 — 런처·검사기·콘솔이 쓰는 길

> 이 문서가 계약이다. 서버 구현(지금은 파이썬 참조본, 운영은 Spring)을 바꿔도
> **이 문서가 그대로면 현장 PC 는 아무 영향이 없다.**

## 0. 공통

| | |
|---|---|
| 인증 | 헤더 `x-bsp-key: <토큰>` 또는 `?key=<토큰>`. 브라우저는 세션 쿠키 `bsp_sid`(15일) |
| 예외 | `GET /api/health`, `POST /login`, `GET /logout` 만 무인증 |
| 시각 | 로컬 `YYYY-MM-DDTHH:MM:SS` (운영 전환 시 UTC ISO8601) |
| 실패 | `{"error":"…"}` + 적절한 상태코드. 401 키 없음 · 403 권한 없음 · 409 규칙 위반 |
| 신뢰 | 파일은 **SHA-256 으로만** 신뢰한다. 해시는 서버가 발행하고 런처가 배치 직전 재계산 |

## 1. 역할

| 역할 | 뜻 |
|---|---|
| `superOwner` | 대표 — 전권 (승인·삭제·번들·회원·사람·차단·롤백·전체 기록) |
| `developer` | 설계 제도 개발자·개발자 — 올리기·검사 결과 제출·자기 제품 기록·리포트 닫기 |
| `vendor` | 타사 개발자 — 자기 제품만 |
| `user` | 일반 제도사 — 받아 쓰기·리포트 올리기 |

권한 판정은 서버 한 곳(`auth.can`)에서만 한다. 클라이언트 판정은 표시용일 뿐이다.

---

## 2. 카탈로그

### `GET /manifest.json`
런처가 가장 먼저 부른다. `schema: 2` 부터 `bundles` 를 함께 싣는다.

```json
{ "schema":2, "generated":"…",
  "products":[ { "id":"bsp.hts","name":"BSP H.T.S.","publisher":"BSP ENGINEERING",
    "kind":"platform|bridged|tool|launcher","minRevit":"2024","channel":"stable",
    "latest":"2026.09.21-1053",
    "versions":[ {"version":"…","files":[
       {"path":"BSP.Hub/BSP.Hub.dll","size":119808,"sha256":"…",
        "url":"/assets/bsp.hts/2026.09.21-1053/BSP.Hub/BSP.Hub.dll"} ]} ] } ],
  "bundles":[ { "id":"bsp.core","name":"BSP 기본","latest":"1.0.0",
    "versions":[ {"version":"1.0.0",
      "members":[{"id":"bsp.platform","version":"0.8.1"},{"id":"bsp.hts","version":"…"}],
      "pins":[{"assembly":"Newtonsoft.Json","version":"13.0.3"}],
      "sha256":"조합 해시","valid":true,"missing":[]} ] } ] }
```

**불변식** : 같은 `(id, version, path)` 의 내용은 절대 바뀌지 않는다. 고치려면 새 버전을 낸다.
**번들 불변식** : 번들 버전은 구성원 `(id, version)` 집합을 고정한다. 하나라도 바뀌면 새 번들 버전.
검증 단위는 «제품» 이 아니라 **«이 조합»** 이다.

### `GET /assets/<id>/<version>/<path>`
바이너리. 운영에서는 서명된 URL 로 302 해도 되고 런처는 따라간다.
내려갈 때마다 다운로드 집계가 올라간다.

---

## 3. 회원

### `GET /api/member?tenant=<테넌트>`
```json
{ "tenant":"bsp-internal","grade":"customer","expires":"2026-12-31",
  "allow":["bsp.core","bsp.platform"],
  "allowResolved":["bsp.platform","bsp.hts"],
  "allowBundles":["bsp.core"],
  "pin":[{"id":"bsp.platform","version":"0.8.1"}] }
```

- `allow` 에는 **제품 id 와 번들 id 를 섞어** 넣을 수 있다. `"*"` 는 전부
- 서버가 번들을 풀어 `allowResolved` 를 함께 준다 — **런처는 이것만 보면 된다**
- 404 면 런처는 **아무것도 설치하지 않는다**(fail-closed). 연결 실패면 마지막 상태로 유예

---

## 4. 심사

| 길 | 누가 | 뜻 |
|---|---|---|
| `POST /api/verdict` | 기계 (정적 검사기·실기 러너) | 검사 결과 등록. `fail` 있으면 승인 잠김 |
| `POST /api/review` | 사람 (`superOwner`) | `status=approved\|rejected\|pending` |
| `GET /api/reviews` | 조회 | 제품@버전별 상태와 검사 항목 |

서식은 `CALLBACKS.md` 4장 참조.

---

## 5. 기록·리포트

| 길 | 본문 | 비고 |
|---|---|---|
| `POST /api/usage` | JSONL | 런처가 오프셋 이후만 보낸다. 깨진 줄은 서버가 버린다 |
| `GET /api/stats` | — | 다운로드 집계 |
| `POST /api/report` | JSON | 첨부 없음 |
| `GET /api/reports` | — | 목록·열림 수 |
| `POST /api/report/close` | 폼 | `developer` 이상 |

---

## 6. 사람·세션

| 길 | 뜻 |
|---|---|
| `POST /login` | 폼 `token=…` → 세션 쿠키 15일 (HttpOnly·SameSite=Lax) |
| `GET /logout` | 그 세션만 폐기 |
| `GET /api/whoami` | 이름·역할·권한 목록 |
| `GET /api/users` · `POST /api/user` | 사람 목록·발급 (`superOwner` 만). **토큰은 발급 응답에서 한 번만** |

세션은 서버가 들고 있다 → **역할 변경·차단이 즉시 반영**된다.
남은 기간이 7일 미만이면 접속할 때 15일로 자동 연장된다.

---

## 7. 관리

| 길 | 뜻 |
|---|---|
| `POST /upload` | multipart — `id name version kind minRevit publisher` + `files[]`. 같은 버전 재업로드는 통째 교체 |
| `POST /delete` | `id version` (`superOwner`) |
| `GET /` | 콘솔 |
| `GET /api/health` | 살아 있나 + 모듈 목록 |

---

## 8. 저장소 (구현 메모)

모듈은 파일을 직접 열지 않고 저장소 계층 하나를 지난다.
`BSP_DB_URL` 이 있으면 **포스트그레**, 없으면 파일.

```
kv(coll, id, body jsonb)        문서   — members · reviews · users · sessions
log(coll, at, body jsonb)       기록   — usage · reports   (파티셔닝 대상)
counter(coll, key, n)           집계   — 다운로드
```

자산(파일) 자체는 오브젝트 스토리지로 분리하는 것이 1순위다.

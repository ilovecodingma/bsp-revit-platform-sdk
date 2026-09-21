# 콜백 규격 v1 — 누가 남기고, 누가 걷고, 누가 받는가

> 세 주체가 **파일과 HTTP 두 가지로만** 이야기한다. 그 외의 통로는 없다.
>
> ```
> [리빗 안 플러그인] ──파일──▶ [백그라운드 런처] ──HTTP──▶ [서버]
>        ▲                          │
>        └────── 파일(구성·상태) ─────┘
> ```
>
> **리빗 프로세스는 서버와 직접 통신하지 않는다.** 보안 심사에 유리하고, 회선이 죽어도
> 도면 작업이 안 멈추며, 리빗을 느리게 만들지 않는다.

모든 경로의 기준은 `%AppData%\BSP\Platform\` (아래 `$STATE`).

---

## 1. 플러그인이 **남기는** 것

### 1-1. 실행 기록 — `$STATE\runlog.jsonl`

한 줄에 JSON 하나 (JSONL). **BOM 없는 UTF-8**, 줄 끝 `\r\n` 또는 `\n`.
기록 실패가 업무를 막으면 안 된다 — 전부 try/catch 로 감싸고 조용히 넘어간다.

```json
{"t":"2026-09-21T16:33:49","product":"bsp.hts","tool":"Export CAD","outcome":"succeeded",
 "ms":1197,"doc":"synth_fab_host","view":"3D","sel":2,"host":"PC-01","user":"k"}
```

| 필드 | 필수 | 뜻 |
|---|---|---|
| `t` | ● | 로컬 시각 `YYYY-MM-DDTHH:MM:SS` (운영 전환 시 UTC) |
| `product` | ● | 제품 id |
| `tool` | ● | 도구 이름. 플랫폼 자체 동작은 `기동`·`mcp.start` 처럼 점 표기 |
| `outcome` | ● | `ok` \| `succeeded` \| `failed` \| `cancelled` \| `rejected` |
| `ms` | ● | 소요 시간 |
| `doc` `view` `sel` | | 문서명·뷰명·선택 수. **도면 내용은 절대 넣지 않는다** |
| `host` `user` | ● | PC 이름·윈도우 사용자 |
| `note` | | 실패 사유 한 줄 |

### 1-2. 실행 중 마크 — `$STATE\.running`

도구를 실행하기 **직전에 쓰고**, 끝나면 **반드시 지운다**(`finally`).

```
<도구 이름>|<시작 시각 ISO>
```

이 파일이 남아 있는 채로 리빗이 사라지면 **그 도구가 죽인 것**이다.
런처가 그것을 보고 `crash.attributed` 를 남긴다. **«누가 죽였나» 에 답하는 유일한 근거다.**

### 1-3. 실행 깔때기 (권장 구현)

```
잠금 확인 → .running 쓰기 → 시계 시작 → 실행
   finally : 트랜잭션·수집기 반납 · 잠금 해제 · .running 삭제 · 기록 한 줄
```
동시 실행은 1건으로 막는다. 두 도구가 같은 모델을 동시에 고치면 트랜잭션이 충돌한다.

---

## 2. 런처가 **주는** 것 (플러그인이 읽는다)

### 2-1. 구성·상태 — `$STATE\state.json`

```json
{ "updated":"2026-09-21T16:20:00",
  "server":{"ok":true,"url":"http://update.example.com"},
  "member":{"ok":true,"tenant":"bsp-internal","grade":"poc","expires":"-"},
  "installed":{ "bsp.hts":{"id":"bsp.hts","name":"BSP H.T.S.","version":"2026.09.21-1053",
                           "kind":"platform","status":"설치됨","files":15,"placed":[...]} },
  "disabled":["bsp.sample"],
  "pending":["bsp.platform / BSP.Platform.dll (리빗이 잡고 있음)"],
  "watch":{"dir":"...\\Addins\\2024","addins":[...],"unapproved":[]},
  "alerts":["bsp.platform 0.8.1 → 0.9.0 : 옛 파일 1개 지움"] }
```

플러그인은 이 파일만 읽으면 된다. **서버 주소도 여기서 받는다** — 플러그인에 주소를 박지 않는다.

### 2-2. 메모리 스냅샷 — `$STATE\memory.json` (덮어쓰기)

```json
{"t":"...","pid":25924,"minutes":23,"ws":1225,"priv":1168,"peak":1225,
 "thread":153,"handle":5181,"modules":520,"baseModules":520,"grown":0,
 "level":"ok","responding":true,"running":"","hangSeconds":0}
```

`level` 은 `ok|warn|high`. **매 틱 덮어쓴다** — 기록을 쌓지 않는다.
기록(`runlog`)에는 **변했을 때만** 남긴다: 단계 변화 / 500MB 눈금 / 모듈 25개 눈금 / 세션 종료.

### 2-3. 도구 배치 위치

| 제품 `kind` | 배치 |
|---|---|
| `platform` | `%AppData%\Autodesk\Revit\Addins\<연도>\` (자기 `.addin` 포함) |
| `bridged` | 같은 곳에 **파일만**. `.addin` 은 깔지 않는다 → 로드 시점을 플랫폼이 쥔다 |
| `tool` | `$STATE\Tools\<제품id>\` |

---

### 2-4. 요청 통로 — `$STATE\cmd\` (리빗 안 «받기» 버튼)

리빗 안 화면이 파일 하나를 넣으면 런처가 **2초 안에** 집어 처리하고 답을 옆에 놓는다.

```
요청  cmd\<티켓>.json        {"op":"install","id":"bsp.hts"}       op : install | sync | enable | disable
답    cmd\<티켓>.done.json   {"ok":true,"status":"설치됨","msg":"BSP H.T.S. 2026.09.21-1053"}
```

- 처리 후 요청 파일은 런처가 지운다. 답 파일은 읽은 쪽이 지운다
- `status` 에 «다음 기동에 적용» 이 들어오면 **리빗을 껐다 켜야 반영된다**는 뜻이다.
  화면은 «설치됨» 과 이 경우를 구분해서 말해야 한다
- 실측 왕복 1.3초 (받기 + SHA-256 검증 + 배치 포함)

## 3. 런처가 **서버로** 보내는 것

| 길 | 언제 | 본문 |
|---|---|---|
| `GET /manifest.json` | 리빗 켜질 때 | — |
| `GET /api/member?tenant=` | 같은 때 | — |
| `GET /assets/<id>/<ver>/<path>` | 받을 것이 있을 때 | — (받은 뒤 **해시 재계산** 후 배치) |
| `POST /api/usage` | 리빗 꺼질 때 | `runlog` 의 **보낸 지점 이후**만 JSONL 로 |
| `POST /api/report` | 사고·요청 | 아래 서식 |

헤더 `x-bsp-key: <토큰>` (또는 `?key=`). 실패해도 재시도는 다음 기회에 — 업무를 막지 않는다.

---

## 4. 검사기가 서버로 보내는 것 — `POST /api/verdict`

정적 검사기와 실기 러너가 **같은 길**로 넣는다. 사람의 승인과는 분리된다.

```json
{ "id":"bsp.hts", "version":"2026.09.21-1053", "revit":"2024", "by":"static",
  "checks":[
    {"name":"참조 API 일치","level":"fail","detail":"선언 2024(major 24) 인데 21.x"},
    {"name":"코드 서명","level":"fail","detail":"서명 9 · 미서명 5"},
    {"name":"동봉 금지","level":"fail","detail":"BSP.Contracts 동봉됨"}
  ] }
```

- `level` : `pass` \| `warn` \| `fail`
- 같은 `(name, revit)` 은 **덮어쓴다** (재검사)
- `fail` 이 하나라도 있으면 **승인 버튼이 잠긴다.** 이미 승인된 것도 `pending` 으로 되돌아간다

### 실기 러너가 넣어야 할 최소 5개

| 이름 | 무엇 |
|---|---|
| 로드 여부 | 리빗이 실제로 올렸나 (저널 `Starting External Application`) |
| 기동 ms | 그 애드온이 기동에 더한 시간 (예산 200ms) |
| 정적 초기화 | **모든 타입 cctor 강제 실행** — 누르면 죽을 코드를 미리 찾는다 |
| 리본 생성 | 버튼 수 · **자기 탭을 만들었는가** |
| 자원 증가 | 메모리·스레드·핸들·모듈 |

> cctor 강제 실행은 파일·네트워크를 건드릴 수 있다. **격리 머신에서만**,
> 명시 플래그 + 화이트리스트로 돌린다. 사용자 PC 기본 실행 금지.

---

## 5. 버그 리포트 — `POST /api/report`

```json
{"product":"bsp.hts","version":"...","revit":"2024","host":"PC-01","user":"k",
 "kind":"bug|crash|request","title":"한 줄","text":"…(2000자까지)"}
```

**첨부는 받지 않는다.** 도면이 섞여 들어오는 것을 구조로 막는다.
긴 로그는 로컬에 두고 여기엔 요약만 올린다.

---

## 6. 실패했을 때의 규칙

| 상황 | 해야 할 일 |
|---|---|
| 서버가 안 보인다 | 마지막 상태로 **계속 동작**. 유예 기간 안이면 아무 일도 없던 듯 |
| 해시가 다르다 | **배치 거부**. 기록에 남기고 다음 동기화에서 다시 시도 |
| 파일이 잠겨 있다 | 큐에 넣고 **다음 리빗 종료 때** 적용 |
| 기록 전송 실패 | 오프셋을 올리지 않는다. 다음에 다시 보낸다 |
| 도구가 죽었다 | 예외를 깔때기가 잡아 사용자에게 «무엇이/어디서» 를 보여 주고 기록 |

# BSP 플랫폼 SDK v0.1 (제안본)

> 리빗 애드온을 **BSP 플랫폼 위에서** 만들고, 검사하고, 배포하고, **관리**하기 위한 묶음.
> 이 SDK 는 «개발 환경» 이 아니다. 개발은 평소 쓰던 Visual Studio + NuGet 으로 한다.
> 여기 있는 것은 **계약 · 검사 · 배포 · 콜백 · 프로세스** 규격 다섯이다.

**우리는 «가장 아래 한 겹» 만 만든다.** 그 위(서버·화면·심사·업무 도구)는 그쪽이 만들고,
우리는 그것을 **혼자 검증할 수 있는 하네스**를 같이 드린다 → `AI\HARNESS.md`

**서버는 이미 있는 남의 것이라고 전제한다.** 런처가 서버에게 바라는 것은 둘뿐이다 —
**목록 한 장(JSON) 과 그 목록이 가리키는 파일.** 주소 체계·인증·언어·호스팅은 전부 그쪽 자유다.
서버를 고칠 수 없으면 목록을 만들어 같이 올리거나(`AI\make-catalog.ps1`) 변환기를 하나 두면 된다
→ `SPEC\ADAPTER.md`. **런처는 한 줄도 고치지 않는다.**

## 무엇이 들어 있나

```
BSP_SDK\
  README.md                 이 문서
  PROPOSAL.md               한 장짜리 제안 — 무엇을 드리고 무엇을 맡기는가

  CLAUDE.md                 AI 에게 주는 오리엔테이션 (이 폴더에서 열면 자동으로 읽힌다)
  AI\HARNESS.md             ★ 경계 — 우리 최소 코어 / 하네스 / 그쪽 몫
  AI\MIGRATE.md             전환 매뉴얼 — 지금 구조 → 런처 형식, 6단계·단계마다 확인
  AI\TEST.md                시험 매뉴얼 — 무엇을 어떻게 확인하고 어떻게 적는가
  AI\ADAPT_HTS.md           지시서 — 기존 애드온(HTS)을 플랫폼에 태운다
  AI\SERVER.md              지시서 — 서버를 만든다 (끝에 합격 시험)
  AI\selftest.ps1           배포 사슬 자동 시험 (현재 5/5 PASS)
  AI\healthcheck.ps1        이 PC 지금 상태 한 장
  AI\snapshot.ps1           보관 · 되돌리기 (전환 전에 한 번)
  AI\make-catalog.ps1       «파일만 있는 서버» 를 배포 서버로 만드는 목록 생성기

  SPEC\LAUNCHER.md          ★ 런처 최소기능 공통설계 (여기부터 읽는다)
  SPEC\ADAPTER.md           ★ 남의 서버를 런처 뒤에 붙이는 세 가지 길
  SPEC\CONTRACT.md          도구 계약   — 무엇을 구현하고 무엇을 하면 안 되는가
  SPEC\PROCESS.md           프로세스 구조 — 애드온은 점화만, 관리는 별도 프로세스
  SPEC\CALLBACKS.md         콜백 규격   — 남기는 것 · 걷는 것 · 받는 것
  SPEC\API.md               서버 API    — 런처·검사기·콘솔이 쓰는 길

  bin\bsp-launcher.exe      백그라운드 매니저 (net48 단일 exe · 런타임 설치 불필요)
  bin\bsp-verify.exe        정적 적합성 검사기
  bin\BSP.Platform.Entry.dll  리빗 엔트리포인트 (매니저를 띄우는 점화 플러그)
  bin\BSP.Platform.Entry.addin
  bin\BSP.Contracts.dll     계약 어셈블리 (참조용 — 결과물에 **동봉 금지**)
  bin\publish.ps1           올리기 한 줄

  src\Entry\                엔트리포인트 전체 소스 + build.ps1 (읽고 고치라고 넣었다)
                            Requests.cs = 리빗 안 «받기» 버튼이 부르는 쪽
  templates\                config.json · product.json · bundle.json
  samples\HelloTool\        최소 도구 한 개 (소스 + build.ps1)
```

## 붙여넣을 한 줄 (이것만 하면 된다)

AI(클로드 코드 등)에 **아래를 그대로 붙여 넣고 엔터.** 나머지는 AI 가 물어보면서 진행한다.

```
https://github.com/ilovecodingma/bsp-revit-platform-sdk 를 내려받아서
AI\SETUP.md 를 읽고 그대로 진행해줘. 내 환경에 맞춰 하나씩 물어보고,
각 단계마다 확인 명령을 돌려서 결과를 보여줘.
```

내려받기만 따로 하려면 :

```powershell
git clone https://github.com/ilovecodingma/bsp-revit-platform-sdk
# 또는 : https://github.com/ilovecodingma/bsp-revit-platform-sdk/archive/refs/heads/main.zip
```

## 대표님께 — 어디부터 보면 되나

1. `AI\HARNESS.md` — 경계 한 장. 우리가 만드는 것과 그쪽이 만드는 것
2. 붙기만 하는지 30초 확인 : `binsp-probe.exe cycle`  (리빗도 서버도 필요 없다)
3. `PROPOSAL.md` — 무엇을 드리고 무엇을 맡기는지
4. `AI\MIGRATE.md` — **지금 구조를 런처 형식으로 바꾸는 6단계.**
   각 단계의 «붙여넣을 문장» 을 AI 에 그대로 넣고 엔터, 끝날 때마다 «확인» 을 돌린다
5. `AI\TEST.md` — 확인·시험 매뉴얼. 결과를 그대로 적어 남긴다

## 30초 요약

1. **만든다** — `BSP.Contracts` 만 참조해 `IBspTool` 을 구현한다 (`samples\HelloTool`)
2. **검사한다** — `bsp-verify.exe <폴더> --id <제품> --version <버전> --target 2024`
3. **올린다** — `publish.ps1` 한 줄. 검사 FAIL 이면 거기서 멈춘다
4. **퍼진다** — 각 PC 의 `bsp-launcher.exe` 가
   **리빗 켜질 때 받아두고, 꺼질 때 적용**한다. 사용자는 아무것도 하지 않는다

## 리빗 «안에서» 받는다, 바꾸는 것은 밖에서

리빗 안 화면에서 목록을 보고 누르면 그 자리에서 받아 설치된다 (실측 왕복 1.3초).
다만 **이미 올라가 있는 DLL 은 리빗 자신도 못 바꾸므로**, 그것만 리빗을 껐다 켤 때 갈린다.
화면은 그 둘을 구분해 말한다 — «설치됨» / «다음 기동에 적용».

## 관리는 리빗 밖에서 한다

애드온(`BSP.Platform.Entry.dll`)이 하는 일은 셋뿐이다 — 세션 표시 · 점화 · 상태 버튼.
업데이트·기록·메모리 감시·사고 지목은 전부 **별도 프로세스**(`bsp-launcher.exe`)가 한다.

```
Revit.exe ─점화─▶ bsp-launcher.exe ─HTTP─▶ 서버
   │                   ▲
   └── 파일 %AppData%\BSP\Platform ──┘
```

리빗이 죽어도, 리빗이 아예 없어도 매니저는 산다. 그래야 «리빗을 껐다 켜면 최신» 이 성립한다.
띄우는 방법(작업 개체 탈출·핸들 차단·중복 방지)과 실측 결과는 `SPEC\PROCESS.md` 에 있다.

## 지켜야 할 것 세 줄

- 자기 `.addin` 을 만들지 않는다. 탭도 만들지 않는다 (플랫폼이 만든다)
- 상태는 플랫폼이 준 폴더에만 쓴다. 남의 제품 파일은 절대 건드리지 않는다
- 선언한 Revit 연도와 **실제 참조한 RevitAPI 버전이 같아야** 한다 —
  다르면 검사에서 FAIL 이고, 그대로 나가면 사용자 PC 에서 조용히 죽는다
  (실제 사고 : `BuiltInCategory` 가 2024 에서 32→64비트로 바뀌어, 2021 로 빌드한 도구가
   버튼을 누르는 순간 `TypeInitializationException` 으로 사망)

## 개발 환경 (우리가 주지 않는 것)

| 필요한 것 | 어디서 |
|---|---|
| 연도별 RevitAPI 참조 | NuGet `Nice3point.Revit.Api.RevitAPI` (연도별 패키지, 2027까지) |
| 개발 편의(async·DI) | NuGet `Nice3point.Revit.Toolkit` |
| 빌드 | Visual Studio / `dotnet build` / 동봉한 `build.ps1` (csc 직접 호출) |
| 파이썬 도구 | pyRevit 그대로 |

리빗을 설치하지 않아도 NuGet 참조만으로 빌드된다. 연도를 바꾸려면 패키지 버전만 바꾼다.

## 런타임 계열 (반드시 인지)

| Revit | 런타임 | 비고 |
|---|---|---|
| ~2024 | .NET Framework 4.8 | 같은 DLL 이 2025 에서 안 돈다 |
| 2025~ | .NET 8 | 별도 빌드 필요 |

## 버전 정책

- 지원 : `N`, `N−1`, `N−2` 세 개
- 새 연도가 나오면 **6개월 안에 `targetRevit` 을 올려야** 카탈로그에 남는다
- 올리지 않으면 신규 배포가 막히고, 이미 깔린 것은 그대로 둔다

## 아직 없는 것 (숨기지 않는다)

| 빠진 것 | 무슨 뜻인가 |
|---|---|
| 코드 서명 인증서 | 지금은 **우리 것도 검사에서 FAIL** 이다. 무인 배포의 전제이므로 먼저 결정해야 한다 |
| 실기 러너 자동화 | 정적 검사는 돈다. 연도별 리빗에서 실제로 띄워 보는 단계는 수동이다 |
| AI·MCP 연계 | 이번 범위 밖. 규격이 파일·HTTP 두 갈래뿐이라 나중에 붙여도 구조는 안 바뀐다 |

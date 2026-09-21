# 도구 계약 v1 — 무엇을 구현하고, 무엇을 하면 안 되는가

> 이 한 장이 «BSP 플랫폼 호환» 의 정의다. 여기 적힌 문장은 전부 **기계가 판정할 수 있게** 썼다.
> `bsp-verify.exe` 와 실기 러너가 이 문장들을 검사한다. 통과해야 카탈로그에 남는다.

## 1. 구현할 것

도구는 `BSP.Contracts` **하나만** 참조한다. 플랫폼(허브)을 참조하지 않는다.

```csharp
public interface IBspTool
{
    string Product { get; }      // 제품 이름 — 도구상자 묶음 단위
    string Group   { get; }      // 제품 안 소분류. 앞 숫자는 정렬용(화면에 안 보임)
    string Name    { get; }      // 버튼 글자. \n 으로 두 줄까지
    string Tip     { get; }      // 한 줄 설명
    string Help    { get; }      // 길게 (없으면 null)
    bool   Pinned  { get; }      // 첫 설치 때 즐겨찾기 기본값
    ImageSource Icon(int px);    // 16 / 32 / 34 로 불린다
    Result Run(UIApplication app);
}
```

선택 계약

| 인터페이스 | 언제 |
|---|---|
| `IBspGuide` | 안내를 붙인다 — `Guide Guide { get; }` 하나. `Purpose · When · Needs · Steps(IList<string>) · Result · Notes(IList<string>)` 를 채운다. 툴팁·F1·설명서가 여기서 나온다 |
| `IBspPanes` | 도킹 패널이 필요할 때 — `RegisterPanes(UIControlledApplication)` + `Panes`. **등록은 기동 시점에만** 가능하므로 플랫폼이 부른다 |

### 좋은 도구의 기준 한 줄

> 도구 코드에 `Transaction` · `ExternalEvent` · `try/catch` · 파일 경로가
> **한 번도 안 나오면 성공이다.** 그것들은 플랫폼이 준다.

---

## 2. 선언할 것 — 매니페스트

```json
{ "id":"bsp.hts.flowmaker", "name":"Flow Maker", "publisher":"BSP ENGINEERING",
  "version":"1.0.0", "kind":"tool",
  "minRevit":"2024", "targetRevit":"2024",
  "needsModel":true,
  "permissions":["state.write"],
  "channel":"stable" }
```

| 필드 | 규칙 |
|---|---|
| `id` | **ASCII 소문자 + 점.** 한글·공백 금지 (URL·경로·로그에 다 실린다) |
| `targetRevit` | **실제 참조한 RevitAPI 버전과 같아야 한다.** 다르면 FAIL |
| `minRevit` | 이보다 낮은 리빗에는 배포하지 않는다 |
| `needsModel` | 모델을 만지는가. `false` 인 도구만 별도 AppDomain 후보가 된다 |
| `permissions` | `state.write` · `network` · `link.read` · `events.global` 중 필요한 것만 |

> `needsModel` 이 필요한 이유 : Revit API 객체는 **AppDomain 경계를 못 넘는다**
> (`ElementId` 조차 `SerializationException`). 모델을 만지는 도구는 기본 도메인에 있어야 하고,
> 죽으면 리빗도 같이 죽는다. 안 만지는 도구만 격리할 수 있다.

---

## 3. 하면 안 되는 것

| 금지 | 왜 | 검사 |
|---|---|---|
| 자기 `.addin` 을 Addins 폴더에 넣기 | 탭 난립·중복 로드 | 런처 폴더 감시 |
| 자기 리본 탭 만들기 | «탭 하나» 원칙이 무너진다 | 실기 러너가 탭 목록 비교 |
| `DockablePane` 직접 등록 | 등록 시점을 플랫폼이 쥐어야 한다 | 계약(`IBspPanes`) |
| `BSP.Contracts` · `RevitAPI*` · `AdWindows` **동봉** | 계약이 둘로 갈린다 | 정적 검사 |
| 전역 이벤트 상시 구독(`DocumentChanged` 등) | 모든 작업이 느려지고 범인을 못 찾는다 | 정적/실기 |
| 프로세스 종료·Dispatcher 조작·워커 스레드에서 API 호출 | 리빗이 죽는다 | 정적(부분) |
| 상태를 플랫폼이 준 폴더 **밖에** 쓰기 | 업데이트 때 사라지거나 지워지지 않는다 | 실기 |
| 도구마다 `try/catch` 로 예외 삼키기 | 사고가 기록되지 않는다 | 리뷰 |

> 기술로 못 막는 것도 있다 — 무한 루프·메모리 폭식·네이티브 크래시.
> 그건 **막는 척하지 않고 기록해서 범인을 댄다.** 3회 연속 크래시면 자동 격리한다.

---

## 4. 검사 (통과해야 게시된다)

### 정적 — `bsp-verify.exe` (코드 실행 없음)

| 항목 | 기준 |
|---|---|
| 참조 API 일치 | 모든 `RevitAPI*` 참조 major == `targetRevit − 2000` |
| 런타임 계열 | `≤2024 → net48` / `2025~ → net8` |
| 코드 서명 | 모든 DLL 서명. 발급자가 허용 목록에 있을 것 |
| 동봉 금지 | 위 표의 어셈블리가 없을 것 |
| 내부 버전 충돌 | 패키지 안에 같은 이름 다른 버전이 없을 것 |

### 실기 — 격리 리빗에서 연도별

로드 여부 · 기동 ms(예산 200ms) · **모든 타입 cctor 강제 실행** ·
리본 생성 결과 · 메모리/스레드/핸들/모듈 증가.

판정은 제품 × 연도 매트릭스로 남고, **런처는 자기 연도에서 PASS·승인된 것만 내려받는다.**

---

## 5. 자주 나는 사고 두 가지 (실측)

**① 연도만 라벨로 바꾼 경우**
About 에는 «Revit 2024 Only» 인데 참조는 21.0.0.0 이었다.
`BuiltInCategory` 가 2024 에서 32→64비트로 바뀌어, 그 배열을 쓰는 정적 초기화가
`RuntimeHelpers.InitializeArray` 에서 터진다. 탭·버튼은 멀쩡히 뜨고 **누르는 순간 죽는다.**

**② 서명이 없는 경우**
리빗이 «보안 — 서명 없는 애드인» 대화상자를 띄우고 **답할 때까지 멈춘다.**
실측 1시간 45분. 무인·전사 배포가 성립하지 않는다.

---

> 리빗 밖에서 도는 매니저와의 관계는 `PROCESS.md` 를 본다. 도구는 그 존재를 몰라도 된다.

## 6. 배포

```powershell
bsp-verify.exe <출력폴더> --id <제품id> --version <버전> --target 2024
publish.ps1 -Path <출력폴더> -Id <제품id> -Version <버전> -Target 2024 -Kind tool
```

올린 뒤에는 각 PC 의 런처가 **리빗 켜질 때 받아두고, 꺼질 때 적용**한다.
사용자는 아무것도 하지 않는다. 이미 올라가 있는 DLL 은 교체되지 않으므로
**지연 로드된(아직 안 누른) 도구만 리빗을 켠 채로 갈아끼울 수 있다.**

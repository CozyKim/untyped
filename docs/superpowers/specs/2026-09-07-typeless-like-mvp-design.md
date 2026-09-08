# typeless-like MVP 설계

작성일: 2026-09-07

## 1. 목적

말한 내용을 온디바이스로 전사하고, 온디바이스 LLM으로 다듬어, 현재 커서 위치에
삽입하는 macOS 메뉴바 앱. 네트워크를 타지 않는다.

MVP의 완성 기준은 **핵심 루프 하나**다.

> 핫키를 누른다 → 말하는 동안 화면에 상태와 목소리 레벨이 보인다 → 필러와
> 말 더듬음이 제거되고 스스로 고친 말은 최종 의도만 남은 텍스트가, 지금 포커스된
> 앱의 커서 위치에 들어간다.

이 루프가 손에 익을 만큼 동작하면 MVP는 끝이다. 여기서 얻은 체감으로 다음 범위를
정한다.

## 2. 비목표

의도적으로 제외한다. 필요해지면 그때 넣는다.

- 설정 창 (핫키 변경, 다듬기 강도, 톤 선택)
- 받아쓰기 기록/히스토리
- 오버레이의 실시간 전사 텍스트 (상태와 오디오 레벨은 9절에서 다룬다)
- 앱별 문체 적응
- 한국어 외 언어 전환 UI
- 배포용 패키징 (공증, 자동 업데이트, 샌드박스)

## 3. 검증된 전제

추측이 아니라 이 머신에서 실행해 확인한 사실이다.

### 환경

| 항목 | 확인값 |
| --- | --- |
| macOS | 26.5.2 (Tahoe), arm64 |
| Xcode / Swift | 26.6 / 6.3.3 |
| SpeechTranscriber 한국어 | `ko-KR` 지원, 모델 설치 완료 |
| 전사 목표 오디오 포맷 | 16 kHz, 1 ch, Int16 |
| SwiftPM 빌드 | `platforms: [.macOS(.v26)]` + Swift Testing으로 빌드·테스트 통과 |
| oMLX | `127.0.0.1:8081`, `gemma-4-e2b-it-8bit` 서빙 |

### 다듬기 백엔드 선정 근거

한국어 구어체 샘플로 네 후보를 측정했다. 채점은 필러 제거·자기 수정 반영·내용
보존을 항목화해 자동으로 매겼다.

| 후보 | 지연 | 결과 |
| --- | --- | --- |
| Apple Foundation Models 3B | 6.8~11초 | **기각.** 구체적 지시문을 주면 가드레일이 무해한 업무 문장을 3/3 차단(`guardrailViolation: May contain unsafe content`). 영어 지시문은 차단을 피하는 대신 한국어를 영어로 번역해버린다 |
| Ollama `qwen3.5:9b` | 20초 | **기각.** `keep_alive`로 로드를 0.34초까지 줄여도 호출당 20초. 지시를 무시하고 설명을 늘어놓는다 |
| gemma4 e2b 오디오 직결 | 1.4~4.1초 | **기각.** 짧은 발화는 완벽하지만 20초를 넘기면 필러도 자기 수정도 처리하지 못하고 전사 수준으로 퇴화한다 |
| **Apple 전사 → gemma4 텍스트 다듬기** | **2.0~5.4초** | **채택.** 긴 샘플 두 건 모두 만점 |

### 채택안의 실측치

구조가 다른 긴 샘플 5건으로 검증했다. 채점은 제거돼야 할 표현과 보존돼야 할
표현을 항목화해 자동으로 매겼다.

| 샘플 | 길이 | 특징 | 점수 | 다듬기 지연 |
| --- | --- | --- | --- | --- |
| long | 30.6초 | 5문장, 끝에 정정 1회 | 9/9 | 5.42초 |
| long2 | 21.3초 | 4문장, 중간에 정정 1회 | 9/9 | 1.99초 |
| l3 | 17.2초 | **정정 2회** | 7/7 | **7.60초** |
| l4 | 17.4초 | 앞쪽에 정정 1회 | 6/6 | 1.82초 |
| l5 | 18.1초 | 정정 없음, 필러 다수 | 6/7 | 2.17초 |

짧은 발화(5초 내외)는 0.8~1.0초다.

l5의 유일한 실패는 전사기가 `세 지표`를 `새 지표`로 옮긴 것으로, 다듬기 단계의
문제가 아니다.

**지연은 발화 길이에 비례하지 않는다.** 17.2초 샘플이 30.6초 샘플보다 오래
걸렸다. 정정 횟수와 출력 길이가 지배한다. 타임아웃 공식은 이 편차를 견뎌야
한다(10절).

전사는 `SpeechAnalyzer`가 말하는 동안 스트리밍으로 처리하므로 말이 끝난 시점에는
이미 끝나 있다. 위 지연이 체감 지연의 전부다.

부수 효과로 확인된 것: gemma4가 전사기의 외래어 오인식 일부를 문맥으로 교정한다
(`리펙터링`→`리팩터링`, `데시보드`→`대시보드`). `AnalysisContext.contextualStrings`로
어휘 힌트를 주는 방법은 6개 샘플 전부 결과가 바뀌지 않아 효과를 확인하지 못했다.

### 한영 코드 스위칭

한국어 개발 대화는 영어 용어를 섞어 쓴다. 그리고 한국인 화자는 그 영어를 한국어
발음으로 말한다. `ko-KR` 전사기는 그것을 한글로 음차하거나 아예 다른 말로
잘못 옮긴다.

```
approve  → 어플로그      뜻이 깨짐
debug    → 비버그        뜻이 깨짐
staging  → 스테이징      음차, 뜻은 통함
```

다듬기 단계에서 영문 표기를 복원할 수 있는지 세 가지로 측정했다. 채점은 원래
영어 용어가 결과에 영문으로 복원됐는지로 매겼다.

| 방식 | 점수 | 문제 |
| --- | --- | --- |
| 전사 그대로 (복원 규칙 없음) | 1/15 | 음차가 그대로 남는다 |
| "영문으로 되돌려라" 규칙만 | 7/15 | **환각.** `어플로그`를 `apply`로 지어낸다 |
| **용어 사전 + 사전 밖 금지** | **15/18** | 채택 |

결정적인 것은 사전 자체가 아니라 **"사전에 없는 말은 절대 영어로 바꾸지 말라"**는
제약이다. 이것이 없으면 모델이 뭉개진 발음을 추측해 틀린 단어를 만든다. 음차보다
나쁘다.

일상 한국어가 불필요하게 영문화되지 않는 것도 확인했다(`사용자`, `이탈률`, `회식`,
`목요일` 4/4 보존).

남은 실패: 사전에 있는 용어를 복원하는 대신 통째로 지워버리는 경우가 관찰됐다
(`제플로이는` 소실). 규칙 5(보존)와 충돌하는 동작이다.

### 육성 검증

실제 육성으로 두 건을 받아 회귀 테스트에 고정했다. TTS 음성으로는 드러나지 않던
실패가 세 가지 나왔다.

| 발견 | 대응 |
| --- | --- |
| 고유명사가 전사에서 깨지고(`langchain`→링체인, `typeless`→타이블리스) 다듬기가 오히려 악화시킨다(→테이블리스) | 사전에 고유명사를 넣는다 |
| 실제 정정은 `아 아니다 그게 아니라`처럼 표시어가 겹치고 주제가 통째로 바뀐다 | 표시어 목록 확장, few-shot 6·7번 추가 |
| 음절을 더듬어 반복한다(`다 다이얼 다 다이어글램`, `코드로 코드`) | 규칙 2에 통합, few-shot 8번 추가 |

사전에 없는 용어도 모델의 일반 지식으로 복원되는 경우가 있었다(`오케이스트레이터`
→`orchestrator`, `서브이전트`→`subagent`). 사전은 보장이지 유일한 경로는 아니다.

### 최종 성능

전체 회귀 스위트 기준이다.

| 스위트 | 점수 |
| --- | --- |
| 긴 발화 5건 (17~30초) | 33/35 |
| 한영 코드 스위칭 4건 | 13/14 |
| 육성 2건 | 18/19 |
| **총계** | **64/68 (94%)** |

남은 실패 4건 중 **3건이 같은 유형**이다. 정정 표시어 앞의 서술을 버리지 못하고
남긴다. 프롬프트를 다섯 가지로 바꿔 봤지만 3B 모델에서 완전히 해결되지 않았다.
실사용 데이터가 쌓이면 few-shot을 보강한다.

### oMLX 프롬프트 캐시 결함과 우회

oMLX는 프롬프트 캐시 키를 **텍스트 프리픽스로만 계산하고 오디오를 무시한다.**
같은 시스템 프롬프트로 서로 다른 오디오를 보내면 먼저 보낸 오디오의 전사가 그대로
돌아온다. 받아쓰기 앱에서는 말한 것과 다른 문장이 삽입되는 최악의 실패다.

시스템 프롬프트 끝에 매 요청 고유한 nonce를 붙이면 사라진다. 우회책이 아니라
**필수 요구사항**으로 취급한다(6절). 캐시를 포기해도 오히려 빨랐으므로 잃는 것은
없다.

이 결함은 오디오를 보낼 때 관찰했다. 채택안은 텍스트만 보내므로 직접 노출되지
않지만, 같은 캐시 로직이 텍스트 프리픽스에도 적용되는 이상 few-shot 프리픽스가
고정된 우리 요청은 동일한 위험을 갖는다. 그래서 텍스트 경로에도 nonce를 붙인다.

### 아직 검증하지 못한 가설

구현 순서를 정하는 근거다. 사실로 취급하지 않는다.

1. 클립보드 백업 + `⌘V` 합성으로 임의의 앱에 텍스트를 넣을 수 있는가, 클립보드를
   언제 복원해야 붙여넣기가 옛 내용을 집어가지 않는가, 그리고 오버레이 패널이
   떠 있어도 원래 앱이 텍스트 포커스를 유지하는가.
2. 오른쪽 `⌥` 단독 키를 `flagsChanged`로 눌림/뗌 모두 안정적으로 받을 수 있는가.
3. **위 측정은 전부 `say` TTS 음성이다.** 실제 육성에서 전사와 다듬기가 같은
   품질을 내는지는 확인하지 못했다.

## 4. 프로젝트 형태

`.xcodeproj` 대신 SwiftPM 패키지 + 번들 조립 스크립트로 간다.

```
Package.swift              실행 타깃 1개 + 테스트 타깃 1개
Scripts/bundle.sh          실행 파일 + Info.plist → TypelessLike.app 조립, ad-hoc 서명
Resources/Info.plist       LSUIElement, 번들 ID, 마이크 권한 문자열
```

근거:

- 프로젝트 생성 도구가 없어 `.pbxproj`를 손으로 써야 하는데, 그 형식은 diff도
  리뷰도 되지 않는다. 전부 텍스트로 유지하면 변경 추적이 된다.
- 메뉴바 앱에 필요한 Info.plist 항목이 몇 개 안 된다.
- `swift build` / `swift test`로 CLI에서 전부 돌아간다.

최소 배포 타깃은 macOS 26.0, Swift 6 strict concurrency를 켠다.

### 외부 의존성

앱 자체는 의존 패키지가 없지만, **다듬기는 OpenAI 호환 API를 여는 로컬 서버에
의존한다.** 개발 환경에서는 oMLX가 `127.0.0.1:8081`에서 `gemma-4-e2b-it-8bit`를
서빙한다.

서버가 떠 있지 않으면 다듬기를 건너뛰고 전사 원문을 그대로 삽입한다(10절). 앱이
못 쓰게 되지는 않는다.

감수하는 비용: 코드 서명이 수동이다. 재빌드마다 ad-hoc 서명 해시가 바뀌면 손쉬운
사용 권한을 다시 승인해야 할 수 있다. 개발 중 반복되면 고정 서명 신원으로 바꾼다.

## 5. 모듈 구조

```
Sources/TypelessLike/
  App/        MenuBarApp.swift              SwiftUI MenuBarExtra, 상태 아이콘
              OverlayPanel.swift            비활성 NSPanel - 상태 + 레벨 미터
  Core/       DictationState.swift          상태 기계 - 순수, 부수효과 없음
              Coordinator.swift             상태 기계와 실제 컴포넌트 배선
  Input/      HotkeyMonitor.swift           전역 키 이벤트 → TriggerEvent
              AudioCapture.swift            AVAudioEngine → AnalyzerInput + 레벨
              AudioLevel.swift              RMS 계산 - 순수 함수
  Transcribe/ Transcriber.swift             SpeechAnalyzer 래핑 → String
  Refine/     TextRefiner.swift             protocol + 폴백 정책
              OpenAICompatibleRefiner.swift  /v1/chat/completions 클라이언트
              RefinementPrompt.swift        규칙 + few-shot 예시
  Output/     TextInserter.swift            클립보드 백업 → ⌘V 합성 → 복원
Tests/TypelessLikeTests/
              DictationStateTests.swift
              AudioLevelTests.swift
              TextRefinerFallbackTests.swift
              RefinementPromptTests.swift
```

의존 방향은 한 방향이다.

```
App → Core → { Input, Transcribe, Refine, Output }
```

하위 네 그룹은 서로를 모른다. 강제되는 구체적 규칙:

- `Refine/`은 `Speech`를 import하지 않는다.
- `Transcribe/`는 HTTP도 프롬프트도 모른다.
- `Output/`은 전사도 다듬기도 모르고, 완성된 문자열만 받는다.

전사 엔진이나 다듬기 백엔드를 갈아끼울 때 서로를 건드리지 않기 위한 경계다.

## 6. 핵심 계약

### TextRefiner

```swift
protocol TextRefiner: Sendable {
    var isAvailable: Bool { get async }
    func refine(_ raw: String) async throws -> String
}
```

입력도 출력도 순수 문자열이다. 오디오, 로케일, 삽입 대상 앱을 모른다.

### OpenAICompatibleRefiner

구현체는 하나다. 백엔드는 설정으로 갈아끼운다.

```swift
struct OpenAICompatibleRefiner: TextRefiner {
    let baseURL: URL      // 예: http://127.0.0.1:8081/v1
    let model: String     // 예: gemma-4-e2b-it-8bit
    let apiKey: String?
    let timeout: Duration
}
```

`POST {baseURL}/chat/completions`에 OpenAI 형식으로 보낸다. oMLX, Ollama,
LM Studio가 모두 같은 형식을 쓰므로 구현체를 늘리지 않고 `baseURL`과 `model`만
바꾸면 된다. 두 서버에서 `/v1/models` 응답을 확인했다.

가용성은 `GET {baseURL}/models`가 응답하는지로 판단한다.

`refine`이 throw하거나 타임아웃하면 Coordinator가 원본 전사 텍스트로 폴백한다.

### 요청 형식

`temperature: 0.0`으로 고정한다. 같은 말에 같은 결과가 나와야 한다.

**시스템 프롬프트 끝에는 매 요청 고유한 nonce를 붙인다.** 3절에서 확인한 oMLX
캐시 결함 때문이다. 붙이지 않으면 이전 요청의 응답이 그대로 돌아올 수 있고,
받아쓰기 앱에서 그것은 말하지 않은 문장이 삽입된다는 뜻이다.

### 다듬기 프롬프트

규칙 넷과 few-shot 여덟 쌍으로 구성한다.

```
받아쓰기 원문을 다듬는다.
1. 정정 표시어('아니', '아니다', '그게 아니라')가 나오면 표시어와 그 앞의 말을
   전부 지우고 뒤의 말만 남긴다. 앞뒤 주제가 달라도 마찬가지다. 문장이 길고 절이
   여러 개여도 똑같이 적용한다.
2. 군말(어, 음, 그, 그 뭐지)과 더듬어 반복한 말을 지운다.
3. 아래 사전의 단어가 음차돼 있으면 영문으로 되돌린다. 사전에 없는 말은 손대지
   않는다.
  사전: <TERM_GLOSSARY>
4. 문장부호와 띄어쓰기를 정리한다. 그 외의 내용은 바꾸지 않는다.
다듬은 문장만 출력한다.
```

**규칙을 넷보다 늘리면 성능이 떨어진다.** 같은 내용을 여섯 규칙으로 나눠 쓴 판이
63/68에서 61/68로 내려갔다. 규칙이 많아지면 각각의 영향력이 희석된다. 규칙을
추가하고 싶을 때는 기존 규칙에 합치는 쪽을 먼저 시도한다.

### 용어 사전의 형태

`<TERM_GLOSSARY>`는 `RefinementPrompt`가 소유하는, **영문 표기만 쉼표로 나열한 평면
목록**이다. 현재 58개 항목, 484자다.

```
PR, approve, review, merge, main, branch, commit, rebase, push, pull, revert,
deploy, staging, production, rollback, endpoint, timeout, retry, logic, log,
debug, error, authentication, ... langchain, typeless, diagram, TTS, STT, LLM, ...
```

**매핑 테이블이 아니라 후보 집합이다.** `오센티케이션 → authentication` 같은 대응은
주지 않는다. 모델이 발음 유사도로 스스로 찾고, 사전은 후보를 닫는 역할만 한다.
이것이 작동하는 이유는 규칙 3의 "사전에 없는 말은 손대지 않는다"가 열린 생성을
폐쇄형 선택으로 바꾸기 때문이다. 그 제약이 없으면 모델은 뭉개진 발음을 추측해
`어플로그`를 `apply`로 지어낸다.

**제품·라이브러리 고유명사도 넣는다.** 육성 검증에서 `langchain`이 `링체인`,
`typeless`가 `타이블리스`로 전사됐고, 사전에 없을 때는 다듬기가 `테이블리스`로
오히려 악화시켰다. 사전에 넣으면 정확히 복원된다.

**음차 표기를 병기하지 않는다.** `approve(어프루브/어플로그)`처럼 흔한 음차형을
괄호로 덧붙인 판을 측정했으나 33/37로 동점이었다. 사전 길이가 484자에서 763자로
늘어난 만큼 희석이 생겨, 한 항목을 더 맞히는 대신 다른 항목을 놓친다. 규칙 개수에서
관찰한 것과 같은 현상이다.

사전이 커지면 같은 희석이 일어날 것으로 보인다. 항목을 늘릴 때는 회귀 스위트로
확인한다.

few-shot 여덟 쌍이 각각 보여주는 것.

| # | 보여주는 것 |
| --- | --- |
| 1 | 짧은 문장의 정정 |
| 2 | 필러만 있는 경우 |
| 3 | 문장 일부만 정정되고 나머지는 보존되는 경우 |
| 4 | 음차된 개발 용어를 영문으로 되돌리는 경우 |
| 5 | 영어 용어가 없는 순수 한국어 — 손대지 않는다 |
| 6 | 주제가 전환되는 정정 — 앞 절을 통째로 버린다 |
| 7 | 주제 전환 정정 + 용어 복원이 겹치는 경우 |
| 8 | 음절을 더듬어 반복한 경우 |

6~8번은 육성 검증에서 드러난 실패를 보고 추가했다. TTS 음성으로는 나오지 않던
패턴이다.

### 알려진 한계

- 20초를 넘으면 다듬기 지연이 눈에 띄게 늘어난다(30초에 5.4초).
- 전사기가 단어를 누락하면 다듬기는 복구하지 못한다. 없는 정보는 만들 수 없다.
- 용어 사전에 없는 영어 용어는 음차된 채로 남는다. 사전을 넓히는 것이 유일한
  해결책이고, 추측하게 두면 틀린 단어를 지어낸다.
- 용어 복원 과정에서 원래 단어를 지워버리는 경우가 관찰됐다.
- 정정 표시어 앞의 서술을 버리지 못하는 경우가 회귀 스위트에서 3건 남아 있다.
  현재 프롬프트로 도달한 한계이며, 실사용 데이터로 few-shot을 보강해 줄인다.

출력 길이 검증 같은 방어 로직은 MVP에 넣지 않는다. 규칙 4와 예시 3·4로 내용
소실이 잡히는 것을 확인했으므로, 실제로 재발하면 그때 넣는다.

## 7. 상태 기계

부수효과가 없는 순수 함수로 분리한다. 이 프로젝트에서 자동 테스트 가치가 확실한
유일한 지점이다.

```swift
enum DictationState: Equatable {
    case idle
    case holding(since: ContinuousClock.Instant)
    case toggled
    case processing
}

enum TriggerEvent { case keyDown, keyUp }
enum Effect { case startCapture, stopCaptureAndProcess, none }

func reduce(
    _ state: DictationState,
    _ event: TriggerEvent,
    now: ContinuousClock.Instant,
    threshold: Duration
) -> (DictationState, Effect)
```

전이표. `threshold`의 기본값은 250ms다.

| 현재 | 이벤트 | 조건 | 다음 | 효과 |
| --- | --- | --- | --- | --- |
| `idle` | keyDown | | `holding(now)` | `startCapture` |
| `idle` | keyUp | | `idle` | `none` |
| `holding(t0)` | keyUp | `now - t0 < threshold` | `toggled` | `none` |
| `holding(t0)` | keyUp | `now - t0 >= threshold` | `processing` | `stopCaptureAndProcess` |
| `holding(t0)` | keyDown | | `holding(t0)` | `none` |
| `toggled` | keyDown | | `processing` | `stopCaptureAndProcess` |
| `toggled` | keyUp | | `toggled` | `none` |
| `processing` | keyDown | | `processing` | `none` |
| `processing` | keyUp | | `processing` | `none` |

`processing`에서 `idle`로의 복귀는 이벤트가 아니라 Coordinator가 삽입 완료 후
직접 수행한다.

짧게 눌러 `toggled`에 들어간 뒤 다시 누르면 길이와 무관하게 종료된다. 그 종료
keyDown에 뒤따르는 keyUp은 `processing` 상태에서 무시된다.

## 8. 데이터 흐름

```
HotkeyMonitor ──TriggerEvent──▶ Coordinator ──reduce──▶ Effect
                                      │ startCapture
                                      ▼
                     AudioCapture (AVAudioEngine + AVAudioConverter)
                                      │ 레벨(RMS) ─▶ Coordinator ─▶ OverlayPanel
                                      │ AsyncStream<AnalyzerInput>
                                      ▼
                     Transcriber (SpeechAnalyzer + SpeechTranscriber)
                                      │ finalizeAndFinishThroughEndOfInput()
                                      ▼  results 소진 → String
                     TextRefiner.refine(raw) ──throw/타임아웃──▶ raw 그대로
                       (OpenAI 호환 /v1/chat/completions, 2.0~5.4초)
                                      ▼
                     TextInserter (클립보드 백업 → ⌘V → 복원)
                                      ▼
                             Coordinator → idle
```

### 오디오

`SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])`로 목표
포맷을 얻고, `AVAudioConverter`로 마이크 네이티브 포맷을 변환한다. 마이크 포맷을
추측하지 않는다.

변환된 버퍼를 `AnalyzerInput(buffer:)`로 감싸 `AsyncStream`에 흘린다.

### 전사

`SpeechTranscriber(locale: Locale(identifier: "ko-KR"), preset: .transcription)`.

MVP에 실시간 미리보기가 없으므로 `volatileResults`가 필요 없다. 미리보기를 넣을
때 `.progressiveTranscription` 계열로 교체한다.

녹음 종료 시 스트림을 닫고 `finalizeAndFinishThroughEndOfInput()`을 호출한 뒤
`transcriber.results`를 소진하며 텍스트를 이어붙인다.

전사는 말하는 동안 진행되므로 녹음이 끝난 시점에는 사실상 완료돼 있다. 체감
지연은 다듬기 시간이 전부다. 다듬기를 오디오까지 맡기는 안(gemma4 오디오 직결)을
버린 이유가 여기 있다 — 그 경우 전사 시간이 말이 끝난 뒤로 옮겨 온다.

### 삽입

1. `NSPasteboard.general`의 현재 내용과 `changeCount`를 백업한다.
2. 다듬어진 텍스트를 쓴다.
3. `CGEvent`로 `⌘V`를 합성해 프론트모스트 앱에 보낸다.
4. 지연 후 클립보드를 복원한다.

4번의 지연값은 실측으로 정한다. 너무 짧으면 붙여넣기가 옛 내용을 집어간다.

## 9. 오버레이

녹음 중임을 화면에서 확인할 수 있어야 한다. 메뉴바 아이콘만으로는 시선이 닿지
않는다.

### 표시 내용

상태(`녹음 중` / `다듬는 중`)와 목소리 레벨 미터. **전사 텍스트는 띄우지 않는다.**

"내 목소리가 잡히고 있다"는 확인에는 레벨 미터로 충분하고, 텍스트를 띄우려면
전사를 `.progressiveTranscription`으로 바꾸고 확정되지 않은 중간 결과가 계속
고쳐지는 것을 UI에서 처리해야 한다. 그 비용을 MVP에서 지불하지 않는다.

### 포커스를 빼앗지 않는 것이 핵심 제약

오버레이가 키 윈도우가 되면 원래 앱의 텍스트 포커스가 풀려 8절의 `⌘V` 삽입이
엉뚱한 곳으로 간다. 앱의 핵심 기능이 깨지는 문제다. `NSPanel`을 다음 설정으로
만든다.

| 설정 | 값 | 이유 |
| --- | --- | --- |
| `styleMask` | `[.nonactivatingPanel, .borderless]` | 앱을 활성화시키지 않는다 |
| `canBecomeKey` | `false` (오버라이드) | 키 윈도우가 되지 않는다 |
| `ignoresMouseEvents` | `true` | 클릭이 아래 앱으로 통과한다 |
| `level` | `.floating` | 다른 창 위에 뜬다 |
| `collectionBehavior` | `[.canJoinAllSpaces, .fullScreenAuxiliary]` | 전체화면 앱 위에도 뜬다 |
| `isOpaque` / `backgroundColor` | `false` / `.clear` | 둥근 모서리 배경을 직접 그린다 |

이 조합은 3절 가설 1에 포함되어 있고 삽입 스파이크에서 함께 검증한다. 따로
검증하면 의미가 없다.

### 레벨 계산

`AudioCapture`의 탭에서 이미 받고 있는 버퍼로 RMS를 구한다. 별도 오디오 경로를
만들지 않는다.

```swift
func rms(_ samples: UnsafeBufferPointer<Float>) -> Float
```

포인터를 받는 이유는 오디오 콜백마다 배열을 복사하지 않기 위해서다. 테스트에서는
`[Float]`로부터 만들면 되므로 검증에 지장이 없다.

값은 dB로 변환해 표시 범위로 클램프한다. 별도 스무딩 코드는 넣지 않는다 —
업데이트가 오디오 버퍼 주기로 들어오므로 SwiftUI의 `.animation(.linear)`이
떨림을 흡수한다.

### 상태를 받는 경로

`OverlayPanel`은 `AudioCapture`를 직접 보지 않는다. 5절의 의존 방향을 지키기
위해서다. `Coordinator`가 현재 `DictationState`와 최신 레벨을 관찰 가능한 상태로
노출하고, `OverlayPanel`은 그것만 읽는다.

덕분에 오버레이는 오디오 엔진도 전사도 모른 채 그릴 수 있고, 렌더링 없이
`Coordinator` 상태만으로 동작을 확인할 수 있다.

### 위치와 수명

화면 하단 중앙 고정. 마우스를 따라다니지 않는다.

`idle`에서는 감춘다. `holding` 또는 `toggled`에 들어갈 때 띄우고, 삽입이 끝나
`idle`로 돌아갈 때 감춘다.

## 10. 에러 처리

모든 실패는 "덜 좋은 결과"로 떨어진다. 아무것도 못 하는 상태로 가지 않는다.

| 실패 | 대응 |
| --- | --- |
| 다듬기 서버 미가동 | `GET /v1/models` 확인 후 다듬기를 건너뛰고 **원본 전사를 삽입** |
| `refine` throw 또는 타임아웃 | 원본 전사를 삽입 |
| 마이크 권한 없음 | 메뉴바에서 시스템 설정 열기 안내 |
| 손쉬운 사용 권한 없음 | 시작 시 `AXIsProcessTrustedWithOptions`로 확인, 안내 |
| 전사 결과가 빈 문자열 | 아무 동작도 하지 않는다 (빈 붙여넣기 방지) |

### 타임아웃

고정 5초는 쓰지 않는다. 30초 발화의 다듬기가 5.4초 걸리는 것을 측정했으므로 고정
5초는 긴 발화를 항상 폴백시킨다.

```
timeout = 4초 + 녹음 길이 × 0.4
```

5초 발화면 6초, 17초면 10.8초, 30초면 16초다.

길이 비례만으로는 부족하다. 3절에서 17.2초 발화가 7.60초 걸린 반면 30.6초 발화는
5.42초에 끝났다 — 정정 횟수가 지연을 좌우하므로 같은 길이에서도 네 배 차이가
난다. 위 계수는 실측 최댓값(7.60초)에 1.4배 여유를 둔 값이다.

여유를 더 키우지 않는 이유는 타임아웃이 실패 처리 시점이기 때문이다. 넘어가면
원본 전사가 삽입되는데, 그것을 위해 30초 발화 뒤 20초를 기다리게 할 수는 없다.

원칙: 다듬기 실패가 받아쓰기를 죽이지 않는다. LLM은 품질 향상 레이어이지 필수
경로가 아니다.

## 11. 트리거 키

기본값은 오른쪽 `⌥`(Option) 단독이다.

단독 수식키라 다른 앱의 단축키와 충돌하지 않고, `flagsChanged` 이벤트로 눌림과
뗌을 모두 받을 수 있다. `Fn`은 시스템이 받아쓰기와 이모지 입력에 이미 쓰고 있어
피한다.

이는 아직 검증하지 못한 선택이며 3절의 가설 2번에 해당한다. MVP에서 키는 코드
상수로 두고 변경 UI는 만들지 않는다.

## 12. 테스트 전략

자동화는 가치가 확실한 곳에만 건다.

- `DictationState.reduce` — 7절 전이표를 전수 검증한다. 250ms 경계 양쪽을 모두
  포함한다. `ContinuousClock.Instant`를 인자로 받으므로 시간을 주입해 결정적으로
  테스트된다.
- `AudioLevel.rms` — 무음, 최대 진폭, 빈 버퍼를 검증한다. 순수 함수다.
- `TextRefiner` 폴백 — 항상 throw하는 스텁으로 Coordinator가 원본을 삽입하는지
  검증한다.
- `RefinementPrompt` — 만들어진 메시지 배열이 규칙 4개와 few-shot 4쌍을 담고,
  시스템 프롬프트 끝의 nonce가 호출마다 달라지는지 검증한다. nonce가 고정되면
  3절의 캐시 결함으로 엉뚱한 문장이 삽입되므로 회귀 테스트 가치가 있다.

오디오 캡처, 전역 키 이벤트, 텍스트 삽입, 오버레이 포커스 동작은 시스템 권한과
실제 하드웨어에 의존해 수동으로 검증한다. 자동화 비용이 얻는 신뢰보다 크다.

## 13. 구현 순서

3절의 미검증 가설을 먼저 없앤다. 1번이 실패하면 설계 전체가 흔들리므로 코드를
쌓기 전에 확인한다.

1. **삽입 + 오버레이 스파이크** — 클립보드 백업/`⌘V` 합성/복원이 실제 앱에서
   동작하는지, 복원 지연은 얼마여야 하는지, 그리고 9절 설정의 `NSPanel`이 떠
   있어도 삽입이 정상인지 확인한다. 결과에 따라 8절 삽입 절차와 9절 패널 설정을
   확정한다.
2. **핫키 스파이크** — 오른쪽 `⌥` 단독의 `flagsChanged` 눌림/뗌 수신을 확인한다.
   실패 시 대체 키를 정한다.
3. `DictationState.reduce` — 테스트 먼저, 그다음 구현.
4. `AudioCapture` + `AudioLevel` + `Transcriber` — 녹음한 한국어가 문자열로
   나오는 데까지. RMS는 테스트 먼저.
5. `RefinementPrompt` + `OpenAICompatibleRefiner` + 폴백 경로. 프롬프트 구성은
   6절에 확정돼 있으므로 새로 탐색하지 않는다.
6. **육성 검증**(가설 3) — 지금까지의 측정은 전부 TTS 음성이다. 실제로 말해 보고
   전사와 다듬기가 같은 품질을 내는지 확인한다. 무너지면 여기서 방향을 다시
   잡는다. 앞선 단계로 이미 녹음·전사·다듬기가 이어져 있으므로 추가 도구가 필요
   없다.
7. `Coordinator` 배선 + `MenuBarApp` 상태 아이콘 + `OverlayPanel`.
8. `Scripts/bundle.sh`와 권한 요청 흐름.

1번과 2번의 산출물은 버리는 코드다. 확인이 끝나면 결론만 남기고 폐기한다.

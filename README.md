# Untyped

말하면 다듬어진 문장이 커서 위치에 들어가는 macOS 메뉴바 앱. 네트워크를 타지 않는다.

> 단축키를 누른다 → 말한다 → 뗀다 → 군말("어", "음")과 스스로 고친 말("아니, 오늘 저녁에")이
> 정리되고, 음차된 개발 용어("제플로이")가 영문("deploy")으로 돌아온 문장이 지금 포커스된
> 앱의 커서 위치에 삽입된다.

전사는 Apple의 온디바이스 `SpeechAnalyzer`, 다듬기는 로컬에서 돌리는 OpenAI 호환 LLM 서버
(oMLX, Ollama, LM Studio 등)가 맡는다. 다듬기가 실패하거나 늦으면 원본 전사를 그대로 넣는다 —
LLM은 품질 향상 레이어이지 필수 경로가 아니다.

## 요구 사항

- macOS 26 이상, Apple Silicon
- Xcode 26 (Swift 6.3) — `swift build`에 필요
- OpenAI 호환 `/v1/chat/completions` 서버. 기본값은 `http://127.0.0.1:8081/v1`의
  `gemma-4-e2b-it-8bit` (oMLX). 서버가 없어도 앱은 동작한다 — 원본 전사만 삽입된다.

## 빌드와 실행

```sh
./Scripts/bundle.sh            # swift build → build/Untyped.app 조립 → 서명
open build/Untyped.app
```

`.xcodeproj` 없이 SwiftPM 패키지와 조립 스크립트만 쓴다. 테스트는 `swift test`.

### 코드 서명

`bundle.sh`는 키체인에서 `TypelessLike Local Dev`라는 codeSigning 전용 자체 서명 인증서를 찾아
서명하고, 없으면 ad-hoc으로 떨어진다(경고 출력). ad-hoc은 빌드마다 designated requirement가
바뀌어 **손쉬운 사용 권한을 재빌드할 때마다 다시 승인**해야 한다. 자체 인증서로 서명하면 한
번만 승인하면 된다.

인증서는 키체인 접근 → 인증서 지원 → 인증서 생성에서 이름 `TypelessLike Local Dev`, 유형
"코드 서명"으로 만든다. 신뢰 설정은 필요 없다. (앱 이름을 바꾸기 전에 만든 인증서라 이름이
다르다. 새로 만들 때 다른 이름을 쓰려면 `Scripts/bundle.sh`의 이름도 바꾼다.)

### 권한

처음 실행하면 두 가지 권한이 필요하다. 메뉴에 "권한 허용하기…" 항목이 뜬다.

- **마이크** — 녹음
- **손쉬운 사용** — `⌘V` 합성으로 텍스트 삽입. 없으면 전사는 되지만 아무것도 삽입되지 않는다.

## 사용법

메뉴바의 마이크 아이콘이 상태를 보여준다.

| 동작 | 결과 |
|---|---|
| 단축키를 **누르고 있는 동안** 말하고 뗀다 | 뗀 순간 전사·다듬기·삽입 |
| 단축키를 **짧게(250ms 미만) 눌렀다 뗀다** | 토글 녹음 시작. 다시 누르면 종료 (설정에서 끌 수 있음) |

기본 단축키는 **오른쪽 ⌥ Option** 단독이다. 단독 수식키라 다른 앱의 단축키와 충돌하지 않는다.

녹음 중에는 화면 아래에 파형 오버레이가 뜨고, 다듬는 동안 스피너로 바뀐다. 녹음 중 다른 앱의
스피커 출력은 음소거된다(그 소리가 마이크로 되돌아 들어오지 않게).

다듬기 없이 원본이 들어간 경우 오버레이에 이유가 2.5초 표시된다:
"다듬기 시간 초과 — 원본 삽입", "최대 토큰 초과 — 원본 삽입", "다듬기 서버 오류 — 원본 삽입" 등.

## 설정

메뉴 → **설정…**. 저장을 눌러야 적용되고, 재시작은 필요 없다.
파일은 `~/Library/Application Support/Untyped/config.json`(소유자만 읽기, 0600).

| 항목 | 키 | 기본값 | 설명 |
|---|---|---|---|
| 서버 주소 | `base_url` | `http://127.0.0.1:8081/v1` | OpenAI 호환 서버 |
| 모델 | `model` | `gemma-4-e2b-it-8bit` | |
| API 키 | `api_key` | 빈 문자열 | 비어 있으면 Authorization 헤더를 보내지 않는다 |
| 최대 출력 토큰 | `max_tokens` | 900 | 결과가 이보다 길면 잘린 문장 대신 원본을 넣는다 |
| 다듬기 대기 시간 | `refine_timeout_seconds` | 4 | 여기에 녹음 길이의 40%가 더해진다 |
| 시스템 프롬프트 | `system_prompt` | (없음 = 내장 기본값) | 기본값과 같으면 파일에 쓰지 않는다 |
| 기본 예시 포함 | `include_examples` | true | few-shot 8쌍. 번역처럼 성격이 다른 프롬프트를 쓸 땐 끈다 |
| 단축키 | `hotkey` | `right_option` | 좌/우 × ⌥ ⌘ ⌃ ⇧ 여덟 개 중 하나 |
| 토글 녹음 | `toggle_enabled` | true | 끄면 누르는 동안만 녹음 |
| 받아쓰기 기록 | `log_enabled` | true | 아래 로그 |

시스템 프롬프트는 설정 창에서 직접 편집하고 "기본값으로 되돌리기"로 복구한다. few-shot 예시는
설정 창에서 볼 수만 있고 코드(`Sources/Untyped/Refine/RefinementPrompt.swift`)로만 바꾼다.

## 로그

받아쓰기마다 원문과 결과가 `~/Library/Application Support/Untyped/dictation.log`(0600)에
남는다. 설정 창의 "로그 파일 보기…"로 연다. 5MB를 넘으면 `dictation.log.1`로 밀어낸다.

```
[2026-09-11 22:10:33] 녹음 7.2초 · 다듬음
STT : 어 내일 아침에 회의 자료를 보내드릴게요 아니 오늘 저녁에 보내드릴게요
결과: 오늘 저녁에 회의 자료를 보내드릴게요.
```

말한 내용이 전부 남으므로 설정에서 끌 수 있다.

## 원본만 들어갈 때

로그의 `· 원본 (이유)`를 보면 된다.

- **다듬기 시간 초과** — 서버가 느리다. 메모리가 부족하면 OS가 모델을 스왑으로 밀어내 첫 응답이
  수 초~수십 초 걸린다(16GB 기기에서 스왑 17GB 사용 시 9토큰에 29초를 관찰했다). 앱은 녹음
  시작 시 1토큰 요청으로 서버를 미리 깨우지만, 오래 쉰 뒤 첫 한 번은 여전히 넘길 수 있다.
  다른 앱을 닫아 메모리를 확보하거나 "다듬기 대기 시간"을 올린다.
- **최대 토큰 초과** — 긴 발화. "최대 출력 토큰"을 올린다.
- **다듬기 서버 오류** — 서버가 꺼졌거나 주소·키가 틀렸다. 메뉴에 "연결할 수 없음"이 함께 뜬다.

## 구조

```
Sources/Untyped/
  App/        MenuBarApp.swift         MenuBarExtra, Settings 씬
              SettingsView.swift       설정 창
              OverlayPanel.swift       비활성 NSPanel — 파형·스피너·알림
              PermissionStatus.swift   마이크·손쉬운 사용 권한
  Core/       DictationState.swift     상태 기계 — 순수 함수
              Coordinator.swift        상태 기계와 컴포넌트 배선. 유일한 배선 지점
              AppConfig.swift          config.json 읽기/쓰기
              DictationLog.swift       dictation.log
  Input/      HotkeyKey.swift          단독 수식키 8개와 판정
              HotkeyMonitor.swift      flagsChanged → TriggerEvent
              AudioCapture.swift       AVAudioEngine → 오디오 스트림 + 레벨
              AudioLevel.swift         RMS
              SystemAudioMuter.swift   녹음 중 다른 앱 출력 음소거
  Transcribe/ Transcriber.swift        SpeechAnalyzer → String
  Refine/     TextRefiner.swift        protocol, 폴백 정책, 타임아웃
              OpenAICompatibleRefiner.swift
              RefinementPrompt.swift   규칙 4개 + 용어 사전 + few-shot 8쌍
  Output/     TextInserter.swift       클립보드 백업 → ⌘V → 복원
```

의존 방향은 `App → Core → { Input, Transcribe, Refine, Output }` 한 방향이다. 하위 모듈은 서로를
모르고 `Coordinator`만 전부를 안다. 상태 기계(`reduce`)는 시간을 인자로 받는 순수 함수라
결정적으로 테스트된다.

다듬기 요청은 `temperature: 0`, 시스템 메시지는 매 요청 같은 바이트로 보내 서버의 프리픽스
캐시가 적중하게 한다(oMLX는 512토큰 블록 단위라 프롬프트가 그보다 짧으면 캐시되지 않는다).

## 테스트

```sh
swift test
```

상태 기계 전이표, RMS, 설정 파일 왕복·호환·권한, 핫키 판정, 프롬프트 구성, 폴백 정책,
빈 오디오 입력에서 전사기가 멈추지 않는지 등을 검증한다. 오디오 캡처·전역 키 이벤트·텍스트
삽입·오버레이는 시스템 권한과 하드웨어에 묶여 있어 수동으로 확인한다.

## 설계 문서

`docs/superpowers/specs/`에 설계 결정과 실측 근거가 있다(로컬에만 유지, git 추적 제외).

[English](README.md) | 한국어

# Untyped

**말하면 다듬어진 문장이 커서 위치에 들어갑니다.** 전부 내 Mac 안에서 도는 macOS 메뉴바 받아쓰기 앱 — 온디바이스 음성 인식에 로컬 LLM을 더해 군말을 지우고, 말하다 고친 내용을 반영하고, 한국어로 발음한 개발 용어를 영문으로 되돌립니다.

![Platform](https://img.shields.io/badge/platform-macOS%2026-blue) ![Swift](https://img.shields.io/badge/Swift-6.3-orange) ![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen)

```
키를 누른 채 말한다:
  "어 내일 아침에 자료를 보내드릴게요 아니 오늘 저녁에 보내드릴게요"

Untyped가 넣는다:
  "오늘 저녁에 자료를 보내드릴게요."
```

## 특징

- **누르고 말하거나, 톡 쳐서 토글.** 단독 수식키 하나(기본 오른쪽 ⌥)라 다른 앱 단축키와 충돌하지 않습니다. ⌘V가 되는 앱이면 어디서든 동작합니다.
- **의도를 살리는 다듬기.** "아니, 오늘 저녁에"라고 하면 그 앞말이 지워집니다. "어", "음"은 사라지고, "제플로이"·"스테이징"·"피알"은 `deploy`, `staging`, `PR`로 돌아옵니다.
- **네트워크를 타지 않습니다.** 전사는 Apple 온디바이스 `SpeechAnalyzer`, 다듬기는 로컬 OpenAI 호환 서버(oMLX, Ollama, LM Studio…).
- **절대 막지 않습니다.** LLM이 느리거나 꺼졌거나 결과가 잘리면 원본 전사를 대신 넣고, 오버레이가 이유를 알려줍니다.
- **프롬프트 편집, 로그 확인.** 설정 창에서 시스템 프롬프트를 고치고, 받아쓰기마다 원문 → 결과가 로컬에 기록됩니다.

## 동작 원리

```
오른쪽 ⌥ 누름 ──▶ 마이크 (AVAudioEngine) ──▶ SpeechAnalyzer (온디바이스, ko-KR)
                                                        │ 원본 전사
                                                        ▼
                                       로컬 LLM  /v1/chat/completions
                                       (규칙 4개 + 용어 사전 + few-shot 8쌍)
                                                        │ 다듬은 문장   (시간 초과·오류 → 원본)
                                                        ▼
                                        클립보드 ──▶ ⌘V 합성 ──▶ 클립보드 복원
```

키를 누르고 있는 동안 다른 앱의 스피커 출력은 음소거되어 그 소리가 마이크로 되돌아 들어오지 않습니다.

## 시작하기

### 요구 사항

- macOS 26 이상, Apple Silicon
- Xcode 26 (Swift 6.3) — `swift build`에 필요
- 다듬기용 OpenAI 호환 채팅 서버. 기본값 `http://127.0.0.1:8081/v1`, 모델 `gemma-4-e2b-it-8bit` (oMLX). 서버가 없어도 앱은 동작합니다 — 원본 전사만 삽입됩니다.

### 빌드와 실행

```sh
./Scripts/bundle.sh      # swift build → build/Untyped.app 조립 → 서명
open build/Untyped.app
```

`.xcodeproj`는 없습니다. SwiftPM 패키지와 조립 스크립트뿐입니다.

### 권한

처음 실행하면 메뉴에 "…권한 허용하기" 항목 두 개가 뜹니다.

| 권한 | 이유 |
|---|---|
| 마이크 | 녹음 |
| 손쉬운 사용 | 텍스트를 넣는 ⌘V 합성. 없으면 전사는 되지만 아무것도 삽입되지 않습니다 |

<details>
<summary><b>코드 서명 (재빌드할 때마다 손쉬운 사용을 다시 묻는 이유)</b></summary>

`Scripts/bundle.sh`는 키체인에 `TypelessLike Local Dev`라는 자체 서명 인증서(코드 서명 전용)가 있으면 그것으로 서명하고, 없으면 경고와 함께 ad-hoc으로 떨어집니다.

ad-hoc 서명은 빌드마다 designated requirement가 바뀌는데 macOS는 손쉬운 사용 권한을 그 값에 묶어 두므로, 재빌드할 때마다 다시 승인해야 합니다. 자체 인증서로 서명하면 한 번만 승인하면 됩니다.

키체인 접근 → 인증서 지원 → 인증서 생성…에서 이름 `TypelessLike Local Dev`, 유형 *코드 서명*으로 만듭니다. 신뢰 설정은 필요 없습니다. (앱 이름을 바꾸기 전에 만든 인증서라 이름이 다릅니다. 다른 이름을 쓰려면 `Scripts/bundle.sh`에서 바꾸세요.)
</details>

## 사용법

메뉴바의 마이크 아이콘이 상태를 보여줍니다: 대기, 듣는 중, 다듬는 중.

| 동작 | 결과 |
|---|---|
| 키를 **누른 채** 말하고 뗀다 | 뗀 순간 전사 → 다듬기 → 삽입 |
| **짧게(250ms 미만)** 눌렀다 뗀다 | 토글 녹음 시작. 다시 누르면 종료 (설정에서 끌 수 있음) |

듣는 동안 화면 아래에 파형 오버레이가 뜨고, 다듬는 동안 스피너로 바뀝니다. 다듬은 결과 대신 원본이 들어가면 이유가 2.5초 표시됩니다 — 예: *다듬기 시간 초과 — 원본 삽입*.

## 설정

메뉴 → **설정…**. **저장**을 누르면 재시작 없이 적용됩니다. 파일은 `~/Library/Application Support/Untyped/config.json` (API 키가 들어 있어 소유자만 읽기, 0600).

<details>
<summary><b>전체 설정 항목</b></summary>

| 항목 | 키 | 기본값 | 설명 |
|---|---|---|---|
| 서버 주소 | `base_url` | `http://127.0.0.1:8081/v1` | OpenAI 호환 서버 |
| 모델 | `model` | `gemma-4-e2b-it-8bit` | |
| API 키 | `api_key` | `""` | 비어 있으면 `Authorization` 헤더를 보내지 않음 |
| 최대 출력 토큰 | `max_tokens` | `900` | 결과가 이보다 길면 잘린 문장을 넣는 대신 원본 전사를 넣음 |
| 다듬기 대기 시간 | `refine_timeout_seconds` | `4` | 여기에 녹음 길이의 40%가 더해짐 |
| 시스템 프롬프트 | `system_prompt` | *(없음 = 내장 기본값)* | 기본값과 다를 때만 파일에 씀 |
| 기본 예시 포함 | `include_examples` | `true` | few-shot 8쌍. 번역처럼 성격이 다른 프롬프트를 쓸 땐 끔 |
| 단축키 | `hotkey` | `right_option` | 좌/우 × `option`, `command`, `control`, `shift` 중 하나 |
| 토글 녹음 | `toggle_enabled` | `true` | 끄면 누르는 동안만 녹음 |
| 받아쓰기 기록 | `log_enabled` | `true` | [로그](#로그) 참고 |

시스템 프롬프트는 설정 창에서 직접 고치고 "기본값으로 되돌리기"로 복구합니다. few-shot 예시는 설정 창에서 볼 수만 있고 코드(`Sources/Untyped/Refine/RefinementPrompt.swift`)로 바꿉니다.
</details>

## 로그

받아쓰기마다 원문과 결과가 `~/Library/Application Support/Untyped/dictation.log`(0600, 5MB에서 `.1`로 회전)에 붙습니다. 설정 창 → **로그 파일 보기…**로 엽니다.

```
[2026-09-11 22:10:33] 녹음 7.2초 · 다듬음
STT : 어 내일 아침에 회의 자료를 보내드릴게요 아니 오늘 저녁에 보내드릴게요
결과: 오늘 저녁에 회의 자료를 보내드릴게요.
```

말한 내용이 전부 남으므로 설정에서 끌 수 있습니다.

## 문제 해결

로그는 원본이 들어간 경우를 `· 원본 (이유)`로 표시합니다.

| 이유 | 뜻 | 대처 |
|---|---|---|
| 다듬기 시간 초과 | 서버가 느림 | 메모리를 확보하세요 — 부족하면 macOS가 모델을 스왑으로 밀어내 첫 토큰까지 3~30초가 걸립니다(16GB Mac, 스왑 17GB 사용 시 9토큰에 29초 관찰). 녹음 시작 시 1토큰 요청으로 서버를 미리 깨우지만, 오래 쉰 뒤 첫 한 번은 여전히 넘길 수 있습니다. *다듬기 대기 시간*을 올리는 것도 방법입니다. |
| 최대 토큰 초과 | 긴 발화 | *최대 출력 토큰*을 올리세요 |
| 다듬기 서버 오류 | 서버 꺼짐, 주소·키 오류 | 메뉴에도 "연결할 수 없음"이 뜹니다 |

프리픽스 캐시: 시스템 메시지를 매 요청 같은 바이트로 보내 서버의 프리픽스 캐시가 적중하게 합니다. oMLX는 512토큰 블록 단위라 그보다 짧은 프롬프트는 캐시되지 않지만, 짧은 만큼 프리필도 싸서 문제되지 않습니다.

## 구조

<details>
<summary><b>모듈 배치</b></summary>

```
Sources/Untyped/
  App/        MenuBarApp.swift         MenuBarExtra + Settings 씬
              SettingsView.swift       설정 창
              OverlayPanel.swift       비활성 NSPanel — 파형·스피너·알림
              PermissionStatus.swift   마이크·손쉬운 사용 권한
  Core/       DictationState.swift     상태 기계 — 순수 함수
              Coordinator.swift        컴포넌트를 잇는 유일한 지점
              AppConfig.swift          config.json 읽기/쓰기
              DictationLog.swift       dictation.log
  Input/      HotkeyKey.swift          단독 수식키 8개와 이벤트 판정
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

의존 방향은 `App → Core → { Input, Transcribe, Refine, Output }` 한 방향입니다. 하위 모듈은 서로를 모르고 `Coordinator`만 전부를 압니다. 상태 기계(`reduce`)는 시간을 인자로 받아 결정적으로 테스트됩니다. 요청은 `temperature: 0`입니다.
</details>

## 개발

```sh
swift test
```

검증 범위: 상태 기계 전이표, RMS, 설정 파일 왕복·기존 파일 호환·권한, 핫키 판정, 프롬프트 구성, 폴백 정책, 빈 오디오 입력에서 전사기가 멈추지 않는지. 오디오 캡처·전역 키 이벤트·텍스트 삽입·오버레이는 시스템 권한과 하드웨어에 묶여 있어 수동으로 확인합니다.

설계 결정과 실측 근거는 `docs/superpowers/specs/`에 있습니다(로컬에만 유지, git 추적 제외).

## 기여

이슈와 풀 리퀘스트를 환영합니다. 규칙: 외부 SwiftPM 의존성 없음, 위의 한 방향 의존 유지, 커밋 메시지는 `feat:` / `fix:` / `docs:` 접두어.

## 라이선스

아직 정하지 않았습니다.

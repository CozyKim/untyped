[English](README.md) | 한국어

<p align="center"><img src="Scripts/icon-previews/b-speech-cursor.png" width="128" alt="Untyped icon"></p>

# Untyped

**말하면 다듬어진 문장이 커서 위치에 들어갑니다.** 전부 내 Mac 안에서 도는 macOS 메뉴바 받아쓰기 앱 — 온디바이스 음성 인식에 로컬 LLM을 더해 군말을 지우고, 말하다 고친 내용을 반영하고, 한국어로 발음한 개발 용어를 영문으로 되돌립니다.

![Platform](https://img.shields.io/badge/platform-macOS%2026-blue) ![Swift](https://img.shields.io/badge/Swift-6.3-orange) ![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen) ![License](https://img.shields.io/badge/license-MIT-lightgrey)

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
| **앱으로 보내기 키** (선택, 두 번째 키) | 홀드/탭은 같고, 결과가 지정한 앱에 들어감: 그 앱으로 전환 → 붙여넣기 → 원래 앱 복귀. 그 앱이 꺼져 있으면 알림만 띄우고 녹음을 시작하지 않음 |

듣는 동안 화면 아래에 파형 오버레이가 뜨고, 다듬는 동안 스피너로 바뀝니다. 2단계(Apple) 방식에서는 말하는 동안 지금까지 인식된 말이 파형 아래에 글자로 보입니다(마지막 두 줄) — 빠른 잠정 전사라 최종 결과와 다를 수 있고, 키를 떼면 사라지며 삽입·로그에는 쓰이지 않습니다. 1단계(LLM 오디오) 방식은 중간 전사가 없어 아무것도 보이지 않습니다. 다듬은 결과 대신 원본이 들어가면 이유가 2.5초 표시됩니다 — 예: *다듬기 시간 초과 — 원본 삽입*.

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
| 키를 누를 때 예열 | `warm_up_enabled` | `true` | 키다운 때 `/health`를 묻고 모델이 없으면 1토큰 예열 요청을 보냄 — 모델이 항상 올라와 있는 서버에서는 꺼서 녹음 시작과 겹치는 요청을 없앨 수 있음 |
| 모델 유지 (Keep Alive) | `keep_alive_enabled` | `false` | 모델을 고정할 수 없는 서버용: 1토큰 예열 요청을 주기적으로 보내 모델의 유휴 TTL이 계속 새로 시작하게 함 — [Keep Alive](#keep-alive) 참고 |
| 유지 요청 간격 | `keep_alive_interval_minutes` | `5` | `1`, `2`, `5`, `10`, `15`, `30` 중 하나. 그 밖의 값은 `5`로 읽음. 서버의 유휴 언로드 시간보다 짧아야 함 |
| 시스템 프롬프트 | `system_prompt` | *(없음 = 내장 기본값)* | 기본값과 다를 때만 파일에 씀 |
| 기본 예시 포함 | `include_examples` | `true` | few-shot 8쌍. 번역처럼 성격이 다른 프롬프트를 쓸 땐 끔 |
| 단축키 | `hotkey` | `right_option` | 좌/우 × `option`, `command`, `control`, `shift` 중 하나 |
| 토글 녹음 | `toggle_enabled` | `true` | 끄면 누르는 동안만 녹음 |
| 넣은 뒤 Return 누르기 | `press_return` | `false` | 기본 단축키로 넣은 뒤 Return — 채팅 앱에서 바로 전송. 터미널이면 명령이 실행됨 |
| 원본 삽입 때도 Return 누르기 | `press_return_on_fallback` | `false` | 다듬기 실패로 원본이 들어간 경우에도 Return. 두 단축키 모두 적용 |
| 앱으로 보내기 단축키 | `target_app_hotkey` | *(없음 = 꺼짐)* | 두 번째 단독 수식키. `hotkey`와 달라야 함 |
| 대상 앱 | `target_app_bundle_id` | *(없음)* | 보낼 앱의 bundle ID. 설정 창의 파일 선택 창에서 앱을 골라 채움 |
| 앱으로 보내기 · 넣은 뒤 Return 누르기 | `target_app_press_return` | `false` | 대상 앱에 넣은 뒤 Return |
| 전사 방식 | `transcription_backend` | `apple` | `apple` = 2단계: 기기 내 `SpeechAnalyzer` → LLM이 텍스트를 다듬음. `llm_audio` = 1단계, Apple STT 없음: 녹음(16 kHz mono WAV, `input_audio` 파트)을 같은 시스템 프롬프트·예시 뒤에 붙여 보내면 모델이 다듬은 문장을 바로 돌려줌. 모델이 오디오 입력을 받아야 함(예: `gemma-4-e2b-it`). 폴백할 원본 전사가 없으므로 실패하면(서버 꺼짐, 모델이 오디오 거부, 대기 시간 = *다듬기 대기 시간* + 녹음 길이 초과, 잘림·빈 결과) 아무것도 넣지 않고 알림·로그에 이유를 남김 |
| 받아쓰기 기록 | `log_enabled` | `true` | [로그](#로그) 참고 |
| 로그인할 때 자동으로 시작 | *(파일에 없음)* | 꺼짐 | macOS 로그인 항목(`SMAppService`). 상태는 시스템이 가지므로 시스템 설정 › 일반 › 로그인 항목에도 나타남 |

시스템 프롬프트는 설정 창에서 직접 고치고 "기본값으로 되돌리기"로 복구합니다. few-shot 예시는 설정 창에서 볼 수만 있고 코드(`Sources/Untyped/Refine/RefinementPrompt.swift`)로 바꿉니다.
</details>

## 로그

받아쓰기마다 원문과 결과가 `~/Library/Application Support/Untyped/dictation.log`(0600, 5MB에서 `.1`로 회전)에 붙습니다. 설정 창 → **로그 파일 보기…**로 엽니다.

```
[2026-09-11 22:10:33] 녹음 7.2초 · 다듬음
소요: STT 0.3초 · 다듬기 1.4초
STT : 어 내일 아침에 회의 자료를 보내드릴게요 아니 오늘 저녁에 보내드릴게요
결과: 오늘 저녁에 회의 자료를 보내드릴게요.
```

입력 시도 결과는 같은 항목의 `입력:` 줄에 대상 앱과 함께 기록됩니다. 정상 수신, 확인 시간 초과(사전·현재 접근성 값의 읽기 가능 여부), 포커스 변경, 클립보드 소유권 변경, 게시 전 실패와 취소를 구분합니다. 설정의 **로그 파일 보기…**로 확인하며, **받아쓰기 기록**을 끄면 입력 진단도 저장하지 않습니다.

헤더에는 녹음 길이가, 바로 아래 `소요:` 줄에는 키를 뗀 뒤의 시간이 경로별로 적힙니다. `apple`: `STT`는 키를 뗀 뒤 기기 내 최종 전사가 나오기까지, `다듬기`는 LLM 다듬기 요청 왕복(시간 초과·오류면 폴백까지 기다린 시간). `llm_audio`: 전사와 다듬기가 한 요청이라 `오디오 다듬기` 하나입니다. 이 줄은 이 버전이 남긴 항목에만 있고, 이전 항목의 모양은 그대로입니다.

다듬은 결과 대신 원본이 들어간 경우엔 소요 줄 아래 `원인:` 줄이 이유를 말해 줍니다 — 로컬 LLM 서버가 꺼져 있었는지(연결 거부), 모델을 아직 올리는 중이었는지(콜드 스타트: 키를 누를 때 보낸 예열 요청이 안 돌아옴), 서버는 살아 있는데 느렸는지, HTTP 오류였는지:

```
[2026-09-12 22:10:33] 녹음 7.2초 · 원본 (다듬기 시간 초과)
소요: STT 0.3초 · 다듬기 6.9초
원인: 콜드 스타트 — 예열 요청이 9.3초째 응답 없음(모델 로드 중). 대기 상한 6.9초
```

Keep Alive 요청은 이 파일에 쓰지 않습니다. 요청마다 통합 로그(Console.app, `[KeepAlive]` 접두)에 한 줄만 남깁니다 — `완료 0.8초` 또는 `실패 0.0초: 연결 거부 — 로컬 LLM 서버가 실행 중이 아님 — 다음 주기에 다시 시도`. 키도, 요청·응답 본문도 남기지 않습니다.

말한 내용이 전부 남으므로 설정에서 끌 수 있습니다.

## 문제 해결

로그는 원본이 들어간 경우를 `· 원본 (이유)`로 표시합니다.

| 이유 | 뜻 | 대처 |
|---|---|---|
| 다듬기 시간 초과 | 서버가 느림 | 메모리를 확보하세요 — 부족하면 macOS가 모델을 스왑으로 밀어내 첫 토큰까지 3~30초가 걸립니다(16GB Mac, 스왑 17GB 사용 시 9토큰에 29초 관찰). 녹음 시작 시 1토큰 요청으로 서버를 미리 깨우지만(아래 *예열과 health 확인*), 오래 쉰 뒤 첫 한 번은 여전히 넘길 수 있습니다. *다듬기 대기 시간*을 올리는 것도 방법입니다. |
| 최대 토큰 초과 | 긴 발화 | *최대 출력 토큰*을 올리세요 |
| 다듬기 서버 오류 | 서버 꺼짐, 주소·키 오류 | 메뉴에도 "연결할 수 없음"이 뜹니다 |

프리픽스 캐시: 시스템 메시지를 매 요청 같은 바이트로 보내 서버의 프리픽스 캐시가 적중하게 합니다. oMLX는 512토큰 블록 단위라 그보다 짧은 프롬프트는 캐시되지 않지만, 짧은 만큼 프리필도 싸서 문제되지 않습니다.

예열과 health 확인: 키를 누르는 순간 `base_url`의 origin에 `GET /health`를 한 번 묻습니다(`/v1/health`가 아님, 1초 타임아웃). oMLX는 `{"status":"healthy","engine_pool":{"loaded_count":1,…}}`처럼 답하는데, HTTP 200이고 `loaded_count`가 1 이상이면 모델이 이미 올라와 있는 것이므로 1토큰 예열 요청을 보내지 않습니다 — 녹음 시작과 겹치던 부하가 사라집니다. `loaded_count`가 0이거나(oMLX는 모델을 올리는 동안 503 + `status: "loading"`), `/health`가 없거나(Ollama·LM Studio 등 404), 응답이 늦거나 형식이 다르면 지금까지처럼 예열합니다. 주기적으로 묻지는 않습니다 — 키다운마다 GET 한 번이 전부입니다. 설정의 *키를 누를 때 예열*을 끄면 health 확인과 예열 요청을 모두 보내지 않습니다. 한계 두 가지: 응답에 *어느* 모델이 올라와 있는지가 없어 `loaded_count ≥ 1`이면 설정한 모델로 간주하므로, 여러 모델 중 다른 모델만 올라와 있으면 예열을 건너뛰어 콜드 스타트를 겪습니다. 또 "올라와 있음"은 서버 엔진의 존재 여부라 macOS가 모델을 스왑으로 밀어낸 상태는 잡지 못합니다 — 그 경우 스왑 복귀 비용을 다듬기 때 치르며, 로그의 `원인:` 줄이 "예열을 생략했으나 …"로 그 사실을 남깁니다.

<a name="keep-alive"></a>Keep Alive(기본 꺼짐): 예열은 키를 누른 뒤에야 도움이 됩니다 — 서버가 유휴 TTL이 지나면 모델을 내리고 고정(pin)도 못 하는 경우, 쉬었다 하는 첫 받아쓰기는 여전히 로드 비용을 통째로 치릅니다. 설정의 *모델 유지 (Keep Alive)*를 켜면 예열과 같은 1토큰 `POST /v1/chat/completions`(시스템 프롬프트 + 예시 + `"."`, `max_tokens: 1`, `temperature: 0`)를 시작 즉시 한 번, 그 뒤 *유지 요청 간격*(1/2/5/10/15/30분, 기본 5분)마다 보내 모델이 실제로 접근되고 `last_access`가 갱신되게 합니다. `GET /health`는 일부러 쓰지 않습니다 — 상태만 알려줄 뿐 접근으로 치지 않아 TTL을 멈추지 못합니다. 간격은 서버의 유휴 언로드 시간보다 짧게 잡으세요. 동작: 루프 하나라 요청이 겹치지 않고(앞 요청이 끝나야 다음을 보냄), 받아쓰기가 진행 중인 주기는 건너뜁니다(그 다듬기 요청이 모델을 건드리므로). 요청마다 걸린 시간을 한 줄 남기고, 실패(서버 꺼짐·HTTP 오류·시간 초과)는 이유 한 줄과 함께 기록한 뒤 다음 주기에 다시 시도합니다 — 백오프도 오버레이 알림도 없고 받아쓰기를 막지 않습니다. 설정을 저장하면 돌던 루프(진행 중 요청 포함)를 취소하고 새 서버·간격으로 다시 시작합니다. 한계: 서버가 그 요청에 *설정한* 모델을 올리는 만큼만 유지되고, macOS가 모델을 스왑으로 밀어내는 것은 보지도 막지도 못하며(요청이 스왑 복귀 비용을 치를 뿐), 요청마다 모델을 새로 올리고 캐시하지 않는 서버에서는 주기적인 작은 요청만 늘어날 뿐 얻는 게 없습니다.

## 구조

<details>
<summary><b>모듈 배치</b></summary>

```
Sources/Untyped/
  App/        MenuBarApp.swift         MenuBarExtra + Settings 씬
              SettingsView.swift       설정 창
              OverlayPanel.swift       비활성 NSPanel — 파형·스피너·알림
              PermissionStatus.swift   마이크·손쉬운 사용 권한
              LoginItem.swift          macOS 로그인 항목(로그인 시 자동 시작)
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
              AudioRecorder.swift      PCM 버퍼 → WAV 바이트 (`llm_audio`용)
  Refine/     TextRefiner.swift        protocol, 폴백 정책, 타임아웃
              LLMHealth.swift          origin/health 해석 — 모델이 올라와 있으면 예열 생략
              KeepAlive.swift          간격 선택지 + 모델을 주기적으로 건드려 유휴 TTL을 새로 시작하는 루프
              OpenAICompatibleRefiner.swift   같은 서버로 텍스트 다듬기, 또는 오디오를 한 요청으로 다듬기
              RefinementPrompt.swift   규칙 4개 + 용어 사전 + few-shot 8쌍; 마지막 턴이 텍스트 또는 오디오
              MultipartChatMessage.swift  content가 문자열 또는 `input_audio`/`text` 파트인 채팅 메시지
  Output/     TextInserter.swift       클립보드 백업 → ⌘V → 복원
              TargetApp.swift          지정 앱 활성화 → TextInserter → 원래 앱 복귀
```

의존 방향은 `App → Core → { Input, Transcribe, Refine, Output }` 한 방향입니다. 하위 모듈은 서로를 모르고 `Coordinator`만 전부를 압니다. 상태 기계(`reduce`)는 시간을 인자로 받아 결정적으로 테스트됩니다. 요청은 `temperature: 0`입니다.
</details>

## 개발

```sh
swift test
```

검증 범위: 상태 기계 전이표, RMS, 설정 파일 왕복·기존 파일 호환·권한, 핫키 판정, 프롬프트 구성, 폴백 정책, 소요 시간 줄을 포함한 로그 항목 형식, Keep Alive 요청 페이로드(`URLProtocol` 스텁으로)와 스케줄러(간격, 받아쓰기 중 건너뜀, 겹침 없음, 실패 기록과 재시도, 정지·재시작, 꺼져 있으면 무요청), 빈 오디오 입력에서 전사기가 멈추지 않는지. 오디오 캡처·전역 키 이벤트·텍스트 삽입·오버레이·로그인 항목 등록은 시스템 권한·하드웨어·`.app` 번들에 묶여 있어 수동으로 확인합니다.

설계 결정과 실측 근거는 `docs/superpowers/specs/`에 있습니다(로컬에만 유지, git 추적 제외).

## 기여

이슈와 풀 리퀘스트를 환영합니다. 규칙: 외부 SwiftPM 의존성 없음, 위의 한 방향 의존 유지, 커밋 메시지는 `feat:` / `fix:` / `docs:` 접두어.

## 라이선스

[MIT](LICENSE)

English | [한국어](README.ko.md)

<p align="center"><img src="Scripts/icon-previews/b-speech-cursor.png" width="128" alt="Untyped icon"></p>

# Untyped

**Speak, and a cleaned-up sentence lands at your cursor.** A macOS menu-bar dictation app that runs entirely on your machine — on-device speech recognition plus a local LLM that strips fillers, applies your mid-sentence corrections, and restores the English tech terms you said in Korean.

![Platform](https://img.shields.io/badge/platform-macOS%2026-blue) ![Swift](https://img.shields.io/badge/Swift-6.3-orange) ![Dependencies](https://img.shields.io/badge/dependencies-none-brightgreen) ![License](https://img.shields.io/badge/license-MIT-lightgrey)

```
You hold the key and say:
  "어 내일 아침에 자료를 보내드릴게요 아니 오늘 저녁에 보내드릴게요"

Untyped inserts:
  "오늘 저녁에 자료를 보내드릴게요."
```

> The app is built for Korean speech and its UI is in Korean. Everything else — settings file, logs, build — is documented here in English.

## Features

- **Hold-to-talk, or tap to toggle.** One standalone modifier key (right ⌥ by default) — never collides with other apps' shortcuts. Works in any app that accepts ⌘V.
- **Refinement that respects what you meant.** "Wait, no, tonight" removes what came before it. Fillers ("어", "음") vanish. Korean-transliterated dev terms come back as `deploy`, `staging`, `PR`.
- **Nothing leaves your Mac.** Transcription is Apple's on-device `SpeechAnalyzer`; refinement goes to a local OpenAI-compatible server (oMLX, Ollama, LM Studio…).
- **Never blocks you.** If the LLM is slow, down, or truncates, the raw transcript is inserted instead and the overlay tells you why.
- **Editable prompt, inspectable log.** Change the system prompt in Settings; every dictation (raw → result) is logged locally.

## How it works

```
right ⌥ down ──▶ mic (AVAudioEngine) ──▶ SpeechAnalyzer (on-device, ko-KR)
                                                   │ raw transcript
                                                   ▼
                                  local LLM  /v1/chat/completions
                                  (4 rules + glossary + 8 few-shot pairs)
                                                   │ refined text   (timeout / error → raw)
                                                   ▼
                                   clipboard ──▶ synthesized ⌘V ──▶ clipboard restored
```

While the key is held, other apps' audio output is muted so it does not bleed into the mic.

## Getting started

### Prerequisites

- macOS 26 or later, Apple Silicon
- Xcode 26 (Swift 6.3) for `swift build`
- An OpenAI-compatible chat server for refinement. Default: `http://127.0.0.1:8081/v1`, model `gemma-4-e2b-it-8bit` (oMLX). Without a server the app still works — it inserts the raw transcript.

### Build and run

```sh
./Scripts/bundle.sh      # swift build → assembles build/Untyped.app → codesign
open build/Untyped.app
```

There is no `.xcodeproj`; the app is a SwiftPM package plus an assembly script.

### Permissions

On first launch the menu shows two "allow…" items:

| Permission | Why |
|---|---|
| Microphone | recording |
| Accessibility | the synthesized ⌘V that inserts text. Without it you get transcription but nothing is inserted |

<details>
<summary><b>Code signing (why Accessibility keeps asking after rebuilds)</b></summary>

`Scripts/bundle.sh` signs with a local self-signed certificate named `TypelessLike Local Dev` (code-signing only) if it exists in your keychain, and falls back to ad-hoc signing with a warning.

Ad-hoc signing changes the designated requirement on every build, and macOS keys the Accessibility grant to that requirement — so you would re-approve after every rebuild. A self-signed certificate keeps it stable; approve once.

Create it in Keychain Access → Certificate Assistant → Create a Certificate…, name `TypelessLike Local Dev`, type *Code Signing*. No trust settings are needed. (The name predates the app's rename; to use a different name, change it in `Scripts/bundle.sh`.)
</details>

## Usage

The menu-bar mic icon shows state: idle, listening, refining.

| Action | Result |
|---|---|
| **Hold** the key, speak, release | On release: transcribe → refine → insert |
| **Tap** (< 250 ms) | Starts toggle recording; tap again to stop (can be disabled) |

A floating waveform appears at the bottom of the screen while listening and turns into a spinner while refining. If the raw transcript was inserted instead of a refined one, a notice explains why for 2.5 s — e.g. *다듬기 시간 초과 — 원본 삽입* (refinement timed out — raw inserted).

## Configuration

Menu → **설정…** (Settings). Changes apply on **저장** (Save) without restarting. The file is `~/Library/Application Support/Untyped/config.json` (mode 0600 — it holds your API key).

<details>
<summary><b>All settings</b></summary>

| Setting (UI) | Key | Default | Notes |
|---|---|---|---|
| 서버 주소 | `base_url` | `http://127.0.0.1:8081/v1` | OpenAI-compatible server |
| 모델 | `model` | `gemma-4-e2b-it-8bit` | |
| API 키 | `api_key` | `""` | empty = no `Authorization` header |
| 최대 출력 토큰 | `max_tokens` | `900` | longer results are discarded in favor of the raw transcript rather than inserted truncated |
| 다듬기 대기 시간 | `refine_timeout_seconds` | `4` | plus 40 % of the recording length |
| 시스템 프롬프트 | `system_prompt` | *(absent = built-in)* | only written when it differs from the built-in default |
| 기본 예시 포함 | `include_examples` | `true` | the 8 few-shot pairs; turn off for prompts of a different nature (e.g. translation) |
| 단축키 | `hotkey` | `right_option` | one of left/right × `option`, `command`, `control`, `shift` |
| 토글 녹음 | `toggle_enabled` | `true` | off = record only while held |
| 받아쓰기 기록 | `log_enabled` | `true` | see [Logs](#logs) |
| 로그인할 때 자동으로 시작 | *(not in the file)* | off | macOS login item (`SMAppService`); the system owns the state, so it also appears under System Settings › General › Login Items |

The system prompt is edited in place with a "기본값으로 되돌리기" (reset) button. The few-shot examples are viewable in Settings but live in code: `Sources/Untyped/Refine/RefinementPrompt.swift`.
</details>

## Logs

Each dictation appends raw and refined text to `~/Library/Application Support/Untyped/dictation.log` (mode 0600, rotated to `.1` at 5 MB). Open it from Settings → **로그 파일 보기…**.

```
[2026-09-11 22:10:33] 녹음 7.2초 · 다듬음
STT : 어 내일 아침에 회의 자료를 보내드릴게요 아니 오늘 저녁에 보내드릴게요
결과: 오늘 저녁에 회의 자료를 보내드릴게요.
```

Since it records everything you say, it can be turned off in Settings.

## Troubleshooting

The log marks fallbacks as `· 원본 (reason)`:

| Reason | Meaning | What to do |
|---|---|---|
| 다듬기 시간 초과 | server too slow | Free memory — under pressure macOS swaps the model out and the first token can take 3–30 s (observed: 29 s for 9 tokens on a 16 GB Mac with 17 GB of swap in use). Untyped pre-warms the server with a 1-token request when recording starts, but the first dictation after a long idle can still time out. Raising *다듬기 대기 시간* helps too. |
| 최대 토큰 초과 | long utterance | raise *최대 출력 토큰* |
| 다듬기 서버 오류 | server down, wrong URL or key | the menu also shows "연결할 수 없음" |

Prefix caching: the system message is sent byte-identical every request so the server's prefix cache can hit. oMLX caches in 512-token blocks — a prompt shorter than that is never cached, which is fine because it is also cheap to prefill.

## Architecture

<details>
<summary><b>Module layout</b></summary>

```
Sources/Untyped/
  App/        MenuBarApp.swift         MenuBarExtra + Settings scene
              SettingsView.swift       settings window
              OverlayPanel.swift       non-activating NSPanel — waveform, spinner, notices
              PermissionStatus.swift   mic / Accessibility checks
              LoginItem.swift          macOS login item (launch at login)
  Core/       DictationState.swift     state machine — pure function
              Coordinator.swift        the only place that wires components together
              AppConfig.swift          config.json read/write
              DictationLog.swift       dictation.log
  Input/      HotkeyKey.swift          the 8 standalone modifier keys and event matching
              HotkeyMonitor.swift      flagsChanged → TriggerEvent
              AudioCapture.swift       AVAudioEngine → audio stream + level
              AudioLevel.swift         RMS
              SystemAudioMuter.swift   mutes other apps' output while recording
  Transcribe/ Transcriber.swift        SpeechAnalyzer → String
  Refine/     TextRefiner.swift        protocol, fallback policy, timeout
              OpenAICompatibleRefiner.swift
              RefinementPrompt.swift   4 rules + glossary + 8 few-shot pairs
  Output/     TextInserter.swift       clipboard backup → ⌘V → restore
```

Dependencies point one way: `App → Core → { Input, Transcribe, Refine, Output }`. Leaf modules do not know each other; `Coordinator` knows all of them. The state machine (`reduce`) takes the clock as an argument, so it is tested deterministically. Requests use `temperature: 0`.
</details>

## Development

```sh
swift test
```

Covered: state-machine transitions, RMS, config round-trip / legacy-file compatibility / file permissions, hotkey matching, prompt composition, fallback policy, and that the transcriber does not hang on empty audio input. Audio capture, global key events, text insertion, the overlay and login-item registration depend on system permissions, hardware and the `.app` bundle and are verified by hand.

Design notes and measurements live in `docs/superpowers/specs/` (kept locally, not tracked).

## Contributing

Issues and pull requests are welcome. Conventions: no external SwiftPM dependencies; keep the one-way dependency direction above; commit messages follow `feat:` / `fix:` / `docs:` prefixes.

## License

[MIT](LICENSE)

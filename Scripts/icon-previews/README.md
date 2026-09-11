# Untyped 앱 아이콘

세 후보는 모두 1024×1024 sRGB PNG이며, 투명 여백과 딥 틸 스퀴클 배경을 공유합니다.

- `a-mic-cursor.png`: 마이크 받침이 텍스트 커서로 이어지는 형태.
- `b-speech-cursor.png` **최종안**: 말풍선 안의 I-beam 커서. 말하기와 텍스트 입력을 함께 표현하며, 작은 크기에서도 두 요소가 분리되어 보입니다.
- `c-untyped.png`: 코드 기호에 취소선. 이름의 말장난을 드러내지만 기능을 이해하려면 해석이 필요합니다.

## 재생성

저장소 루트에서 macOS와 Xcode Command Line Tools만으로 실행합니다.

```sh
./Scripts/render-icon.sh
./Scripts/bundle.sh
```

도형 원본은 `Scripts/render-icon.swift`입니다. 렌더 스크립트는 세 후보를 다시 그리고 최종 PNG를 `sips`로 축소한 뒤 `iconutil`로 `Resources/AppIcon.icns`를 만듭니다. 임시 iconset에는 16·32·128·256·512 포인트의 1×·2× 이미지가 포함됩니다. 번들 빌드는 저장된 ICNS를 사용하므로 아이콘을 바꿨을 때만 재생성이 필요합니다.

## 번들 확인

```sh
sips -g pixelWidth -g pixelHeight Resources/AppIcon.icns
plutil -p build/Untyped.app/Contents/Info.plist
cmp Resources/AppIcon.icns build/Untyped.app/Contents/Resources/AppIcon.icns
codesign -dv build/Untyped.app
codesign --verify --deep --strict build/Untyped.app
```

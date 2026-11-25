# ocfloat

Floating Chat for OpenCode.

A macOS menu bar app that summons a floating Quick Chat for opencode with a global hotkey.

## Development

Requires Xcode 27+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml` and not checked in.

```sh
xcodegen generate
open FloatingChat.xcodeproj
```

Command line build and test:

```sh
xcodebuild -project FloatingChat.xcodeproj -scheme FloatingChat -derivedDataPath build test
```

## License

[MIT](LICENSE)

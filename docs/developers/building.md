# Building and testing

## Requirements

- macOS 14 or later to run (the full Liquid Glass look needs macOS 26 or later; older versions get the same layout with plain materials).
- Xcode 26 or later (the code uses macOS 26 SDK APIs behind `#available`).
- `adb`: `brew install android-platform-tools`.
- `xcodegen` only to regenerate the project: `brew install xcodegen`, then `scripts/generate-project.sh` (it also keeps Xcode's build output in `build.noindex/`).
- No CocoaPods. Dependencies are Swift packages: grpc-swift, swift-protobuf and SwiftNIO (for the debug-app inspector).

## Build and run

```bash
./scripts/build-app.sh && open "build.noindex/Benz Mirror.app"   # release build, ad-hoc signed
open BenzMirror.xcodeproj                                        # or work in Xcode: ⌘R to run, ⌘U for the UI tests
./scripts/install-local.sh                                       # build and install to /Applications (waits for the old copy to quit)
```

## Tests

```bash
./scripts/test.sh                                                # unit tests of every package, one line per package
BENZMIRROR_TEST_SERIAL=<adb serial> ./scripts/test.sh            # plus the tests that use a real phone
BENZMIRROR_TEST_SERIAL=<serial> BENZMIRROR_TEST_DEBUG_APP=<package> swift test --filter AppInspectorLiveTests   # needs Android Studio and a running debug app
BENZMIRROR_SNAPSHOT_DIR=/some/folder swift test --filter ConnectTests   # also writes PNG snapshots of real views with fake data
```

Tests without the environment variables skip the phone tests. Some tests need `ffmpeg` for test video (`brew install ffmpeg`) and skip without it.

## Quality checks that run in the tests

- Every user-visible string used in code exists in `Resources/Localizable.xcstrings`.
- Every language offered in Settings has every string, with the same `%@` and `%lld` as English (`scripts/localize.py check` does the same from the command line).
- No two menu shortcuts share a key combination, and none uses a reserved one.

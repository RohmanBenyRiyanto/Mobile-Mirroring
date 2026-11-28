# Benz Mirror for developers

Everything here is for people who build, change or release the app. The main [README](../../README.md) is for users.

| Document | What is in it |
|---|---|
| [building.md](building.md) | Requirements, building, running, tests, the project generator |
| [architecture.md](architecture.md) | Code layout, how a session works, security rules, updating scrcpy |
| [release.md](release.md) | DMG, signing, GitHub workflows, the website, notices, translations |

The app is a Swift client for the scrcpy server (v5.0.1). Everything is Swift Package Manager; the Xcode project is a thin shell generated from `project.yml`.

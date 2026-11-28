# Releasing

## Version

`CFBundleShortVersionString` and `BenzReleaseChannel` (for example `"beta 1"`) live in `project.yml`; regenerate with `scripts/generate-project.sh`. The About screen shows `0.1.0 beta 1 (1)`. Tags look like `v0.1.0-beta.1`; a tag with a dash is published as a pre-release.

Add a section to `CHANGELOG.md` for every version (`## [0.1.0-beta.1]`): the website reads it.

## DMG

```bash
scripts/make-dmg.sh      # builds build.noindex/Benz-Mirror-<version>.dmg, ad-hoc signed
SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=<keychain profile> scripts/make-dmg.sh   # signed and notarized (needs an Apple Developer account)
```

Without notarization macOS asks users to allow the app once (System Settings → Privacy & Security → Open Anyway).

## GitHub workflows

| Workflow | Runs when | Does |
|---|---|---|
| `release.yml` | a `v*` tag is pushed, or by hand in the Actions tab | tests, builds the DMG, keeps it as an artifact, and for a tag publishes a GitHub release |
| `pages.yml` | `release/production` changes `website/**` or `CHANGELOG.md` | publishes `website/` to GitHub Pages |

`release.yml` uses a `macos-26` runner and picks the newest Xcode. Neither workflow runs for ordinary pushes to `release/development`.

Pages setup (once): Settings → Pages → Source **GitHub Actions**; Settings → Environments → `github-pages` → allow deployment from `release/production`.

## Website

`website/` is plain HTML, CSS and JavaScript with no build step. `website/assets/js/config.js` holds the repository, the DMG name and where the changelog is read from. Preview: `python3 -m http.server -d website 8000`. The site reads the latest release and `CHANGELOG.md` through GitHub's public API.

## Third-party notices

`scripts/make-notices.py` writes `Resources/THIRD-PARTY-NOTICES.txt` from `Packages/Core/Package.resolved` (run `swift package resolve` in `Packages/Core` first). Run it whenever the dependencies change.

## Translations

`Resources/Localizable.xcstrings` is the string catalog (English is the source). `Resources/InfoPlist.xcstrings` holds the permission text.

```bash
python3 scripts/localize.py export                 # numbered English strings
python3 scripts/localize.py apply <lang> file.tsv  # lines "N<TAB>translation"; refuses a changed %@ or %lld
python3 scripts/localize.py check                  # every language complete, placeholders intact
```

A new language also needs its code in `AppLanguage.supported`, `CFBundleLocalizations` (`project.yml`) and a native name in `AppLanguage.names`. The tests check that all of them agree.

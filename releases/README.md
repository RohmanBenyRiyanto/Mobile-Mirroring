# releases/

Optional second download source for the website. The preferred way is a GitHub Release
(push a tag such as `v0.1.0`).

To publish a DMG from this folder instead, name it with the version and commit it:

    cp "build.noindex/Benz-Mirror.dmg" releases/Benz-Mirror-0.1.0.dmg
    (cd releases && shasum -a 256 Benz-Mirror-0.1.0.dmg > Benz-Mirror-0.1.0.dmg.sha256)

GitHub refuses files over 100 MB, and every DMG committed here stays in the git history.

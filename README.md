# PreviewChat

macOS menu bar app: chat with the PDF open in Preview, powered by the [Claude Code](https://claude.com/claude-code) CLI.

## Requirements
- macOS 26+, Apple Silicon
- `claude` CLI installed and logged in (uses your Claude subscription)

## Install
1. Download `PreviewChat-<version>.dmg` from [Releases](../../releases/latest).
2. Open it, drag **PreviewChat** to **Applications**.
3. First launch: the build is not notarized, so macOS blocks it. Open it once, then
   **System Settings → Privacy & Security → Open Anyway**.
4. Allow the prompts: **Automation → Preview** (find the open PDF) and **Accessibility** (current page number).

Verify the download (optional): `shasum -a 256 -c PreviewChat-<version>.dmg.sha256`

## Usage
Open a PDF in Preview, click the menu bar icon, ask away.
- Return: send · Shift+Return: newline · ⌘N: new chat

## Build from source
```sh
./build.sh      # → build/PreviewChat.app
./release.sh    # → dist/PreviewChat-<version>.dmg (+ .sha256)
```
Needs Swift 6 toolchain (Command Line Tools is enough).

## Releasing
1. Bump `CFBundleShortVersionString` (semver) and `CFBundleVersion` (+1) in `Info.plist`.
2. Add an entry to `CHANGELOG.md`; commit.
3. `./release.sh`, smoke-test the DMG.
4. `git tag vX.Y.Z && git push --tags`
5. `gh release create vX.Y.Z dist/PreviewChat-X.Y.Z.dmg* --notes-file <notes>`

With a Developer ID cert: `NOTARY_PROFILE=<profile> ./release.sh` signs, notarizes and staples so Gatekeeper opens it without warnings.

---
name: launch-release-on-github
description: Create a GitHub release from matching successful Windows, macOS, and Linux CI runs, packaging Windows builds as RAR and attaching the unchanged macOS Apple Archive and Linux tar.xz artifacts with user-facing notes and fixed install notes. Use when releasing on GitHub, assembling multi-platform release assets, tagging a version, or /launch-release-on-github.
---

# Launch Release On GitHub

Publish a GitHub Release from one pushed commit. Attach five platform assets:

- Windows `x86_64` and `arm64` as flat `.rar` archives.
- macOS as one universal `x86_64 + arm64` Apple Archive (`.aar`) copied
  unchanged from CI.
- Linux `x86_64` and `arm64` as separate `.tar.xz` archives.

Write user-facing release notes ending with the fixed Install Notes block below.

## Inputs

Ask only if missing:

| Input | Default |
|---|---|
| Version (for example `3.2.0`) | Required |
| Commit | Pushed `main` HEAD |
| Previous tag | Latest existing release |

Follow the repository's existing tag style (`3.2.0`, not `v3.2.0`). Confirm that the selected commit is present on the
remote before continuing.

## Workflow

Run the assembly on macOS with `gh`, `rar`, `aa`, `lipo`, `tar`, and `file`
available on `PATH`.

### 1. Match every CI run to the release commit

Find the Windows, macOS, and Linux workflow runs whose `headSha` exactly equals
the release commit:

```bash
gh run list --workflow windows.yml --commit <sha> \
  --json databaseId,headSha,status,conclusion,url
gh run list --workflow mac.yml --commit <sha> \
  --json databaseId,headSha,status,conclusion,url
gh run list --workflow linux.yml --commit <sha> \
  --json databaseId,headSha,status,conclusion,url
```

For each workflow:

- If the matching run is still running, wait with
  `gh run watch <run-id> --exit-status`.
- If it failed, has a different SHA, or lacks an expected architecture, stop.
- Never substitute an older successful build.

Download the three successful runs into separate directories:

```bash
release_dir="$(mktemp -d "/tmp/rigol2spice-release-<ver>.XXXXXX")"
mkdir -p "$release_dir/windows" "$release_dir/macos" "$release_dir/linux"
gh run download <windows-run-id> --dir "$release_dir/windows"
gh run download <macos-run-id> --dir "$release_dir/macos"
gh run download <linux-run-id> --dir "$release_dir/linux"
```

Expect these downloaded artifact directories:

```text
windows/rigol2spice-windows-x86_64/
windows/rigol2spice-windows-arm64/
macos/rigol2spice-macos-universal/rigol2spice-macos-universal.aar
linux/rigol2spice-linux-x86_64/rigol2spice-linux-x86_64.tar.xz
linux/rigol2spice-linux-arm64/rigol2spice-linux-arm64.tar.xz
```

Stop if an expected artifact is absent or if more than one candidate file
matches an expected asset.

### 2. Package Windows as RAR

Create flat archives with files at the archive root and no parent directory.
Require `rar` on `PATH` (Homebrew cask on macOS). If Gatekeeper blocks it, run
`xattr -cr` on the cask folder; never upload a ZIP instead.

```bash
mkdir -p "$release_dir/assets"
cd "$release_dir/windows/rigol2spice-windows-x86_64"
rar a -m5 "$release_dir/assets/rigol2spice-windows-x86_64.rar" *
cd "$release_dir/windows/rigol2spice-windows-arm64"
rar a -m5 "$release_dir/assets/rigol2spice-windows-arm64.rar" *
```

Each Windows archive must contain `rigol2spice.exe` and its bundled runtime
DLLs.

### 3. Validate and collect the macOS asset

Copy the native `.aar` from the matching CI artifact unchanged. Do not sign,
rebuild, recompress, or wrap it in the ZIP downloaded from GitHub Actions.

```bash
cp "$release_dir/macos/rigol2spice-macos-universal/rigol2spice-macos-universal.aar" \
  "$release_dir/assets/"
```

Extract the copied archive into a fresh directory. Require exactly one
executable named `rigol2spice`, verify both slices, and exercise its help:

```bash
mkdir -p "$release_dir/verify-macos"
aa extract \
  -i "$release_dir/assets/rigol2spice-macos-universal.aar" \
  -d "$release_dir/verify-macos"
test -x "$release_dir/verify-macos/rigol2spice"
lipo -archs "$release_dir/verify-macos/rigol2spice"
"$release_dir/verify-macos/rigol2spice" --help >/dev/null
```

The `lipo` output must include both `x86_64` and `arm64`, and the executable
must retain its executable permission. Stop if extraction produces any other
file or directory.

### 4. Validate and collect Linux assets

Copy the native CI archives unchanged; do not recompress them or wrap them in
the ZIP downloaded from GitHub Actions.

```bash
cp "$release_dir/linux/rigol2spice-linux-x86_64/rigol2spice-linux-x86_64.tar.xz" \
  "$release_dir/assets/"
cp "$release_dir/linux/rigol2spice-linux-arm64/rigol2spice-linux-arm64.tar.xz" \
  "$release_dir/assets/"
```

Extract each Linux archive into its own fresh directory. Require exactly one
executable named `rigol2spice`; use `file` to confirm `x86-64` for the
`x86_64` archive and `ARM aarch64` for the `arm64` archive.

```bash
mkdir -p "$release_dir/verify-linux-x86_64" "$release_dir/verify-linux-arm64"
tar -C "$release_dir/verify-linux-x86_64" -xJf \
  "$release_dir/assets/rigol2spice-linux-x86_64.tar.xz"
tar -C "$release_dir/verify-linux-arm64" -xJf \
  "$release_dir/assets/rigol2spice-linux-arm64.tar.xz"
file "$release_dir/verify-linux-x86_64/rigol2spice"
file "$release_dir/verify-linux-arm64/rigol2spice"
```

### 5. Write release notes

Write `$release_dir/NOTES.md`.

Describe only user-visible changes and include CLI examples when useful. Use
`git log <previous-tag>..<sha>`, the README, and CLI help as sources. Omit pure
refactors and internal implementation details.

Always end with this exact Install Notes block:

```markdown
---

## Install Notes
| OS  |   |
|---|---|
| Windows | <ul> <li> Windows doesn't support the `.rar` file format natively. Install [7-zip](https://www.7-zip.org/) or [WinRAR](https://www.win-rar.com/) to open it. <li> If Windows complains about missing **MSVCP140.DLL**, [install the Visual C++ 2015 Redistributable from Microsoft](https://docs.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170). </ul> |
| macOS | <ul> <li> Open `rigol2spice-macos-universal.aar` with macOS Archive Utility. <li> If macOS blocks the executable, remove its quarantine attributes with: `xattr -cr /path/to/rigol2spice` </ul> |
| Linux | <ul><li> Choose the archive matching your CPU (`x86_64` or `arm64`) and extract it with `tar -xJf rigol2spice-linux-<architecture>.tar.xz`. <li>The Swift runtime is included in the executable and does not need to be installed separately. </ul> |
```

### 6. Tag and create the release

Stop and ask before overwriting if the tag or release already exists.

```bash
git tag -a <ver> -m "<ver>" <sha>
git push origin <ver>
gh release create <ver> --title "<ver>" \
  --notes-file "$release_dir/NOTES.md" \
  "$release_dir/assets/rigol2spice-windows-x86_64.rar" \
  "$release_dir/assets/rigol2spice-windows-arm64.rar" \
  "$release_dir/assets/rigol2spice-macos-universal.aar" \
  "$release_dir/assets/rigol2spice-linux-x86_64.tar.xz" \
  "$release_dir/assets/rigol2spice-linux-arm64.tar.xz"
```

Confirm all five assets with `gh release view <ver>`, then return the release
URL to the user.

## Hard rules

- Release exactly five assets: two Windows `.rar`, one macOS `.aar`, and two
  Linux `.tar.xz` files.
- Never upload GitHub Actions ZIP wrappers.
- Copy macOS and Linux archives byte-for-byte from their matching CI artifacts.
- Never sign, rebuild, or recompress the macOS executable or `.aar` locally.
- Require `x86_64` and `arm64` for Windows and Linux, and both slices in the
  universal macOS executable.
- Require every workflow run and the tag to use the same commit SHA.
- Keep the Install Notes block exactly as written above.
- Stop and ask before overwriting an existing tag or release.
- Stop and ask before shipping with any missing platform or architecture.

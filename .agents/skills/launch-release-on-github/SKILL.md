---
name: launch-release-on-github
description: >
  Create a GitHub release with Windows CI binaries as RAR, user-facing notes,
  and install notes. Use when releasing on GitHub, packaging Windows builds as
  rar, tagging a version, or /launch-release-on-github.
metadata:
  short-description: "GitHub release with Windows RAR builds"
---

# Launch Release On GitHub

Publish a GitHub Release: tag a commit, attach Windows CI binaries as **`.rar`**
(not zip), and write user-facing notes with fixed Install Notes.

## Inputs

Ask only if missing:

| Input | Default |
|---|---|
| Version (e.g. `3.2.0`) | — required |
| Commit | pushed `main` HEAD |
| Previous tag | latest existing release (for changelog) |

Tag style follows existing tags (`3.2.0`, not `v3.2.0`, unless the repo uses `v`).

## Workflow

### 1. Match CI to the commit

- Find the successful Windows workflow run whose SHA equals the release commit.
- If still running: wait (`gh run watch <id> --exit-status`).
- If failed or SHA mismatch: **stop** — do not package an older build.

```bash
gh run download <run-id> --dir /tmp/rel-<ver>
```

Expect folders like `rigol2spice-windows-x86_64/` and `rigol2spice-windows-arm64/`
(binary + bundled DLLs). Adjust names if CI differs.

### 2. Pack as RAR

Flat archives (files at archive root, no parent folder). Requires `rar` on PATH
(Homebrew cask). If Gatekeeper kills it: `xattr -cr` on the cask folder — never
upload zip instead.

```bash
cd /tmp/rel-<ver>
(cd rigol2spice-windows-x86_64 && rar a -m5 ../rigol2spice-windows-x86_64.rar *)
(cd rigol2spice-windows-arm64  && rar a -m5 ../rigol2spice-windows-arm64.rar  *)
```

### 3. Release notes

Write `/tmp/rel-<ver>/NOTES.md`.

**Body:** section `## What changes for you`, then short `###` subsections.
User-facing only — what they can do, with CLI examples when useful.
Source: `git log <prev-tag>..HEAD` + README/CLI; skip pure refactors.

**Always end with this exact Install Notes block:**

```markdown
---

## Install Notes

* Windows doesn't support the `.rar` file format natively. You must install third party software to open it like [7-zip](https://www.7-zip.org/) or [WinRAR](https://www.win-rar.com/)
* If Windows complains about **MSVCP140.DLL**, [please install the latest X64 Visual C++ 2015 Redistributable from Microsoft](https://docs.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170).
```

### 4. Tag and release

```bash
git tag -a <ver> -m "<ver>" <sha> && git push origin <ver>
gh release create <ver> --title "<ver>" --notes-file /tmp/rel-<ver>/NOTES.md \
  /tmp/rel-<ver>/rigol2spice-windows-x86_64.rar \
  /tmp/rel-<ver>/rigol2spice-windows-arm64.rar
```

Confirm with `gh release view <ver>`, then give the user the release URL.

## Hard rules

- Assets = **only** the `.rar` files (never CI zip artifacts)
- Install Notes text = exactly the block above (do not invent variants)
- Tag SHA = same commit CI built
- Existing tag/release → stop and ask before overwriting
- One arch only → ask before shipping

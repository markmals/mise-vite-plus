# Mise Plugin for Vite+ — Design Spec

## Overview

A vfox-based Lua plugin for Mise that installs and manages Vite+ (the Unified Toolchain for the Web). The plugin replicates the behavior of the official Vite+ installer scripts (`https://vite.plus` for Unix, `https://vite.plus/ps1` for Windows) as a native Mise plugin, so the result is the same regardless of how the user installs Vite+.

## Plugin Structure

```
mise-vite-plus/
├── metadata.lua              # Plugin metadata
├── hooks/
│   ├── available.lua         # List versions from npm registry
│   ├── pre_install.lua       # Return platform-specific tarball URL
│   ├── post_install.lua      # Place binaries, bootstrap JS deps, create symlinks
│   └── env_keys.lua          # Expose bin/ on PATH
├── lib/
│   └── platform.lua          # Shared platform detection helper
├── types/
│   └── mise-plugin.lua       # LuaCATS type definitions (existing)
├── mise-tasks/test           # Integration test script
└── .github/workflows/ci.yml  # CI pipeline (existing)
```

## metadata.lua

```lua
PLUGIN = {
    name = "vite-plus",
    version = "1.0.0",
    description = "Vite+ - Unified Toolchain for the Web",
    author = "markmals",
    updateUrl = "https://github.com/markmals/mise-vite-plus",
}
```

No `legacyFilenames` — Vite+ does not use legacy version files.

## lib/platform.lua

Centralized helper mapping Mise's `RUNTIME` object to Vite+'s npm package naming convention.

### Platform mapping

| RUNTIME.osType | RUNTIME.archType | RUNTIME.envType | npm package suffix     |
| -------------- | ---------------- | --------------- | ---------------------- |
| Darwin         | arm64            | nil             | `darwin-arm64`         |
| Darwin         | amd64            | nil             | `darwin-x64`           |
| Linux          | amd64            | gnu             | `linux-x64-gnu`        |
| Linux          | arm64            | gnu             | `linux-arm64-gnu`      |
| Linux          | amd64            | musl            | `linux-x64-musl`       |
| Linux          | arm64            | musl            | `linux-arm64-musl`     |
| Windows        | amd64            | nil             | `win32-x64-msvc`       |
| Windows        | arm64            | nil             | `win32-arm64-msvc`     |

### Mapping rules

- `amd64` maps to `x64` (npm convention).
- `Darwin` maps to `darwin`, `Linux` to `linux`, `Windows` to `win32`.
- Linux appends libc type (`-gnu` or `-musl`). Defaults to `gnu` if `RUNTIME.envType` is nil.
- Windows always appends `-msvc`.
- Errors on unsupported OS/arch combinations.

### Exported functions

- `platform.suffix()` — full suffix, e.g. `darwin-arm64` or `win32-x64-msvc`
- `platform.package_name()` — e.g. `@voidzero-dev/vite-plus-cli-darwin-arm64`
- `platform.tarball_url(version)` — full npm registry tarball URL
- `platform.binary_name()` — `"vp.exe"` on Windows, `"vp"` otherwise

## hooks/available.lua

### Flow

1. `GET https://registry.npmjs.org/vite-plus` — fetch full package metadata.
2. Parse JSON, iterate over `versions` object keys.
3. Sort by semver using `semver.sort_by(versions, "version")` (oldest first, newest last).
4. Return list of `{version = "x.y.z"}` entries.

### Details

- Uses `http.get()` and `json.decode()` from Mise's built-in Lua modules.
- No `note` field — Vite+ does not distinguish LTS/pre-release.
- No `rolling` versions — Vite+ uses fixed semver releases.
- Errors with descriptive messages on HTTP failure or parse failure.

## hooks/pre_install.lua

### Flow

1. Receive `ctx.version` (already resolved by Mise).
2. Use `lib/platform.lua` to build the tarball URL.
3. Return `{version = version, url = url}`.

### Details

- No checksum verification for now — the npm registry does not provide standalone sha256 per tarball, and the official installer does not verify checksums either. HTTPS provides transport security.
- Mise downloads the tarball and extracts it automatically.

### Return value

```lua
{
    version = version,
    url = "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-<suffix>/-/vite-plus-cli-<suffix>-<version>.tgz",
}
```

## hooks/post_install.lua

The most involved hook. After Mise downloads and extracts the npm tarball, PostInstall handles Vite+-specific setup.

### Flow

1. **Locate the extracted binary.** npm tarballs extract with a `package/` prefix. The binary is at `<path>/package/vp` (or `<path>/vp` if Mise strips the prefix). Check both locations.
2. **Create `bin/` directory.** `mkdir -p <path>/bin`
3. **Move binary into `bin/`.** Move to `<path>/bin/vp` and `chmod +x` on Unix.
4. **Create multicall symlinks.** `ln -sf vp <path>/bin/vpx` and `ln -sf vp <path>/bin/vpr`. On Windows, copy the binary instead of symlinking.
5. **Write `package.json`.** Wrapper declaring `vite-plus` as a dependency:
   ```json
   {
     "name": "vp-global",
     "version": "<version>",
     "private": true,
     "dependencies": { "vite-plus": "<version>" }
   }
   ```
6. **Write `.npmrc`.** Contains `minimum-release-age=0` and `min-release-age=0` to bypass publish delays (matches official installer).
7. **Run `vp install --silent`.** Bootstraps JS dependencies. Run with `CI=true` env to suppress prompts. Working directory is the install path.
8. **Create `~/.vite-plus/current` symlink.** Points to `ctx.sdkInfo[PLUGIN.name].path` (the version-specific install directory under Mise, e.g. `~/.local/share/mise/installs/vite-plus/0.1.15/`), matching Homebrew formula behavior. Create `~/.vite-plus/` directory if it doesn't exist. On Windows, use a junction (`cmd /c mklink /J`).
9. **Run `vp env setup --env-only`.** Creates env/shim files in `~/.vite-plus/`. This is required for Vite+ to function properly.

### Error handling

- Error if the binary is not found after extraction.
- Error if `vp install --silent` fails (include log output).
- Warn (don't error) if `vp env setup` fails — non-critical for basic operation.

### Windows considerations

- Binary name is `vp.exe`.
- Copy `vp-shim.exe` if present in the extracted package.
- Use file copy instead of symlinks for `vpx`/`vpr`.
- Use `cmd /c mklink /J` for the `~/.vite-plus/current` junction.

## hooks/env_keys.lua

Minimal — expose the `bin/` directory on PATH:

```lua
return {
    { key = "PATH", value = mainPath .. "/bin" }
}
```

No additional env vars needed. Mise handles version switching.

## What the plugin does NOT do

These responsibilities belong to Mise or are unnecessary in this context:

- **Shell config modification** — Mise handles PATH via `EnvKeys`.
- **Node.js manager setup** — Mise users manage Node via Mise itself.
- **Version cleanup** — Mise manages installed versions.
- **Version switching** — Mise handles this natively.

## Testing

### mise-tasks/test

1. `mise plugin link --force vite-plus .` — link the local plugin.
2. `mise cache clear` — ensure clean state.
3. `mise install vite-plus@0.1.15` — install a known version.
4. `mise exec "vite-plus@0.1.15" -- vp --version` — verify the binary runs.
5. Assert output contains the version string.
6. Verify `vpx --help` and `vpr --help` also work.

### CI

The existing `.github/workflows/ci.yml` runs `mise run ci` on `ubuntu-latest` and `macos-latest`. No Windows CI for now.

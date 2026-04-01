# Mise Vite+ Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a Mise tool plugin that installs and manages Vite+ via platform-specific npm tarballs, replicating the official installer behavior.

**Architecture:** Standard vfox plugin with 4 hooks (Available, PreInstall, PostInstall, EnvKeys) and a shared `lib/platform.lua` helper. PreInstall returns a tarball URL for Mise to download; PostInstall places binaries, bootstraps JS dependencies, and creates the `~/.vite-plus/current` symlink.

**Tech Stack:** Lua 5.1, Mise vfox plugin API, npm registry API, built-in Mise Lua modules (http, json, semver, file)

**Spec:** `docs/superpowers/specs/2026-04-01-mise-vite-plus-plugin-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `metadata.lua` | Modify | Plugin name, version, author, description |
| `lib/platform.lua` | Create | Platform detection: OS, arch, libc → npm package suffix and URL |
| `hooks/available.lua` | Modify | Fetch all versions from npm registry, return sorted list |
| `hooks/pre_install.lua` | Modify | Return platform-specific tarball URL for a given version |
| `hooks/post_install.lua` | Modify | Place binary, create symlinks, write package.json, bootstrap JS deps |
| `hooks/env_keys.lua` | Modify | Expose `bin/` on PATH |
| `.luarc.json` | Modify | Add `lib` to workspace library for IDE support |
| `mise-tasks/test` | Modify | Integration test for the plugin |

---

### Task 1: metadata.lua

**Files:**
- Modify: `metadata.lua`

- [ ] **Step 1: Update metadata.lua with Vite+ plugin info**

Replace the full contents of `metadata.lua` with:

```lua
-- metadata.lua
-- Plugin metadata and configuration
-- Documentation: https://mise.jdx.dev/tool-plugin-development.html#metadata-lua

PLUGIN = { -- luacheck: ignore
    -- Required: Tool name (lowercase, no spaces)
    name = "vite-plus",

    -- Required: Plugin version (not the tool version)
    version = "1.0.0",

    -- Required: Brief description of the tool
    description = "Vite+ - Unified Toolchain for the Web",

    -- Required: Plugin author/maintainer
    author = "markmals",

    -- Optional: Repository URL for plugin updates
    updateUrl = "https://github.com/markmals/mise-vite-plus",

    -- Optional: Minimum mise runtime version required
    minRuntimeVersion = "0.2.0",
}
```

- [ ] **Step 2: Commit**

```bash
git add metadata.lua
git commit -m "feat: configure metadata for vite-plus plugin"
```

---

### Task 2: lib/platform.lua

**Files:**
- Create: `lib/platform.lua`
- Modify: `.luarc.json`

- [ ] **Step 1: Create lib/platform.lua**

Create the `lib/` directory and write `lib/platform.lua`:

```lua
--- Platform detection helper for Vite+ npm packages.
--- Maps Mise's RUNTIME object to Vite+'s npm package naming convention.
---
--- npm packages follow the pattern:
---   @voidzero-dev/vite-plus-cli-<suffix>
--- where suffix is e.g. "darwin-arm64", "linux-x64-gnu", "win32-x64-msvc"

local M = {}

--- Returns the OS token used in npm package names.
--- @return string os_token e.g. "darwin", "linux", "win32"
local function os_token()
    local os_type = RUNTIME.osType
    if os_type == "Darwin" then
        return "darwin"
    elseif os_type == "Linux" then
        return "linux"
    elseif os_type == "Windows" then
        return "win32"
    end
    error("Unsupported operating system: " .. tostring(os_type))
end

--- Returns the architecture token used in npm package names.
--- @return string arch_token e.g. "arm64", "x64"
local function arch_token()
    local arch = RUNTIME.archType
    if arch == "arm64" then
        return "arm64"
    elseif arch == "amd64" then
        return "x64"
    end
    error("Unsupported architecture: " .. tostring(arch))
end

--- Returns the full platform suffix for the npm package name.
--- e.g. "darwin-arm64", "linux-x64-gnu", "win32-x64-msvc"
--- @return string suffix
function M.suffix()
    local os = os_token()
    local arch = arch_token()

    if os == "linux" then
        local libc = RUNTIME.envType or "gnu"
        return os .. "-" .. arch .. "-" .. libc
    elseif os == "win32" then
        return os .. "-" .. arch .. "-msvc"
    else
        return os .. "-" .. arch
    end
end

--- Returns the scoped npm package name for the CLI binary.
--- e.g. "@voidzero-dev/vite-plus-cli-darwin-arm64"
--- @return string package_name
function M.package_name()
    return "@voidzero-dev/vite-plus-cli-" .. M.suffix()
end

--- Returns the full npm registry tarball URL for a given version.
--- @param version string e.g. "0.1.15"
--- @return string url
function M.tarball_url(version)
    local suffix = M.suffix()
    return "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-"
        .. suffix
        .. "/-/vite-plus-cli-"
        .. suffix
        .. "-"
        .. version
        .. ".tgz"
end

--- Returns the binary filename for the current platform.
--- @return string binary_name "vp.exe" on Windows, "vp" otherwise
function M.binary_name()
    if RUNTIME.osType == "Windows" then
        return "vp.exe"
    end
    return "vp"
end

return M
```

- [ ] **Step 2: Add lib to .luarc.json workspace library**

The current `.luarc.json` has `"library": ["types"]`. Add `"lib"` so the language server can resolve `require("platform")`:

Change `.luarc.json` to:

```json
{
  "$schema": "https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json",
  "runtime": {
    "version": "Lua 5.1"
  },
  "diagnostics": {
    "disable": ["duplicate-set-field"]
  },
  "workspace": {
    "checkThirdParty": false,
    "library": ["types", "lib"]
  }
}
```

- [ ] **Step 3: Commit**

```bash
git add lib/platform.lua .luarc.json
git commit -m "feat: add platform detection helper for npm package mapping"
```

---

### Task 3: hooks/available.lua

**Files:**
- Modify: `hooks/available.lua`

- [ ] **Step 1: Implement Available hook**

Replace the full contents of `hooks/available.lua` with:

```lua
--- Returns a list of available Vite+ versions from the npm registry.
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook
--- @param ctx AvailableCtx
--- @return AvailableVersion[]
function PLUGIN:Available(ctx) -- luacheck: ignore 212
    local http = require("http")
    local json = require("json")
    local semver = require("semver")

    local resp, err = http.get({
        url = "https://registry.npmjs.org/vite-plus",
    })

    if err ~= nil then
        error("Failed to fetch Vite+ versions from npm: " .. err)
    end
    if resp.status_code ~= 200 then
        error("npm registry returned status " .. resp.status_code .. ": " .. resp.body)
    end

    local pkg = json.decode(resp.body)
    if not pkg.versions then
        error("Unexpected npm registry response: missing 'versions' field")
    end

    local result = {}
    for version, _ in pairs(pkg.versions) do
        table.insert(result, { version = version })
    end

    return semver.sort_by(result, "version")
end
```

- [ ] **Step 2: Verify the hook works**

Run:

```bash
mise plugin link --force vite-plus .
mise ls-remote vite-plus
```

Expected: A list of semver versions printed to stdout (e.g. `0.0.1`, `0.0.2`, ... `0.1.15`).

- [ ] **Step 3: Commit**

```bash
git add hooks/available.lua
git commit -m "feat: implement Available hook to list versions from npm"
```

---

### Task 4: hooks/pre_install.lua

**Files:**
- Modify: `hooks/pre_install.lua`

- [ ] **Step 1: Implement PreInstall hook**

Replace the full contents of `hooks/pre_install.lua` with:

```lua
--- Returns download information for a specific Vite+ version.
--- Mise will download and extract the tarball automatically.
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#preinstall-hook
--- @param ctx PreInstallCtx
--- @return PreInstallResult
function PLUGIN:PreInstall(ctx)
    local platform = require("platform")
    local version = ctx.version

    return {
        version = version,
        url = platform.tarball_url(version),
    }
end
```

- [ ] **Step 2: Commit**

```bash
git add hooks/pre_install.lua
git commit -m "feat: implement PreInstall hook to return platform tarball URL"
```

---

### Task 5: hooks/post_install.lua

**Files:**
- Modify: `hooks/post_install.lua`

This is the most involved hook. It handles binary placement, multicall symlinks, package.json, JS bootstrap, and the `~/.vite-plus/current` symlink.

- [ ] **Step 1: Implement PostInstall hook**

Replace the full contents of `hooks/post_install.lua` with:

```lua
--- Performs additional setup after Mise downloads and extracts the Vite+ tarball.
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#postinstall-hook
--- @param ctx PostInstallCtx
function PLUGIN:PostInstall(ctx)
    local platform = require("platform")
    local file = require("file")

    local sdkInfo = ctx.sdkInfo[PLUGIN.name]
    local path = sdkInfo.path
    local version = sdkInfo.version
    local binary = platform.binary_name()
    local is_windows = RUNTIME.osType == "Windows"

    -- Step 1: Locate the extracted binary.
    -- npm tarballs extract with a package/ prefix. Check both locations
    -- in case Mise strips the prefix.
    local src_binary
    local package_path = file.join_path(path, "package", binary)
    local direct_path = file.join_path(path, binary)
    if file.exists(package_path) then
        src_binary = package_path
    elseif file.exists(direct_path) then
        src_binary = direct_path
    else
        error("Could not find " .. binary .. " in extracted tarball at " .. path)
    end

    -- Step 2: Create bin/ directory
    local bin_dir = file.join_path(path, "bin")
    os.execute('mkdir -p "' .. bin_dir .. '"')

    -- Step 3: Move binary into bin/ and make executable
    local dest_binary = file.join_path(bin_dir, binary)
    local mv_result = os.execute('mv "' .. src_binary .. '" "' .. dest_binary .. '"')
    if mv_result ~= 0 then
        error("Failed to move " .. binary .. " to " .. dest_binary)
    end
    if not is_windows then
        os.execute('chmod +x "' .. dest_binary .. '"')
    end

    -- On Windows, also copy vp-shim.exe if present
    if is_windows then
        local shim_src = file.join_path(path, "package", "vp-shim.exe")
        if not file.exists(shim_src) then
            shim_src = file.join_path(path, "vp-shim.exe")
        end
        if file.exists(shim_src) then
            os.execute('copy "' .. shim_src .. '" "' .. file.join_path(bin_dir, "vp-shim.exe") .. '"')
        end
    end

    -- Step 4: Create multicall symlinks (vpx, vpr)
    if is_windows then
        local vpx_dest = file.join_path(bin_dir, "vpx.exe")
        local vpr_dest = file.join_path(bin_dir, "vpr.exe")
        os.execute('copy "' .. dest_binary .. '" "' .. vpx_dest .. '"')
        os.execute('copy "' .. dest_binary .. '" "' .. vpr_dest .. '"')
    else
        os.execute('ln -sf vp "' .. file.join_path(bin_dir, "vpx") .. '"')
        os.execute('ln -sf vp "' .. file.join_path(bin_dir, "vpr") .. '"')
    end

    -- Step 5: Write wrapper package.json
    local pkg_json = '{\n'
        .. '  "name": "vp-global",\n'
        .. '  "version": "' .. version .. '",\n'
        .. '  "private": true,\n'
        .. '  "dependencies": {\n'
        .. '    "vite-plus": "' .. version .. '"\n'
        .. '  }\n'
        .. '}\n'
    local pkg_file = assert(io.open(file.join_path(path, "package.json"), "w"))
    pkg_file:write(pkg_json)
    pkg_file:close()

    -- Step 6: Write .npmrc to bypass publish delay restrictions
    local npmrc_file = assert(io.open(file.join_path(path, ".npmrc"), "w"))
    npmrc_file:write("minimum-release-age=0\nmin-release-age=0\n")
    npmrc_file:close()

    -- Step 7: Run vp install --silent to bootstrap JS dependencies
    local install_log = file.join_path(path, "install.log")
    local install_cmd = 'cd "' .. path .. '" && CI=true "' .. dest_binary .. '" install --silent > "' .. install_log .. '" 2>&1'
    if is_windows then
        install_cmd = 'cd /d "' .. path .. '" && set CI=true && "' .. dest_binary .. '" install --silent > "' .. install_log .. '" 2>&1'
    end
    local install_result = os.execute(install_cmd)
    if install_result ~= 0 then
        local log_content = ""
        local log_fh = io.open(install_log, "r")
        if log_fh then
            log_content = log_fh:read("*a")
            log_fh:close()
        end
        error("Failed to install Vite+ JS dependencies. Log:\n" .. log_content)
    end

    -- Step 8: Create ~/.vite-plus/current symlink
    local home = os.getenv("HOME") or os.getenv("USERPROFILE")
    local vp_home = file.join_path(home, ".vite-plus")
    os.execute('mkdir -p "' .. vp_home .. '"')
    local current_link = file.join_path(vp_home, "current")
    if is_windows then
        os.execute('cmd /c rmdir "' .. current_link .. '" 2>nul')
        os.execute('cmd /c mklink /J "' .. current_link .. '" "' .. path .. '"')
    else
        os.execute('ln -sfn "' .. path .. '" "' .. current_link .. '"')
    end

    -- Step 9: Run vp env setup --env-only
    local env_cmd = '"' .. dest_binary .. '" env setup --env-only > /dev/null 2>&1'
    if is_windows then
        env_cmd = '"' .. dest_binary .. '" env setup --env-only > nul 2>&1'
    end
    local env_result = os.execute(env_cmd)
    if env_result ~= 0 then
        -- Warn but don't error — env setup is non-critical for basic operation
        io.stderr:write("warn: vp env setup --env-only failed (exit code " .. tostring(env_result) .. ")\n")
    end

    -- Clean up extracted package/ directory if it still exists
    local package_dir = file.join_path(path, "package")
    if file.exists(package_dir) then
        os.execute('rm -rf "' .. package_dir .. '"')
    end
end
```

- [ ] **Step 2: Commit**

```bash
git add hooks/post_install.lua
git commit -m "feat: implement PostInstall hook with binary setup, JS bootstrap, and symlinks"
```

---

### Task 6: hooks/env_keys.lua

**Files:**
- Modify: `hooks/env_keys.lua`

- [ ] **Step 1: Implement EnvKeys hook**

Replace the full contents of `hooks/env_keys.lua` with:

```lua
--- Configures environment variables for the installed Vite+ version.
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#envkeys-hook
--- @param ctx EnvKeysCtx
--- @return EnvKey[]
function PLUGIN:EnvKeys(ctx)
    local mainPath = ctx.path

    return {
        {
            key = "PATH",
            value = mainPath .. "/bin",
        },
    }
end
```

- [ ] **Step 2: Commit**

```bash
git add hooks/env_keys.lua
git commit -m "feat: implement EnvKeys hook to expose bin/ on PATH"
```

---

### Task 7: Integration Test

**Files:**
- Modify: `mise-tasks/test`

- [ ] **Step 1: Update the test script**

Replace the full contents of `mise-tasks/test` with:

```bash
#!/usr/bin/env bash
#MISE description="Run plugin tests - install and execute vite-plus"
set -euo pipefail

echo "=== Linking plugin ==="
mise plugin link --force vite-plus .
mise cache clear

echo "=== Installing vite-plus@0.1.15 ==="
mise install vite-plus@0.1.15

echo "=== Testing vp --version ==="
output=$(mise exec "vite-plus@0.1.15" -- vp --version)
echo "vp output: $output"

if echo "$output" | grep -q '0.1.15'; then
    echo "✓ vp --version passed"
else
    echo "✗ vp --version failed: expected 0.1.15 in output"
    exit 1
fi

echo "=== Testing vpx --help ==="
vpx_output=$(mise exec "vite-plus@0.1.15" -- vpx --help 2>&1 || true)
echo "vpx output: $vpx_output"

if echo "$vpx_output" | grep -qi 'usage\|vpx\|vite'; then
    echo "✓ vpx --help passed"
else
    echo "✗ vpx --help failed: unexpected output"
    exit 1
fi

echo "=== Testing vpr --help ==="
vpr_output=$(mise exec "vite-plus@0.1.15" -- vpr --help 2>&1 || true)
echo "vpr output: $vpr_output"

if echo "$vpr_output" | grep -qi 'usage\|vpr\|vite'; then
    echo "✓ vpr --help passed"
else
    echo "✗ vpr --help failed: unexpected output"
    exit 1
fi

echo ""
echo "✓ All tests passed"
```

- [ ] **Step 2: Run the test**

```bash
mise run test
```

Expected: All 3 checks pass — `vp --version` outputs a version containing `0.1.15`, and both `vpx --help` and `vpr --help` produce usage output.

- [ ] **Step 3: Commit**

```bash
git add mise-tasks/test
git commit -m "test: update integration test for vite-plus plugin"
```

---

### Task 8: End-to-End Verification

This task verifies the full plugin works outside of the test harness.

- [ ] **Step 1: Clean install and verify**

```bash
mise plugin link --force vite-plus .
mise cache clear
mise install vite-plus@latest
mise use vite-plus@latest
vp --version
vpx --help
vpr --help
```

Expected: All commands succeed. `vp --version` prints the latest Vite+ version (currently `0.1.15`).

- [ ] **Step 2: Verify ~/.vite-plus/current symlink**

```bash
ls -la ~/.vite-plus/current
```

Expected: Symlink pointing to the Mise install path (e.g. `~/.local/share/mise/installs/vite-plus/0.1.15/`).

- [ ] **Step 3: Run linting**

```bash
mise run lint
```

Expected: No lint errors. If `stylua` reports formatting issues, fix with `mise run lint-fix` and commit.

- [ ] **Step 4: Run full CI suite locally**

```bash
mise run ci
```

Expected: All checks pass (lint + test).

- [ ] **Step 5: Final commit (if any lint fixes were needed)**

```bash
git add -A
git commit -m "style: fix formatting from linter"
```

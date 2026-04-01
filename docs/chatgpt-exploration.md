Yes. For Vite+, a **tool plugin** is the better fit than a backend plugin.

Reason: backend plugins are mainly for `plugin:tool` ecosystems where one plugin manages many tools, while tool plugins are for a single tool with custom install steps, env setup, or legacy parsing. Vfox-based plugins are the recommended modern plugin system in mise, are written in Lua, and work across macOS, Linux, and Windows. ([mise-en-place][1])

Your Vite+ case matches the “complex installation process” exception pretty closely:

- download a platform-specific archive
- place `vp`, `vpx`, and `vpr`
- possibly run an install/bootstrap step
- possibly set env vars or PATH entries

That is exactly the kind of thing a tool plugin is for. ([mise-en-place][2])

## Recommended shape

Start from the official tool-plugin template. The docs recommend `mise-tool-plugin-template`, and the standard structure is:

- `metadata.lua`
- `hooks/available.lua`
- `hooks/pre_install.lua`
- `hooks/env_keys.lua`
- optional `hooks/post_install.lua`
- optional `lib/*.lua`
- optional `test/test.sh` ([mise-en-place][1])

A Vite+ plugin repo would look like this:

```text
mise-vite-plus/
├── metadata.lua
├── hooks/
│   ├── available.lua
│   ├── pre_install.lua
│   ├── env_keys.lua
│   └── post_install.lua
├── lib/
│   └── vite_plus.lua
└── test/
    └── test.sh
```

## How I would implement Vite+

### 1. `metadata.lua`

```lua
PLUGIN = {
  name = "vite-plus",
  version = "0.1.0",
  description = "Vite+ plugin for mise",
  author = "Mark"
}
```

This file is required plugin metadata. ([mise-en-place][3])

### 2. `hooks/available.lua`

Use the npm registry to list Vite+ versions. The plugin docs show `Available(ctx)` for version listing, and the built-in Lua modules include `http` and `json`, so you can query npm directly. ([mise-en-place][1])

```lua
local http = require("http")
local json = require("json")
local semver = require("semver")

function PLUGIN:Available(ctx)
  local resp, err = http.get({
    url = "https://registry.npmjs.org/vite-plus",
    headers = {
      ["User-Agent"] = "mise-vite-plus-plugin"
    }
  })

  if err ~= nil then
    error("Failed to fetch vite-plus versions: " .. err)
  end

  if resp.status_code ~= 200 then
    error("npm registry returned status " .. tostring(resp.status_code))
  end

  local pkg = json.decode(resp.body)
  local versions = {}

  for version, _ in pairs(pkg.versions or {}) do
    table.insert(versions, { version = version })
  end

  table.sort(versions, function(a, b)
    return semver.compare(a.version, b.version) < 0
  end)

  return versions
end
```

One important detail from the backend-plugin docs also applies conceptually here: version results should be semver-sorted from oldest to newest rather than plain string-sorted. ([mise-en-place][4])

### 3. `lib/vite_plus.lua`

Centralize the platform-specific tarball URL logic.

```lua
local M = {}

function M.os_name()
  if RUNTIME.osType == "Darwin" then
    return "darwin"
  elseif RUNTIME.osType == "Linux" then
    return "linux"
  elseif RUNTIME.osType == "Windows" then
    return "windows"
  end
  error("Unsupported OS: " .. tostring(RUNTIME.osType))
end

function M.arch_name()
  local arch = RUNTIME.archType
  if arch == "arm64" then
    return "arm64"
  elseif arch == "amd64" then
    return "x64"
  end
  error("Unsupported arch: " .. tostring(arch))
end

function M.package_name(version)
  return "@voidzero-dev/vite-plus-cli-" .. M.os_name() .. "-" .. M.arch_name()
end

function M.download_url(version)
  local pkg = M.package_name(version)
  local bare = pkg:gsub("^@", "")
  local filename = "vite-plus-cli-" .. M.os_name() .. "-" .. M.arch_name() .. "-" .. version .. ".tgz"
  return "https://registry.npmjs.org/" .. bare .. "/-/" .. filename
end

return M
```

The plugin Lua modules docs explicitly provide cross-platform helpers and recommend using built-in modules rather than external dependencies. ([mise-en-place][5])

### 4. `hooks/pre_install.lua`

This is where most of the Vite+ work belongs: download, extract, place the binary, write `package.json`, create aliases, and maybe prepare the install root. Tool plugins support `PreInstall` specifically for installation logic, while the built-in modules include `http`, `archiver`, `file`, and `cmd`. ([mise-en-place][1])

```lua
local http = require("http")
local archiver = require("archiver")
local file = require("file")
local helper = require("vite_plus")

function PLUGIN:PreInstall(ctx)
  local version = ctx.version
  local install_path = ctx.installPath

  os.execute('mkdir -p "' .. install_path .. '/bin"')

  local archive_path = file.join_path(install_path, "vite-plus.tgz")
  local extract_path = file.join_path(install_path, "extract")

  os.execute('mkdir -p "' .. extract_path .. '"')

  local err = http.download_file({
    url = helper.download_url(version),
    headers = {
      ["User-Agent"] = "mise-vite-plus-plugin"
    }
  }, archive_path)

  if err ~= nil then
    error("Failed to download Vite+ archive: " .. err)
  end

  err = archiver.decompress(archive_path, extract_path)
  if err ~= nil then
    error("Failed to extract Vite+ archive: " .. err)
  end

  -- npm tarballs usually unpack under package/
  local vp_src = file.join_path(extract_path, "package", "vp")
  local vp_dst = file.join_path(install_path, "bin", "vp")

  os.execute('cp "' .. vp_src .. '" "' .. vp_dst .. '"')
  if RUNTIME.osType ~= "Windows" then
    os.execute('chmod +x "' .. vp_dst .. '"')
  end

  -- multicall aliases
  local vpx_dst = file.join_path(install_path, "bin", "vpx")
  local vpr_dst = file.join_path(install_path, "bin", "vpr")

  if RUNTIME.osType == "Windows" then
    os.execute('copy "' .. vp_dst .. '" "' .. vpx_dst .. '"')
    os.execute('copy "' .. vp_dst .. '" "' .. vpr_dst .. '"')
  else
    os.execute('ln -sf vp "' .. vpx_dst .. '"')
    os.execute('ln -sf vp "' .. vpr_dst .. '"')
  end

  local pkg_json = [[
{
  "name": "vp-global",
  "version": "]] .. version .. [[",
  "private": true,
  "dependencies": {
    "vite-plus": "]] .. version .. [["
  }
}
]]
  local f = assert(io.open(file.join_path(install_path, "package.json"), "w"))
  f:write(pkg_json)
  f:close()

  return {}
end
```

## 5. `hooks/post_install.lua`

If Vite+ truly needs the equivalent of your Homebrew `post_install`, put it here. Tool plugins explicitly support `PostInstall` for additional setup after installation. ([mise-en-place][1])

```lua
local cmd = require("cmd")

function PLUGIN:PostInstall(ctx)
  local path = ctx.installPath
  local bin = path .. "/bin"

  cmd.exec("vp install --silent", {
    cwd = path,
    env = {
      CI = "true",
      PATH = bin .. ":" .. os.getenv("PATH")
    }
  })

  return {}
end
```

This is the piece I am least certain about, because it depends on how `vp install` behaves when run inside a non-Homebrew, non-global install root. If Vite+ insists on writing into `~/.vite-plus/current` or other home-directory state, you may need to redirect that with an env var if one exists, or patch the plugin to create a per-install structure. That part depends on Vite+ internals, not mise itself.

## 6. `hooks/env_keys.lua`

Tool plugins use `EnvKeys` to expose environment configuration. The docs list env setup as one of the main jobs of tool plugins. ([mise-en-place][1])

For a first pass, keep it simple and just expose `bin/`:

```lua
function PLUGIN:EnvKeys(ctx)
  return {
    {
      key = "PATH",
      value = ctx.installPath .. "/bin",
      path = true
    }
  }
end
```

If Vite+ needs extra env like `VP_HOME`, add it here:

```lua
function PLUGIN:EnvKeys(ctx)
  return {
    {
      key = "PATH",
      value = ctx.installPath .. "/bin",
      path = true
    },
    {
      key = "VP_HOME",
      value = ctx.installPath
    }
  }
end
```

## Local development flow

The official docs recommend local linking during development:

```bash
mise plugin link vite-plus /path/to/mise-vite-plus
mise ls-remote vite-plus
mise install vite-plus@0.1.15
mise use -g vite-plus@0.1.15
vp --version
```

That `plugin link` → `ls-remote` → `install` → `use` loop is the intended local workflow. ([mise-en-place][1])

## The main design choice

You have two viable plugin designs.

### Option A: a true `vite-plus` tool plugin

This is what I outlined above.

Use this if the plugin is specifically for Vite+ and you want commands like:

```bash
mise install vite-plus@0.1.15
```

### Option B: a backend plugin for “npm package with custom bootstrap”

Use this only if you want something generic, like:

```bash
mise install my-plugin:vite-plus@0.1.15
mise install my-plugin:other-tool@1.2.3
```

That is more work and only makes sense if you want to support a family of similarly awkward packages. Backend plugins use `BackendListVersions`, `BackendInstall`, and `BackendExecEnv`, and are intended for multi-tool `plugin:tool` formats. ([mise-en-place][6])

## What will probably be annoying

The risky parts are not the plugin mechanics. They are Vite+’s install assumptions.

Based on the Homebrew formula you showed earlier, the likely trouble spots are:

- it may expect a home-directory install model
- it may expect a mutable `current` symlink
- it may expect JS dependencies to be bootstrapped after binary install
- it may rely on multicall behavior from `argv[0]`

A mise plugin can handle all of those in principle because plugins can run arbitrary install/setup code and set env vars, but each one is an implementation detail you will need to test. Tool plugins also execute arbitrary code, so stick to a repo you control and pin versions. ([mise-en-place][2])

## Minimal first milestone

I would aim for this sequence:

1. `Available` reads versions from npm.
2. `PreInstall` downloads the platform tarball and installs `vp`.
3. `EnvKeys` exposes `bin/`.
4. Verify `vp --version`.
5. Then add `vpx`/`vpr`.
6. Only after that add any `vp install --silent` bootstrap logic.

That keeps the failure surface small.

## Publish/use it

Once it works locally, put it in a git repo and install it with:

```bash
mise plugin install vite-plus https://github.com/<you>/mise-vite-plus
mise install vite-plus@0.1.15
```

Mise also supports configuring plugin repos in `mise.toml`. ([mise-en-place][7])

Here is the shortest practical summary:

- write a **tool plugin**, not a backend plugin
- use the official `mise-tool-plugin-template`
- implement `available.lua`, `pre_install.lua`, `env_keys.lua`
- add `post_install.lua` only if Vite+ truly requires bootstrap steps
- develop with `mise plugin link`

A useful next step is to make the plugin only support macOS first, get `vp --version` working, and then generalize platform handling.

[1]: https://mise.jdx.dev/tool-plugin-development.html "Tool Plugin Development | mise-en-place"
[2]: https://mise.jdx.dev/plugins.html "Plugins | mise-en-place"
[3]: https://mise.jdx.dev/plugin-publishing.html "Plugin Publishing | mise-en-place"
[4]: https://mise.jdx.dev/backend-plugin-development.html?utm_source=chatgpt.com "Backend Plugin Development | mise-en-place"
[5]: https://mise.jdx.dev/dev-tools/backends/vfox.html "Vfox Backend | mise-en-place"
[6]: https://mise.jdx.dev/backend-plugin-development.html "Backend Plugin Development | mise-en-place"
[7]: https://mise.jdx.dev/plugin-usage.html "Using Plugins | mise-en-place"

> Does this support using @latest?

Yes, but you have to implement it explicitly in the plugin.

Out of the box, a tool plugin does **not** automatically understand `@latest`. It just receives whatever version string the user typed (`ctx.version`) and uses it. So unless you handle `"latest"` yourself, this will fail or behave unpredictably.

## What mise expects conceptually

When someone runs:

```bash
mise install vite-plus@latest
```

mise will:

1. Call your `Available` hook
2. Pass `"latest"` into your install flow
3. Expect your plugin to resolve that into a concrete version

There’s no built-in “latest resolution” unless you implement it.

## How to support `@latest`

You resolve `"latest"` inside `PreInstall` (or a helper), using the same source as `Available`.

For npm-backed tools, the cleanest approach is to read the `dist-tags.latest` field from the npm registry.

### Update your helper

```lua
local http = require("http")
local json = require("json")

local M = {}

function M.resolve_version(version)
  if version ~= "latest" then
    return version
  end

  local resp, err = http.get({
    url = "https://registry.npmjs.org/vite-plus"
  })

  if err ~= nil then
    error("Failed to fetch latest version: " .. err)
  end

  local pkg = json.decode(resp.body)
  local latest = pkg["dist-tags"] and pkg["dist-tags"]["latest"]

  if not latest then
    error("Could not resolve latest version from npm")
  end

  return latest
end

return M
```

## Use it in `PreInstall`

```lua
local helper = require("vite_plus")

function PLUGIN:PreInstall(ctx)
  local version = helper.resolve_version(ctx.version)

  -- use resolved version everywhere below
end
```

## Also fix `Available` ordering

You already sort versions, but for consistency with `latest`, you should ensure:

- semver sort is correct
- newest version is last

Then mise UIs (like `ls-remote`) behave correctly.

## Optional: support other aliases

If you want parity with npm behavior, you can also support:

- `@latest` → `dist-tags.latest`
- `@beta` → `dist-tags.beta`
- `@next` → `dist-tags.next`

Example:

```lua
function M.resolve_version(version)
  if version ~= "latest" and not version:match("^%a+$") then
    return version
  end

  local resp = http.get({ url = "https://registry.npmjs.org/vite-plus" })
  local pkg = json.decode(resp.body)

  local tag = pkg["dist-tags"] and pkg["dist-tags"][version]

  if tag then
    return tag
  end

  error("Unknown version/tag: " .. version)
end
```

## Important nuance

Even if you support `@latest`, mise will still **store the resolved version**, not `"latest"`.

So after:

```bash
mise use vite-plus@latest
```

you’ll end up with something like:

```toml
[tools]
vite-plus = "0.1.15"
```

That’s expected behavior.

---

Short answer:
**Yes, but only if your plugin resolves `"latest"` to a real version (usually via npm `dist-tags`).**

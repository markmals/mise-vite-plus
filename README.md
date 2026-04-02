# mise-vite-plus

A [mise](https://mise.jdx.dev) plugin to install and manage [Vite+](https://viteplus.dev) — the Unified Toolchain for the Web.

## Install Globally

```bash
mise plugin install vite-plus https://github.com/markmals/mise-vite-plus
mise install vite-plus@latest
mise use -g vite-plus@latest
```

## Install Locally

```toml
[plugins]
vite-plus = "https://github.com/markmals/mise-vite-plus"

[tools]
vite-plus = "latest"
```

## Usage

Once installed, the `vp`, `vpx`, and `vpr` commands are available:

```bash
vp --version
vp create        # Scaffold a new project
vpx cowsay hello # Run a package binary
vpr build        # Run a project script
```

Pin a specific version in a project:

```bash
mise use vite-plus@0.1.15
```

List available versions:

```bash
mise ls-remote vite-plus
```

## What the plugin does

The plugin replicates the behavior of the official [Vite+ installer](https://vite.plus) as a native mise plugin:

1. **Available** — Fetches all published versions from the npm registry.
2. **PreInstall** — Resolves the platform-specific npm tarball URL (macOS/Linux, x64/arm64).
3. **PostInstall** — Extracts the `vp` binary, creates `vpx`/`vpr` multicall symlinks, writes a `package.json` wrapper, runs `vp install --silent` to bootstrap JS dependencies, and sets up the `~/.vite-plus/current` symlink.
4. **EnvKeys** — Adds `<install-dir>/bin` to `PATH`.

## Development

### Prerequisites

- [mise](https://mise.jdx.dev) — manages dev tools (Lua, stylua, actionlint, etc.)
- [hk](https://hk.jdx.dev) — linting and pre-commit hooks (installed via mise)

### Setup

```bash
mise install        # Install dev tools
hk install          # Set up pre-commit hooks
mise plugin link --force vite-plus .
```

### Tasks

```bash
mise run test       # Install vite-plus and verify vp/vpx/vpr
mise run lint       # Run all linters (stylua, lua-language-server, actionlint)
mise run lint-fix   # Auto-fix lint issues
mise run ci         # Run lint + test
```

### Debugging

```bash
MISE_DEBUG=1 mise install vite-plus@latest
```

## Files

| Path                     | Purpose                                 |
| ------------------------ | --------------------------------------- |
| `metadata.lua`           | Plugin metadata (name, version, author) |
| `hooks/available.lua`    | Fetches versions from npm registry      |
| `hooks/pre_install.lua`  | Returns platform-specific tarball URL   |
| `hooks/post_install.lua` | Binary setup, JS bootstrap, symlinks    |
| `hooks/env_keys.lua`     | Adds `bin/` to `PATH`                   |
| `lib/platform.lua`       | Platform detection and URL helpers      |
| `mise-tasks/test`        | Integration test script                 |
| `hk.pkl`                 | Linting and pre-commit hook config      |

## License

MIT

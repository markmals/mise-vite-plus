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

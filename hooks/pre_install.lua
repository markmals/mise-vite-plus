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

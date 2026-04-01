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

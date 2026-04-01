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

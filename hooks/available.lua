--- Split a string by a single-character separator.
--- @param s string
--- @param sep string single character
--- @return string[]
local function split(s, sep)
    local parts = {}
    for part in s:gmatch("([^" .. sep .. "]+)") do
        parts[#parts + 1] = part
    end
    return parts
end

--- Compare two semver pre-release strings per the SemVer 2.0 spec.
--- Returns -1, 0, or 1.
--- @param a string|nil
--- @param b string|nil
--- @return integer
local function compare_pre(a, b)
    -- No pre-release on both → equal
    if not a and not b then return 0 end
    -- A release (no pre) has higher precedence than a pre-release
    if not a then return 1 end
    if not b then return -1 end

    local a_ids = split(a, ".")
    local b_ids = split(b, ".")

    for i = 1, math.max(#a_ids, #b_ids) do
        if not a_ids[i] then return -1 end -- fewer fields → lower precedence
        if not b_ids[i] then return 1 end

        local an = tonumber(a_ids[i])
        local bn = tonumber(b_ids[i])

        if an and bn then
            if an ~= bn then return an < bn and -1 or 1 end
        elseif an then
            return -1 -- numeric identifiers sort before alphanumeric
        elseif bn then
            return 1
        else
            if a_ids[i] < b_ids[i] then return -1 end
            if a_ids[i] > b_ids[i] then return 1 end
        end
    end

    return 0
end

--- Compare two semver version strings. Returns true when a < b.
--- @param a string
--- @param b string
--- @return boolean
local function version_less(a, b)
    local a_maj, a_min, a_pat, a_pre = a:match("^(%d+)%.(%d+)%.(%d+)%-?(.*)$")
    local b_maj, b_min, b_pat, b_pre = b:match("^(%d+)%.(%d+)%.(%d+)%-?(.*)$")

    -- Versions that don't parse as semver sort before valid versions
    if not a_maj and not b_maj then return a < b end
    if not a_maj then return true end
    if not b_maj then return false end

    a_maj, a_min, a_pat = tonumber(a_maj), tonumber(a_min), tonumber(a_pat)
    b_maj, b_min, b_pat = tonumber(b_maj), tonumber(b_min), tonumber(b_pat)

    if a_maj ~= b_maj then return a_maj < b_maj end
    if a_min ~= b_min then return a_min < b_min end
    if a_pat ~= b_pat then return a_pat < b_pat end

    local pre_a = a_pre ~= "" and a_pre or nil
    local pre_b = b_pre ~= "" and b_pre or nil

    return compare_pre(pre_a, pre_b) < 0
end

--- Returns a list of available Vite+ versions from the npm registry.
--- Documentation: https://mise.jdx.dev/tool-plugin-development.html#available-hook
--- @param ctx AvailableCtx
--- @return AvailableVersion[]
function PLUGIN:Available(ctx) -- luacheck: ignore 212
    local http = require("http")
    local json = require("json")

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
        -- Filter out git-hash based development builds (e.g. 0.0.0-g0fd4d06d.20260225-1306)
        -- whose non-standard pre-release segments confuse semver sorting in mise.
        -- Keep stable releases and standard pre-releases (alpha, beta, rc).
        local pre = version:match("^%d+%.%d+%.%d+%-(.+)$")
        if not pre or pre:match("^alpha%.") or pre:match("^beta%.") or pre:match("^rc%.") then
            table.insert(result, { version = version })
        end
    end

    table.sort(result, function(a, b)
        return version_less(b.version, a.version)
    end)

    return result
end

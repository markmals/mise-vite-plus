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

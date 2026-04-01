# Contributor Guidelines

This is a repository for a vfox-based Lua plugin for Mise to make installing Vite+ possible via Mise. The goal is to replicate the official Vite+ installer script (https://vite.plus) as a native Mise plugin so the behavior matches regardless of how the user installs Vite+.

## Additional Documentation

Additional documentation for this project and its tools can be found in `./docs/*.md`.

## Homebrew Formula

I've done something similar to this wit Homebrew as well (https://github.com/markmals/homebrew-tap), which you can see the full formula below:

```ruby
class VitePlus < Formula
  desc "Unified Toolchain for the Web"
  homepage "https://viteplus.dev"
  license "MIT"
  depends_on :macos

  if Hardware::CPU.arm?
    url "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-darwin-arm64/-/vite-plus-cli-darwin-arm64-0.1.15.tgz"
    sha256 "d91c4aceb9f06a6b13b21bef225b779dffcf1e3fc7467ec04d33fe4fab32d9a3"
  else
    url "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-darwin-x64/-/vite-plus-cli-darwin-x64-0.1.15.tgz"
    sha256 "c52becbbfdd668035d53709ef476459faa2c54efda82af2e1ea83e575357f77b"
  end

  def install
    # Install binary into libexec/bin/ so it sits inside a version directory
    # that mirrors the structure the install script creates (~/.vite-plus/<ver>/)
    (libexec/"bin").install Dir["**/vp"].first => "vp"

    # Create wrapper package.json so `vp install` can pull down the JS CLI
    # (needed for commands like migrate/create that delegate to JS)
    (libexec/"package.json").write <<~JSON
      {
        "name": "vp-global",
        "version": "#{version}",
        "private": true,
        "dependencies": {
          "vite-plus": "#{version}"
        }
      }
    JSON

    # vpx and vpr are multicall aliases — the vp binary changes behavior based on argv[0]
    (libexec/"bin").install_symlink "vp" => "vpx"
    (libexec/"bin").install_symlink "vp" => "vpr"

    bin.install_symlink libexec/"bin/vp"
    bin.install_symlink libexec/"bin/vpx"
    bin.install_symlink libexec/"bin/vpr"
  end

  def post_install
    # Bootstrap JS dependencies using vp itself (no external node required).
    # This runs outside the sandbox so vp can download Node if needed.
    # CI=true suppresses interactive prompts (e.g., Node manager setup).
    cd libexec do
      ENV["CI"] = "true"
      system bin/"vp", "install", "--silent"
    end

    # `vp env setup` creates shims in ~/.vite-plus/bin/ that resolve through
    # ../current/bin/vp. Standalone installs create this symlink automatically,
    # but Homebrew installs don't — create it so the shims work.
    vp_home = Pathname.new(Dir.home)/".vite-plus"
    vp_home.mkpath
    current = vp_home/"current"
    current.unlink if current.exist? || current.symlink?
    current.make_symlink(libexec)
  end

  def caveats
    <<~EOS
      Vite+ installed.

      Run `vp create` to start a project.

      If you use a Node version manager (mise, nvm, fnm, etc.),
      it may shadow the Node version that Vite+ manages. Run:

          vp env setup

      to add Vite+'s managed Node to your shell PATH.

      Try:
          vp --version
          vp help
          vp create
          vpx cowsay Vite+ FTW!
          vpr build
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/vp --version")
    assert_match "Usage: vpx", shell_output("#{bin}/vpx --help")
    assert_match "Usage: vpr", shell_output("#{bin}/vpr --help")
  end
end
```

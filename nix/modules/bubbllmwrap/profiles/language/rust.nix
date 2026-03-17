{pkgs, ...}: {
  _file = ./rust.nix;

  profiles = {
    rust = {
      args = [
        "--ro-bind-try"
        "~/.cargo/registry"
        "~/.cargo/registry"

        "--ro-bind-try"
        "~/.cargo/git"
        "~/.cargo/git"

        "--ro-bind-try"
        "~/.cargo/config"
        "~/.cargo/config"

        "--ro-bind-try"
        "~/.cargo/config.toml"
        "~/.cargo/config.toml"

        "--ro-bind-try"
        "~/.cargo/credentials"
        "~/.cargo/credentials"
      ];

      packages = with pkgs; [
        rustc
        cargo
        rustfmt
        clippy
        rust-analyzer
      ];
    };
  };
}

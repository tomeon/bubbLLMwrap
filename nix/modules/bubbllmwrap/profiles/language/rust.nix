{
  lib,
  pkgs,
  ...
}: {
  _file = ./rust.nix;

  profiles = {
    rust = {
      filesystem.mounts = {
        cargo-registry = "~/.cargo/registry";
        cargo-git = "~/.cargo/git";
        cargo-config = "~/.cargo/config";
        cargo-config-toml = "~/.cargo/config.toml";
        # Off by default: crates.io tokens (older file name).
        cargo-credentials = {
          source = "~/.cargo/credentials";
          enable = lib.mkDefault false;
        };
        # Off by default: crates.io tokens.
        cargo-credentials-toml = {
          source = "~/.cargo/credentials.toml";
          enable = lib.mkDefault false;
        };
      };

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

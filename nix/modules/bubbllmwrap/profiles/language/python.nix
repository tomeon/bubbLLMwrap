{
  lib,
  pkgs,
  ...
}: {
  _file = ./python.nix;

  profiles = {
    python = {
      filesystem.mounts = {
        pip-cache = "~/.cache/pip";
        poetry-cache = "~/.cache/pypoetry";
        uv-cache = "~/.cache/uv";
        # Off by default: `auth.toml` can hold repository credentials.
        poetry-config = {
          source = "~/.config/pypoetry";
          enable = lib.mkDefault false;
        };
        uv-config = "~/.config/uv";
        pip-config = "~/.pip";
        # Off by default: PyPI upload tokens.
        pypirc = {
          source = "~/.pypirc";
          enable = lib.mkDefault false;
        };
      };

      packages = with pkgs; [
        python3
        python3Packages.pip
        python3Packages.virtualenv
        poetry
        ruff
        pyright
        uv
      ];
    };
  };
}

{pkgs, ...}: {
  _file = ./python.nix;

  profiles = {
    python = {
      args = [
        "--ro-bind-try"
        "~/.cache/pip"
        "~/.cache/pip"

        "--ro-bind-try"
        "~/.cache/pypoetry"
        "~/.cache/pypoetry"

        "--ro-bind-try"
        "~/.cache/uv"
        "~/.cache/uv"

        "--ro-bind-try"
        "~/.config/pypoetry"
        "~/.config/pypoetry"

        "--ro-bind-try"
        "~/.config/uv"
        "~/.config/uv"

        "--ro-bind-try"
        "~/.pip"
        "~/.pip"

        "--ro-bind-try"
        "~/.pypirc"
        "~/.pypirc"
      ];

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

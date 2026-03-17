{pkgs, ...}: {
  _file = ./js.nix;

  profiles = {
    js = {
      args = [
        "--ro-bind-try"
        "~/.npm"
        "~/.npm"

        "--ro-bind-try"
        "~/.yarn"
        "~/.yarn"

        "--ro-bind-try"
        "~/.cache/yarn"
        "~/.cache/yarn"

        "--ro-bind-try"
        "~/.local/share/pnpm"
        "~/.local/share/pnpm"

        "--ro-bind-try"
        "~/.bun"
        "~/.bun"

        "--ro-bind-try"
        "~/.npmrc"
        "~/.npmrc"

        "--ro-bind-try"
        "~/.yarnrc"
        "~/.yarnrc"

        "--ro-bind-try"
        "~/.yarnrc.yml"
        "~/.yarnrc.yml"

        "--ro-bind-try"
        "~/.config/pnpm"
        "~/.config/pnpm"

        "--ro-bind-try"
        "~/.config/yarn"
        "~/.config/yarn"

        "--ro-bind-try"
        "~/.config/npm"
        "~/.config/npm"
      ];

      packages = with pkgs; [
        nodejs
        yarn
        pnpm
        bun
        typescript
        typescript-language-server
        eslint
        prettier
      ];
    };
  };
}

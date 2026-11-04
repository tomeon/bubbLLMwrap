{
  lib,
  pkgs,
  ...
}: {
  _file = ./js.nix;

  profiles = {
    js = {
      filesystem.mounts = {
        npm-cache = "~/.npm";
        yarn = "~/.yarn";
        yarn-cache = "~/.cache/yarn";
        pnpm-store = "~/.local/share/pnpm";
        bun = "~/.bun";
        # Off by default: registry auth tokens.
        npmrc = {
          source = "~/.npmrc";
          enable = lib.mkDefault false;
        };
        # Off by default: registry auth tokens.
        yarnrc = {
          source = "~/.yarnrc";
          enable = lib.mkDefault false;
        };
        # Off by default: registry auth tokens (`npmAuthToken`).
        yarnrc-yml = {
          source = "~/.yarnrc.yml";
          enable = lib.mkDefault false;
        };
        # Off by default: its `rc` can hold registry auth tokens.
        pnpm-config = {
          source = "~/.config/pnpm";
          enable = lib.mkDefault false;
        };
        yarn-config = "~/.config/yarn";
        # Off by default: its `npmrc` can hold registry auth tokens.
        npm-config = {
          source = "~/.config/npm";
          enable = lib.mkDefault false;
        };
      };

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

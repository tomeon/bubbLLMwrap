{pkgs, ...}: {
  _file = ./go.nix;

  profiles = {
    go = {
      filesystem.mounts = {
        go-mod-cache = "~/go/pkg/mod";
        go-build-cache = "~/.cache/go-build";
        go-config = "~/.config/go";
      };

      packages = with pkgs; [
        go
        gopls
        delve
        golangci-lint
        gotools
        gofumpt
      ];
    };
  };
}

{pkgs, ...}: {
  _file = ./go.nix;

  profiles = {
    go = {
      args = [
        "--ro-bind-try"
        "~/go/pkg/mod"
        "~/go/pkg/mod"

        "--ro-bind-try"
        "~/.cache/go-build"
        "~/.cache/go-build"

        "--ro-bind-try"
        "~/.config/go"
        "~/.config/go"
      ];

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

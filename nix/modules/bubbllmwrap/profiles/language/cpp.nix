{pkgs, ...}: {
  _file = ./cpp.nix;

  profiles = {
    cpp = {
      args = [
        "--ro-bind-try"
        "~/.cache/ccache"
        "~/.cache/ccache"

        "--ro-bind-try"
        "~/.ccache"
        "~/.ccache"
      ];

      packages = with pkgs; [
        ccache
        gcc
        clang
        cmake
        gnumake
        clang-tools
      ];
    };
  };
}

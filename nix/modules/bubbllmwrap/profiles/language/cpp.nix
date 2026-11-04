{pkgs, ...}: {
  _file = ./cpp.nix;

  profiles = {
    cpp = {
      filesystem.mounts = {
        ccache = "~/.cache/ccache";
        ccache-legacy = "~/.ccache";
      };

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

{
  lib,
  pkgs,
  ...
}: {
  _file = ./basic.nix;

  profiles = {
    basic-tooling = {
      args = [
        "--ro-bind-try"
        "~/.gitconfig"
        "~/.gitconfig"

        "--ro-bind-try"
        "~/.config/git"
        "~/.config/git"

        "--ro-bind-try"
        "~/.config/jj"
        "~/.config/jj"
      ];

      packages = with pkgs;
        lib.filter (p: p.meta.supported or true) [
          bash
          curl
          coreutils
          diffutils
          dnsutils
          fd
          file
          findutils
          gawk
          getent
          git
          gnugrep
          gnused
          gnutar
          gzip
          iproute2
          jq
          jujutsu
          less
          man
          patch
          procps
          ripgrep
          rsync
          tree
          unzip
          util-linux
          vim
          which
          yq
          zip
        ];

      env = {
        TMPDIR = "/tmp";
        SHELL = "${pkgs.bash}/bin/bash";
      };
    };
  };
}

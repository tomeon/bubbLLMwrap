{
  lib,
  pkgs,
  ...
}: {
  _file = ./nix.nix;

  profiles = {
    nix = {
      # `/nix/var/nix` is deliberately not bound: it holds the Nix daemon's
      # socket, and a read-only bind doesn't stop `connect(2)`. With seccomp
      # disabled the CLI could then have the daemon build or substitute, with
      # network access outside the proxy. (With seccomp enabled, `AF_UNIX`
      # sockets are blocked anyway.) Bind it yourself if you accept that.
      filesystem.mounts = {
        etc-nix = "/etc/nix";
        # Off by default: `nix.conf` often holds `access-tokens`.
        nix-config = {
          source = "~/.config/nix";
          enable = lib.mkDefault false;
        };
      };

      packages = with pkgs; [
        nix
        alejandra
      ];
    };
  };
}

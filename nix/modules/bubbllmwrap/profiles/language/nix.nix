{pkgs, ...}: {
  _file = ./nix.nix;

  profiles = {
    nix = {
      args = [
        "--ro-bind-try"
        "/nix/var/nix"
        "/nix/var/nix"

        "--ro-bind-try"
        "/etc/nix"
        "/etc/nix"

        "--ro-bind-try"
        "~/.config/nix"
        "~/.config/nix"
      ];

      packages = with pkgs; [
        nix
        alejandra
      ];
    };
  };
}

{
  lib,
  pkgs,
  ...
}: {
  _file = ./devops.nix;

  profiles = {
    devops = {
      filesystem.mounts = {
        # Off by default: cluster credentials.
        kube = {
          source = "~/.kube";
          enable = lib.mkDefault false;
        };
        # Off by default: AWS keys.
        aws = {
          source = "~/.aws";
          enable = lib.mkDefault false;
        };
        helm-cache = "~/.cache/helm";
        # Off by default: `credentials.tfrc.json` holds API tokens.
        terraform = {
          source = "~/.terraform.d";
          enable = lib.mkDefault false;
        };
        # Off by default: `config.json` holds registry credentials.
        docker = {
          source = "~/.docker";
          enable = lib.mkDefault false;
        };
        # Off by default: `auth.json` can hold registry credentials.
        containers-config = {
          source = "~/.config/containers";
          enable = lib.mkDefault false;
        };
        # Off by default: registry and repository credentials.
        helm-config = {
          source = "~/.config/helm";
          enable = lib.mkDefault false;
        };
      };

      packages = with pkgs; [
        awscli2
        podman
        kubernetes-helm
        kubectl
        opentofu
        pgcli
        cloudflared
      ];
    };
  };
}

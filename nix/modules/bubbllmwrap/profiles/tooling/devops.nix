{pkgs, ...}: {
  _file = ./devops.nix;

  profiles = {
    devops = {
      args = [
        "--ro-bind-try"
        "~/.kube"
        "~/.kube"

        "--ro-bind-try"
        "~/.aws"
        "~/.aws"

        "--ro-bind-try"
        "~/.cache/helm"
        "~/.cache/helm"

        "--ro-bind-try"
        "~/.terraform.d"
        "~/.terraform.d"

        "--ro-bind-try"
        "~/.docker"
        "~/.docker"

        "--ro-bind-try"
        "~/.config/containers"
        "~/.config/containers"

        "--ro-bind-try"
        "~/.config/helm"
        "~/.config/helm"
      ];

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

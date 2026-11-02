{
  description = "Private inputs for development of this project";

  inputs = {
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "";
  };

  # This flake is only used for its inputs; actual configuration goes in the
  # `partitionedAttrs` option of the top-level flake.
  outputs = _: {};
}

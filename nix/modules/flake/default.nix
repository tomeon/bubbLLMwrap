# flake-parts integration module
#
# Provides perSystem options for configuring sandboxes and devshells
# declaratively within a flake-parts-based flake.
#
# Usage in a flake:
#   imports = [bubbllmwrap.flakeModules.bubbllmwrap];
#   perSystem = {config, pkgs, ... }: {
#     bubbllmwrap = {
#       profiles = {
#         claude-code.llm.package = pkgs.claude-code;
#         my-tooling.packages = with pkgs; [
#           perl
#           util-linux
#         ];
#       };
#
#       environments.my-env.imports = with config.bubbllmwrap.profiles; [
#         claude-code
#         my-tooling
#       ];
#     };
#   };
{
  lib,
  flake-parts-lib,
  moduleWithSystem,
  self,
  ...
} @ localFlake: {...} @ consumer: let
  inherit (lib) mkOption types;
in {
  _file = ./default.nix;

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
      config,
      pkgs,
      ...
    } @ perSystem: let
      path = self + "/nix/lib/modules/eval-args.nix";
      args = import path localFlake perSystem ({lib, ...}: {
        options = {
          includePackages = mkOption {
            type = types.bool;
            default = true;
            description = ''
              When enabled, include the generated LLM sandbox scripts in the
              `packages` flake output.
            '';
          };
        };
      });
    in {
      _file = ./default.nix;
      options = {
        bubbllmwrap = mkOption {
          description = ''
            Configuration for bubblewrap-based LLM sandbox environments and
            their profiles.
          '';
          default = {};
          type = types.submoduleWith (args
            // {
              shorthandOnlyDefinesConfig = false;
            });
        };
      };
    });

  config = {
    perSystem = {config, ...}: let
      cfg = config.bubbllmwrap;
    in {
      packages = lib.optionalAttrs cfg.includePackages (lib.mapAttrs (_: value: value.script) cfg.environments);
    };
  };
}

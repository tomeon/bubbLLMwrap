{
  self,
  moduleWithSystem,
  ...
} @ localFlake: {
  lib,
  pkgs,
  ...
} @ args: modules: let
  path = self + "/nix/lib/modules/eval-args.nix";
in
  lib.evalModules (import path localFlake args modules)

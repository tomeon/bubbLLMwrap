{moduleWithSystem, ...} @ localFlake: {
  lib,
  pkgs,
  ...
}: modules: {
  class = "bubbllmwrap";

  specialArgs = {
    modulesPath = ../../modules/bubbllmwrap;
  };

  modules =
    (lib.toList modules)
    ++ [
      (import ./options.nix localFlake)

      ({lib, ...}: {
        _file = ./eval-args.nix;
        _module.args.pkgs = lib.mkDefault pkgs;
      })
    ];
}

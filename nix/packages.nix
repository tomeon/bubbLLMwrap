{
  lib,
  moduleWithSystem,
  self,
  ...
} @ localFlake: {
  perSystem = {
    config,
    pkgs,
    ...
  }: let
    pkgSet = lib.makeScope pkgs.newScope (scope: {
      evalSandbox = scope.callPackage (import ./pkgs/eval-sandbox localFlake) {};
      makeSandbox = scope.callPackage ./pkgs/sandbox {};
      makeSandboxProxy = scope.callPackage ./pkgs/sandbox-proxy {};
      makeSandboxScanDir = scope.callPackage ./pkgs/sandbox-scan-dir {};

      sandbox-lib = scope.callPackage ./pkgs/sandbox-lib {};
      sandbox-seccomp-filter = scope.callPackage ./pkgs/sandbox-seccomp-filter {};
      sandbox-writers = scope.callPackage ({
        lib,
        execline,
        writers,
      }:
        lib.fix (finalAttrs: {
          writeExeclineb = let
            staticArgs = {interpreter = lib.getExe' execline "execlineb";};
          in
            name: argsOrScript:
              if lib.isAttrs argsOrScript && !lib.isDerivation argsOrScript
              then writers.makeScriptWriter (argsOrScript // staticArgs) name
              else writers.makeScriptWriter staticArgs name argsOrScript;

          writeExeclinebBin = name: finalAttrs.writeExeclineb "/bin/${name}";
        })) {};

      apply-seccomp = scope.callPackage ./pkgs/apply-seccomp {};

      docs = scope.callPackage ({
        nixosOptionsDoc,
        evalSandbox,
      }: let
        eval = evalSandbox {};
        ourPrefix = "${toString self}/";
      in
        (nixosOptionsDoc {
          inherit (eval) options;
          warningsAreErrors = false;
          transformOptions = opt:
            opt
            // {
              # Disappear anything that's not one of ours.
              visible = opt.visible && (lib.any (lib.hasPrefix ourPrefix) opt.declarations);
              declarations = map (decl: let
                name = lib.removePrefix ourPrefix decl;
              in
                if lib.hasPrefix ourPrefix decl
                then {
                  inherit name;
                  url = "../${name}";
                }
                else decl)
              opt.declarations;
            };
        }).optionsCommonMark) {};
    });
  in {
    # The scope itself (with `callPackage`, `newScope`, ...) for in-flake use,
    # e.g. by the checks.
    _module.args.bubbllmwrapScope = pkgSet;

    # Strip the `makeScope` plumbing from the public output. In particular its
    # `packages` attribute is a function, which breaks the Nix CLI's lookup of
    # fully qualified installables such as `.#packages.<system>.<name>`.
    legacyPackages = builtins.removeAttrs pkgSet [
      "callPackage"
      "newScope"
      "overrideScope"
      "packages"
    ];

    packages = {
      inherit (config.legacyPackages) apply-seccomp docs;
    };
  };
}

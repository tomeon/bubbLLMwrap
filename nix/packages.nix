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
    legacyPackages = pkgSet;
    packages = lib.filterAttrs (lib.const lib.isDerivation) config.legacyPackages;
  };
}

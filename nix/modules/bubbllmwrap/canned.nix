{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}: let
  looksLikeModule = name: value: value == "regular" && lib.hasSuffix ".nix" name;
  looksLikeDir = _: value: value == "directory";

  profileModulesFrom = lib.fix (fn: dir:
    lib.pipe dir [
      builtins.readDir
      (lib.mapAttrs (
        name: value:
          if looksLikeDir name value
          then fn (dir + "/${name}")
          else if looksLikeModule name value
          then [(dir + "/${name}")]
          else []
      ))
      builtins.attrValues
      lib.concatLists
    ]);

  profileModules = profileModulesFrom (modulesPath + "/profiles");
in {
  _file = ./canned.nix;

  imports = profileModules;

  environments =
    lib.flip lib.pipe [
      lib.cartesianProduct
      (map (combo: {
        name = "${combo.llm}${lib.optionalString (combo.tooling != null) "-${combo.tooling}"}";
        value = lib.const {
          imports = [
            config.profiles.${combo.llm}
            config.profiles.${
              if combo.tooling == null
              then "basic-tooling"
              else combo.tooling
            }
          ];
        };
      }))
      lib.listToAttrs
    ] {
      llm = [
        "claude-code"
        "codex"
      ];

      tooling = [
        "cpp"
        "devops"
        "go"
        "js"
        "nix"
        "python"
        "rust"
        null
      ];
    };
}

{
  lib,
  coreutils,
  s6,
  sandbox-writers,
  stdenv,
  writers,
}: {
  name,
  services ? {},
}: let
  services' =
    {
      s6-svscan-log = {
        args = {
          makeWrapperArgs = [
            "--prefix"
            "PATH"
            ":"
            (lib.makeBinPath [s6])
          ];
        };
        text = ''
          importas -i fifo SANDBOX_S6_SVSCAN_LOG_FIFO
          importas -i dir SANDBOX_S6_LOG_DIR
          fdmove -c 1 2
          redirfd -rnb 0 $fifo
          s6-log -b -d 3 -- T $dir
        '';
      };
    }
    // services;

  mkHookScript = hookName:
    writers.writeBash "${name}-${hookName}" {
      makeWrapperArgs = [
        "--prefix"
        "PATH"
        ":"
        (lib.makeBinPath [coreutils s6])
      ];
    };
in
  stdenv.mkDerivation (finalAttrs: {
    inherit name;
    passAsFile = ["buildCommand"];
    enableParallelBuilding = true;
    buildCommand = ''
      mkdir -p "$out"
      ${lib.concatMapStringsSep "\n" (name: let
        service = services'.${name};
      in ''
        mkdir -p "$out"/${name}/{env,data}
        cp ${sandbox-writers.writeExeclineb name (service.args or {}) service.text} "$out"/${name}/run
      '') (builtins.attrNames services')}
    '';
    passthru = {
      install = mkHookScript "install" ''
        cp --dereference --preserve=all --recursive --no-target-directory ${finalAttrs} "''${1?}"
      '';

      start = mkHookScript "start" ''
        exec s6-svscan "''${1?}"
      '';

      stop = mkHookScript "stop" ''
        exec s6-svscanctl -t "''${1?}"
      '';
    };
  })

{
  lib,
  writers,
  coreutils,
  execline,
  s6,
  s6-portable-utils,
}:
writers.writeBash "sandbox-lib.sh" (''
    PATH="''${PATH:+"''${PATH}:"}${lib.escapeShellArg (lib.makeBinPath [
      coreutils
      execline
      s6
      s6-portable-utils
    ])}"
  ''
  + (builtins.readFile ./sandbox-lib.sh))

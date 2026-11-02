{
  lib,
  execline,
  coreutils,
  curl,
  glider,
  s6,
  s6-portable-utils,
  socat,
  writers,
  writeText,
  makeSandboxScanDir,
  sandbox-lib,
}: {
  name,
  allowList,
  extraConfig,
  extraRules,
}: let
  # Allowlisted domains go direct; `extraRules` is appended once, after them.
  gliderRulefile = writeText "glider.rule" (''
      forward=direct://
    ''
    + lib.concatMapStrings (domain: "domain=${domain}\n") allowList
    + extraRules);

  gliderConfig = writeText "glider.conf" ''
    verbose=True
    forward=reject://
    ${extraConfig}
  '';

  scanDir = makeSandboxScanDir {
    inherit name;
    services = {
      glider = {
        args = {
          makeWrapperArgs = [
            "--prefix"
            "PATH"
            ":"
            (lib.makeBinPath [execline glider socat s6-portable-utils])
          ];
        };
        text = ''
          s6-envdir ./env

          multisubstitute {
            importas -S -D ./data/http.sock SANDBOX_PROXY_HTTP_SOCKET_PATH
            importas -S -D ./data/socks5.sock SANDBOX_PROXY_SOCKS5_SOCKET_PATH
          }

          s6-notifyoncheck -d -c "
            redirfd -w 2 /dev/null
            if { eltest -S ''${SANDBOX_PROXY_HTTP_SOCKET_PATH} }
            if { eltest -S ''${SANDBOX_PROXY_SOCKS5_SOCKET_PATH} }
            if { socat EXEC:true UNIX-CONNECT:''${SANDBOX_PROXY_HTTP_SOCKET_PATH} }
            socat EXEC:true UNIX-CONNECT:''${SANDBOX_PROXY_SOCKS5_SOCKET_PATH}
          "
          exec glider -config ${gliderConfig} -rulefile ${gliderRulefile}
            -listen unix://''${SANDBOX_PROXY_HTTP_SOCKET_PATH},http://
            -listen unix://''${SANDBOX_PROXY_SOCKS5_SOCKET_PATH},socks5://
        '';
      };
    };
  };
in
  writers.writeBashBin "${name}-sandbox-proxy" {
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [coreutils s6])

      "--set"
      "SANDBOX_LIB"
      sandbox-lib

      "--set"
      "SANDBOX_S6_SCAN_DIR"
      scanDir
    ];
  } (builtins.readFile ./sandbox-proxy.sh)

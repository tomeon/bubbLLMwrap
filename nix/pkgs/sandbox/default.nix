{
  lib,
  callPackage,
  bash,
  bubblewrap,
  cacert,
  coreutils,
  execline,
  s6,
  socat,
  writeText,
  writers,
  makeSandboxScanDir,
  apply-seccomp,
  sandbox-lib,
}: {
  name,
  env,
  args,
  packages,
  llmPackage,
  llmCmd,
  llmArgs,
  vcsMetadataDirs ? [],
  applySeccomp ? true,
  preHook ? "",
  enterHook ? "",
  exitHook ? "",
  postHook ? "",
}: let
  customResolvConf = writeText "resolv.conf" ''
    nameserver 192.0.2.1
  '';

  customHosts = writeText "hosts" ''
    127.0.0.1 localhost
    ::1 localhost localhost6 ip6-localhost ip6-loopback
  '';

  envArgs = lib.pipe env [
    (lib.mapAttrsToList (name: value: ["--setenv" name value]))
    lib.concatLists
  ];

  allArgs = args ++ envArgs;

  path = lib.makeBinPath (packages ++ [s6 coreutils llmPackage]);

  sandboxName = "${name}-sandbox";

  preHookScript = writers.writeBash "${sandboxName}-pre-hook" {} preHook;
  postHookScript = writers.writeBash "${sandboxName}-post-hook" {} postHook;

  scanDir = makeSandboxScanDir {
    name = sandboxName;
    services = let
      args = {
        makeWrapperArgs = [
          "--prefix"
          "PATH"
          ":"
          (lib.makeBinPath [socat])
        ];
      };
    in {
      socat-http = {
        inherit args;
        text = ''
          socat TCP-LISTEN:3128,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/run/http.sock
        '';
      };

      socat-socks5 = {
        inherit args;
        text = ''
          socat TCP-LISTEN:1028,bind=127.0.0.1,reuseaddr,fork UNIX-CONNECT:/run/socks5.sock
        '';
      };
    };
  };

  vars = writers.writeBash "${sandboxName}-vars" {} ''
    declare -a __sandbox_bwrap_args=(
      ${lib.concatStringsSep "\n" allArgs}
    )

    if [[ -n "''${SANDBOX_PROXY_HTTP_SOCKET_PATH:-}" ]]; then
      __sandbox_bwrap_args+=(
        --bind
        "$SANDBOX_PROXY_HTTP_SOCKET_PATH"
        /run/http.sock

        --setenv
        SANDBOX_PROXY_HTTP_SOCKET_PATH
        /run/http.sock
      )
    fi

    if [[ -n "''${SANDBOX_PROXY_SOCKS5_SOCKET_PATH:-}" ]]; then
      __sandbox_bwrap_args+=(
        --bind
        "$SANDBOX_PROXY_SOCKS5_SOCKET_PATH"
        /run/socks5.sock

        --setenv
        SANDBOX_PROXY_SOCKS5_SOCKET_PATH
        /run/socks5.sock
      )
    fi

    declare -r __sandbox_bwrap_args
  '';

  llmMaybeWrapped = (lib.optional applySeccomp (lib.getExe apply-seccomp)) ++ [llmCmd];

  rcfile = writers.writeBash "${sandboxName}-rcfile" {} ''
    export SANDBOX_S6_SCAN_DIR=${scanDir}

    source ${sandbox-lib}

    __sandbox_setup

    unset all_proxy ALL_PROXY \
      no_proxy NO_PROXY \
      ftp_proxy FTP_PROXY \
      grpc_proxy GRPC_PROXY \
      http_proxy HTTP_PROXY \
      https_proxy HTTPS_PROXY \
      DOCKER_HTTP_PROXY DOCKER_HTTPS_PROXY \
      GIT_SSH_COMMAND \
      CLOUDSDK_PROXY_TYPE CLOUDSDK_PROXY_ADDRESS CLOUDSDK_PROXY_PORT \
      RSYNC_PROXY

    declare -r __sandbox_no_proxy=localhost,localhost6,ip6-localhost,ip6-loopback,127.0.0.1,::1

    if [[ -n "''${SANDBOX_PROXY_HTTP_SOCKET_PATH:-}" ]]; then
      declare -rx no_proxy="$__sandbox_no_proxy"
      declare -rx NO_PROXY="$__sandbox_no_proxy"

      declare -rx http_proxy="http://localhost:3128"
      declare -rx HTTP_PROXY="$http_proxy"

      declare -rx https_proxy="$http_proxy"
      declare -rx HTTPS_PROXY="$https_proxy"

      declare -rx GIT_SSH_COMMAND="ssh -o ProxyCommand='socat - PROXY:localhost:%h:%p,proxyport=3128'"

      declare -rx DOCKER_HTTP_PROXY="$http_proxy"
      declare -rx DOCKER_HTTPS_PROXY="$https_proxy"

      declare -rx CLOUDSDK_PROXY_TYPE=https
      declare -rx CLOUDSDK_PROXY_ADDRESS=localhost
      declare -rx CLOUDSDK_PROXY_PORT=3128
    else
      touch "''${__sandbox_s6_scan_dir?}/socat-http/down"
    fi

    if [[ -n "''${SANDBOX_PROXY_SOCKS5_SOCKET_PATH:-}" ]]; then
      if ! [[ -v no_proxy ]]; then
        declare -rx no_proxy="$__sandbox_no_proxy"
      fi

      if ! [[ -v NO_PROXY ]]; then
        declare -rx NO_PROXY="$__sandbox_no_proxy"
      fi

      declare -rx all_proxy="socks5h://localhost:1028"
      declare -rx ALL_PROXY="$all_proxy"

      declare -rx ftp_proxy="$all_proxy"
      declare -rx FTP_PROXY="$ftp_proxy"

      declare -rx RSYNC_PROXY="localhost:1028"

      declare -rx grpc_proxy="$all_proxy"
      declare -rx GRPC_PROXY="$grpc_proxy"

      # NOTE that Go's `net/http` does not (currently?) support `socks5h://`,
      # so use `socks5://` (no `h` suffix in the scheme).
      if [[ -z "''${DOCKER_HTTP_PROXY:-}" ]]; then
        declare -rx DOCKER_HTTP_PROXY="socks5://localhost:1028"
      fi

      if [[ -z "''${DOCKER_HTTPS_PROXY:-}" ]]; then
        declare -rx DOCKER_HTTPS_PROXY="$DOCKER_HTTP_PROXY"
      fi

      # TODO make `GIT_SSH_COMMAND` use the socks5 proxy in case the HTTP proxy
      # is disabled.
      if [[ -z "''${GIT_SSH_COMMAND:-}" ]]; then
        declare -rx GIT_SSH_COMMAND="ssh -o ProxyCommand='socat - SOCKS5-CONNECT:localhost:1028:%h:%p'"
      fi
    else
      touch "''${__sandbox_s6_scan_dir?}/socat-socks5/down"
    fi

    __sandbox_s6_svscan -C 2

    ${enterHook}
    alias ${llmCmd}=${lib.escapeShellArg (lib.concatStringsSep " " ((map lib.escapeShellArg llmMaybeWrapped) ++ llmArgs))}" "''${__sandbox_llm_cmd_args_runtime:-}
    ${llmCmd} || exit
    ${exitHook}
    exit
  '';

  entrypoint = writers.writeBash "${sandboxName}-entrypoint" {} ''
    __sandbox_llm_cmd_args_runtime="''${*@Q}" exec "''${BASH:-bash}" --rcfile ${lib.escapeShellArg rcfile} -i -m
  '';
in
  writers.writeBashBin sandboxName {
    makeWrapperArgs = [
      "--set"
      "SANDBOX_RESOLV_CONF"
      customResolvConf

      "--set"
      "SANDBOX_HOSTS"
      customHosts

      "--set"
      "SANDBOX_BIN_SH"
      "${bash}/bin/sh"

      "--set"
      "SANDBOX_USR_BIN_ENV"
      "${coreutils}/bin/env"

      "--set"
      "SANDBOX_CA_BUNDLE"
      "${cacert}/etc/ssl/certs/ca-bundle.crt"

      "--set"
      "SANDBOX_LIB"
      sandbox-lib

      "--set"
      "SANDBOX_PATH"
      path

      "--set"
      "SANDBOX_ENTRYPOINT"
      entrypoint

      "--set"
      "SANDBOX_VCS_METADATA_DIRS"
      (lib.concatStringsSep ":" vcsMetadataDirs)

      "--set"
      "SANDBOX_VARS"
      vars

      "--set"
      "SANDBOX_PRE_HOOK"
      preHookScript

      "--set"
      "SANDBOX_POST_HOOK"
      postHookScript

      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [bubblewrap execline s6])
    ];
  } (builtins.readFile ./sandbox.sh)

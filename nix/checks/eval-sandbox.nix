{
  lib,
  testers,
  writers,
  pkgs,
  evalSandbox,
  bubbllmwrap,
}: let
  allowedHost = "allowed.host";
  blockedHost = "blocked.host";

  # Exits 0 if TIOCSTI is refused with EPERM, 1 if it succeeds. Run under
  # `script` so the probe has a controlling terminal; otherwise TIOCSTI fails
  # with ENOTTY whether or not it is filtered.
  tiocstiProbe = writers.writePython3 "tiocsti-probe" {} ''
    import errno
    import fcntl
    import sys
    import termios

    try:
        fcntl.ioctl(0, termios.TIOCSTI, b"#")
    except OSError as e:
        sys.exit(0 if e.errno == errno.EPERM else 2)
    sys.exit(1)
  '';

  # Create test environments containing a fake LLM that performs testing
  # assertions.
  envs = lib.flip lib.mapAttrs bubbllmwrap.environments (_: config:
    config.extend (env: {
      hooks = {
        pre = ''
          echo 1>&2 '# PHASE: pre'
          ${pkgs.procps}/bin/ps 1>&2
        '';

        enter = ''
          echo 1>&2 '# PHASE: enter'
          ${pkgs.procps}/bin/ps 1>&2
        '';

        exit = ''
          echo 1>&2 '# PHASE: exit'
          cat "''${SANDBOX_S6_LOG_DIR}/current" 1>&2
        '';

        post = ''
          echo 1>&2 '# PHASE: post'
          cat "''${SANDBOX_S6_LOG_DIR}/current" 1>&2
        '';
      };

      packages = with pkgs; [curl];

      env = {
        TEST_VAR_SIMPLE = "simple-value";
        TEST_VAR_WITH_SPACE = {
          value = "value with spaces";
          quote = true;
        };
        TEST_VAR_NUMERIC = "42";
      };

      llm = {
        package =
          lib.mkForce
          (writers.writeBashBin env.config.name {
              makeWrapperArgs = [
                "--prefix"
                "PATH"
                ":"
                (lib.makeBinPath [pkgs.util-linux])
              ];
            } ''
              set -euo pipefail

              script="''${BASH_SOURCE[0]}"
              script_name="''${script##*/}"

              declare -g rc=0

              err() {
                declare -g rc=1
                printf 1>&2 -- '%s: error: %s\n' "$script_name" "$*"
              }

              ${lib.concatMapStringsSep "\n" (var: ''
                if ! [[ -v ${var.name} ]]; then
                  err "${var.name} is not defined"
                ${lib.optionalString var.quote ''
                  elif [[ "''$${var.name}" != ${var} ]]; then
                    err "${var.name} is set to ''$${var.name}, not expected value "${var}
                ''}
                fi
              '') (builtins.attrValues env.config.env)}

              ${lib.concatMapStringsSep "\n" (p:
                lib.optionalString (p ? meta.mainProgram) ''
                  if ! type -P ${p.meta.mainProgram}; then
                    err "package "${lib.escapeShellArg (lib.getName p)}" is not installed in this environment"
                  fi
                '')
              env.config.packages}

              if (cd /nope) &>/dev/null; then
                err "changing directory to forbidden path /nope is possible but should not be"
              fi

              ${lib.optionalString env.config.filesystem.denyVcsMetadata ''
                if touch .git/hooks/planted 2>/dev/null; then
                  err "able to write to .git/hooks, which should be read-only"
                fi
              ''}

              ${lib.concatMapStrings (dir: ''
                target=${lib.escapeShellArg dir.target}
                # shellcheck disable=SC2088
                if [[ $target == '~/'* ]]; then
                  target="$HOME/''${target#'~/'}"
                fi
                if ! touch "$target/.probe"; then
                  err "state directory $target is not writable"
                fi
              '') (lib.filter (dir: dir.enable) (lib.attrValues env.config.filesystem.stateDirs))}

              ${lib.optionalString env.config.seccomp.denyTerminalInjection ''
                if ! script -qec ${tiocstiProbe} /dev/null </dev/null >/dev/null; then
                  err "TIOCSTI was not refused with EPERM"
                fi
              ''}

              curl_with_http_code() {
                curl -o /dev/null --retry 2 -f -S -s -L -m 5 -w '%{http_code}' "$@"
              }

              if ! http_code="$(curl_with_http_code http://${allowedHost})"; then
                err "unable to reach allowed host \`${allowedHost}'"
              elif [[ "$http_code" != 200 ]]; then
                err "got unexpected HTTP code for allowed host: ''${http_code}"
              fi

              if http_code="$(curl_with_http_code http://${blockedHost})"; then
                err "able to reach blocked host \`${blockedHost}'"
              elif [[ "$http_code" != 403 ]] && [[ "$http_code" != 502 ]]; then
                err "got unexpected HTTP code for blocked host: ''${http_code}"
              fi

              for lc in http{,s}_proxy; do
                uc="''${lc^^}"
                for var in "$lc" "$uc"; do
                  if ! [[ -v "$var" ]]; then
                    err "variable ''${var} is not defined"
                  fi
                done
              done

              if [[ -f ./test.txt ]]; then
                if test_content="$(< ./test.txt)"; then
                  if [[ "$test_content" != 'test content' ]]; then
                    err "file ./test.txt contained unexpected content: ''${test_content}"
                  fi
                else
                  err "file ./test.txt could not be read"
                fi
              else
                err "file ./test.txt does not exist"
              fi

              exit "$rc"
            '');
        args = [];
      };

      proxy = {
        enable = true;
        allowList = lib.mkForce [allowedHost];
      };
    }));
in
  testers.nixosTest {
    name = "sandbox";

    nodes = {
      machine = {
        services.nginx = {
          enable = true;
          virtualHosts =
            lib.genAttrs [
              allowedHost
              blockedHost
            ] (lib.const {
              locations."/".return = "200 'OK'";
            });
        };

        networking.extraHosts = ''
          127.0.0.1 ${allowedHost} ${blockedHost}
        '';

        virtualisation.memorySize = 2048;
      };
    };

    testScript = ''
      start_all()

      machine.wait_for_unit("multi-user.target")
      machine.wait_for_unit("nginx.service")

      machine.wait_until_succeeds("curl -f -s -S -L -m 5 http://${allowedHost}/")
      machine.wait_until_succeeds("curl -f -s -S -L -m 5 http://${blockedHost}/")

      # Create test project
      machine.succeed("mkdir -p /tmp/test-project/.git/hooks")
      machine.succeed("echo 'test content' > /tmp/test-project/test.txt")

      # Test 1: Sandbox runs successfully
      ${lib.concatMapStringsSep "\n" (env: ''
        machine.succeed("cd /tmp/test-project && ${lib.getExe env.script}")
      '') (builtins.attrValues envs)}
    '';
  }

{moduleWithSystem, ...}:
moduleWithSystem ({self', ...} @ perSystem: {
    config,
    lib,
    pkgs,
    ...
  } @ toplevel: let
    inherit (lib) mkOption types;

    extraTypes = lib.fix (final: let
      argModule = {
        options = {
          value = mkOption {
            type = types.str;
            description = ''
              The value of the argument.
            '';
          };

          quote = mkOption {
            type = types.bool;
            default = false;
            description = ''
              Whether to shell quote the value of this argument .  Set this to
              false if you want to do things like interpolate environment
              variables' values in this value.
            '';
          };

          __toString = mkOption {
            type = types.functionTo types.str;
            readOnly = true;
            internal = true;
            default = var:
              if var.quote
              then lib.escapeShellArg var.value
              else var.value;
          };
        };
      };

      coerceToArg = types.coercedTo types.str (value: {inherit value;});

      arg = coerceToArg (types.submodule argModule);

      var = coerceToArg (types.submodule [
        argModule
        ({name, ...}: {
          options = {
            name = mkOption {
              type = types.strMatching "^[a-zA-Z_][0-9a-zA-Z_]+$";
              default = name;
              readOnly = true;
              internal = true;
            };
          };
        })
      ]);
    in {
      args = types.listOf arg;
      env = types.attrsOf var;
    });
  in {
    _file = ./options.nix;

    options = {
      profiles = mkOption {
        type = types.attrsOf types.deferredModule;
        default = {};
        description = ''
          Attribute set of configurations meant to be imported into one or more
          entries in the {option}`environments` attribute set.

          Use this for attaching names to groups of related options you'd like to
          mix-and-match in {option}`environments`.
        '';
        example = lib.literalExpression ''
          {
            config,
            lib,
            pkgs,
            ...
          }: {
            profiles = {
              basic-tooling = {
                packages = with pkgs; [
                  jq
                  procps
                  stdenv
                ];
              };

              my-little-language = {

              };
            };
          }

          environments = {
            my-stuff = _: {
              imports = with config.profiles; [
                basic-tooling
                my-little-language
              ];
            };
          };
        '';
      };

      environments = mkOption {
        description = ''
          Attribute set of sandbox environments. Each environment combines one
          or more profiles and produces a runnable sandbox script.
        '';
        default = {};
        type = types.attrsOf (types.submodule ({
            name,
            config,
            extendModules,
            ...
          } @ environment: {
            freeformType = types.anything;

            options = {
              name = mkOption {
                type = types.str;
                default = name;
                description = ''
                  Environment identifier. Defaults to the attribute name in the
                  {options}`environments`.
                '';
              };

              enable = lib.mkEnableOption "this sandbox environment" // {default = true;};

              extend = mkOption {
                type = types.raw;
                readOnly = true;
                default = modules:
                  (extendModules {
                    modules = lib.toList modules;
                  }).config;
                example = lib.literalExpression ''
                  {
                    my-extended-environment = environments.my-environment.extend [
                      ({pkgs, ...}: {
                        packages = with pkgs; [
                          hello
                          worldofgoo
                        ];
                      })
                    ];
                  }
                '';
                description = ''
                  Function that permits extending this environment by applying
                  additional modules.
                '';
              };

              packages = mkOption {
                type = types.listOf types.package;
                default = [];
                description = ''
                  Packages to be made available inside the sandbox.
                '';
              };

              bubblewrap = lib.mkPackageOption pkgs "bubblewrap" {};

              env = mkOption {
                type = extraTypes.env;
                default = {};
                example = {
                  BAZ = {
                    quote = true;
                    value = "wear sunscreen";
                  };
                  FOO = ''"$BAR"'';
                };
                description = ''
                  Environment variables to set inside the sandbox.
                '';
              };

              args = mkOption {
                type = extraTypes.args;
                default = [];
                example = [
                  "--ro-bind-try"
                  ''"''${PRJ_DATA_DIR}:/data"''
                ];
                description = ''
                  Additional arguments to pass to the bubblewrap
                  {command}`bwrap` executable.
                '';
              };

              hooks = mkOption {
                description = ''
                  Lifecycle hooks to run before, during, and after entering the
                  bubblewrap sandbox.
                '';
                default = {};
                type = types.submodule {
                  options = {
                    pre = mkOption {
                      type = types.lines;
                      default = "";
                      description = ''
                        Commands to run before entering the bubblewrap sandbox.
                      '';
                    };

                    enter = mkOption {
                      type = types.lines;
                      default = "";
                      description = ''
                        Commands to run upon entering the bubblewrap sandbox.
                      '';
                    };

                    exit = mkOption {
                      type = types.lines;
                      default = "";
                      description = ''
                        Commands to run upon exiting the bubblewrap sandbox.
                      '';
                    };

                    post = mkOption {
                      type = types.lines;
                      default = "";
                      description = ''
                        Commands to run after exiting the bubblewrap sandbox.
                      '';
                    };
                  };
                };
              };

              script = mkOption {
                type = types.package;
                readOnly = true;
                defaultText = "<derivation>";
                default = let
                  withoutProxy =
                    self'.legacyPackages.makeSandbox.override {
                      inherit (config) bubblewrap;
                    } {
                      inherit (config) name args env packages;

                      applySeccomp = config.seccomp.enable;

                      preHook = config.hooks.pre;
                      enterHook = config.hooks.enter;
                      exitHook = config.hooks.exit;
                      postHook = config.hooks.post;

                      llmPackage = config.llm.package;
                      llmCmd = config.llm.cmd;
                      llmArgs = config.llm.args;

                      vcsMetadataDirs =
                        lib.optionals config.filesystem.denyVcsMetadata
                        config.filesystem.vcsMetadataDirs;
                    };

                  withProxy = pkgs.writers.writeBashBin (lib.getName withoutProxy) {} ''
                    exec ${lib.getExe config.proxy.script} ${lib.getExe withoutProxy} "$@"
                  '';

                  drv =
                    if config.proxy.enable
                    then withProxy
                    else withoutProxy;
                in
                  drv.overrideAttrs (_: prevAttrs: {
                    passthru =
                      (prevAttrs.passthru or {})
                      // {
                        inherit environment;
                      };
                  });

                description = ''
                  The generated script that enters the environment.
                '';
              };

              llm = mkOption {
                description = ''
                  LLM CLI configuration (package, command, arguments, and
                  prompt) used inside this environment.
                '';
                default = {};
                type = types.submodule (llm: {
                  freeformType = types.anything;

                  options = {
                    package = mkOption {
                      type = types.package;
                      default = pkgs.coreutils;
                      defaultText = "<derivation>";
                      description = ''
                        The LLM CLI package.
                      '';
                    };

                    cmd = mkOption {
                      type = types.nonEmptyStr;
                      default = llm.config.package.meta.mainProgram or (lib.getName llm.config.package);
                      defaultText = "llm.config.package.meta.mainProgram or lib.getName llm.config.package";
                      description = ''
                        Name of the CLI executable.
                      '';
                    };

                    args = mkOption {
                      type = extraTypes.args;
                      default = [];
                      description = ''
                        Additional command-line arguments to pass to the CLI.
                      '';
                    };

                    prompt = mkOption {
                      type = types.lines;
                      default = "";
                      description = ''
                        Custom system prompt text for the LLM CLI within this
                        sandbox.

                        :::{.note}
                        This option is merely a convenience; in order to use
                        the prompt stored herein, you will have to pass it as
                        the value of an environment variable, CLI argument, or
                        configuration file parameter for the LLM CLI in
                        question.  For instance, with {command}`claude-code`,
                        you could use this prompt as the value of the
                        `--append-system-prompt` CLI argument.
                        :::
                      '';
                    };
                  };

                  config = {
                    prompt = builtins.readFile ./sandbox-prompt.txt;
                  };
                });
              };

              proxy = mkOption {
                description = ''
                  HTTP proxy configuration for filtering of network traffic to
                  and from the sandbox.

                  :::{.note}
                  Uses the [glider](https://github.com/nadoo/glider) forward
                  proxy.
                  :::
                '';
                default = {};
                type = types.submodule (proxy: {
                  freeformType = types.anything;

                  options = {
                    enable = lib.mkEnableOption "HTTP proxy with domain allowlist filtering" // {default = true;};

                    package = lib.mkPackageOption pkgs "glider" {};

                    port = mkOption {
                      type = types.port;
                      default = 0;
                      description = ''
                        Port for the proxy to listen on. `0` means a random high
                        port will be selected at runtime.
                      '';
                    };

                    allowList = mkOption {
                      type = types.listOf types.str;
                      default = [];
                      description = ''
                        List of domain names allowed through the proxy.  All other
                        domains are blocked with a `403 Unauthorized` response.
                      '';
                    };

                    extraConfig = mkOption {
                      type = types.lines;
                      default = "";
                      description = ''
                        Additional Glider configuration lines to append.
                      '';
                    };

                    extraRules = mkOption {
                      type = types.lines;
                      default = "";
                      description = ''
                        Addition Glider rule specifications.
                      '';
                    };

                    script = mkOption {
                      type = types.package;
                      readOnly = true;
                      defaultText = "<derivation>";
                      default =
                        self'.legacyPackages.makeSandboxProxy.override {
                          glider = proxy.config.package;
                        } {
                          inherit (config) name;
                          inherit (proxy.config) allowList extraConfig extraRules;
                        };
                    };
                  };
                });
              };

              seccomp = mkOption {
                description = ''
                  Options related to system call filtering in the sandbox
                  using the {command}`apply-seccomp` program.

                  :::{.note}
                  System calls are filtered using [the `apply-seccomp` program](https://github.com/anthropic-experimental/sandbox-runtime/tree/34a39e0139d9d3a386abccb8dbf4c0411b4d1028/vendor/seccomp-src)
                  from the [`anthropic-experimental/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime)
                  project.

                  See [the "Unix Socket Restrictions (Linux)" section](https://github.com/anthropic-experimental/sandbox-runtime#unix-socket-restrictions-linux)
                  from that project's documentation for details on the goals of
                  this program and how it achieves them.
                '';
                default = {};
                type = types.submodule {
                  options = {
                    enable = mkOption {
                      type = types.bool;
                      default = true;
                      description = ''
                        When enabled, run the LLM CLI under the
                        {command}`apply-seccomp` wrapper command that causes
                        certain system calls to be blocked.
                      '';
                    };
                  };
                };
              };

              filesystem = mkOption {
                description = ''
                  Host filesystem protections applied to the writable project
                  directory before {command}`bwrap` is invoked.
                '';
                default = {};
                type = types.submodule {
                  options = {
                    denyVcsMetadata = mkOption {
                      type = types.bool;
                      default = true;
                      description = ''
                        Bind every recognized version-control metadata root
                        (see {option}`environments.<name>.filesystem.vcsMetadataDirs`)
                        found under the project directory read-only inside the
                        sandbox.

                        This prevents the sandboxed CLI from planting code that
                        executes on the host *after* the sandbox exits — for
                        example `.git/hooks/*`, `core.hooksPath` or aliases in
                        `.git/config`, or the `.jj` equivalents.

                        :::{.note}
                        Locking is currently whole-root: with this enabled the
                        CLI cannot write to `.git`/`.jj` at all, so committing
                        from inside the sandbox fails. Disable this option (or
                        narrow
                        {option}`environments.<name>.filesystem.vcsMetadataDirs`)
                        if the CLI must write version-control state.
                        :::
                      '';
                    };

                    vcsMetadataDirs = mkOption {
                      type = types.listOf types.str;
                      default = [".git" ".jj"];
                      description = ''
                        Directory names recognized as version-control metadata
                        roots. Every match found under the project directory is
                        bound read-only when
                        {option}`environments.<name>.filesystem.denyVcsMetadata`
                        is enabled.

                        Recognition is by name and resolved at runtime, so
                        nested repositories, submodules, and linked worktrees
                        are all covered by the same rule.
                      '';
                    };
                  };
                };
              };
            };
          }));
      };
    };
  })

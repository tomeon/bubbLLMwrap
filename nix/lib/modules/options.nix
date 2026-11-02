{moduleWithSystem, ...}:
moduleWithSystem ({self', ...} @ perSystem: {
    config,
    lib,
    pkgs,
    ...
  } @ toplevel: let
    inherit (lib) mkOption types;

    extraTypes = lib.fix (final: let
      # `quote` defaults differ: `args` are shell words by default (profiles
      # rely on `~` expansion), while `env` values are literal by default.
      argModule = {
        quoteByDefault,
        quoteDescription,
      }: {
        options = {
          value = mkOption {
            type = types.str;
            description = ''
              The value of the argument.
            '';
          };

          quote = mkOption {
            type = types.bool;
            default = quoteByDefault;
            description = quoteDescription;
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

      arg = coerceToArg (types.submodule (argModule {
        quoteByDefault = false;
        quoteDescription = ''
          Whether to shell-quote the value. When `false` (the default for
          `args`), the value is inserted into the launcher script as shell
          syntax: `~` and `$VAR` expand on the host when the sandbox starts,
          and unquoted spaces split it into several arguments.
        '';
      }));

      var = coerceToArg (types.submodule [
        (argModule {
          quoteByDefault = true;
          quoteDescription = ''
            Whether to shell-quote the value. When `true` (the default for
            `env`), the value is passed literally. Set it to `false` to insert
            the value as shell syntax instead, e.g. to expand `~` or `$VAR` on
            the host when the sandbox starts; then quote any expansion that may
            contain spaces.
          '';
        })
        ({name, ...}: {
          options = {
            name = mkOption {
              type = types.strMatching "^[a-zA-Z_][0-9a-zA-Z_]*$";
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
        # A plain attrset definition is config only (the `types.submodule`
        # shorthand); definitions that use `imports` or declare options must be
        # functions, e.g. `environments.foo = {config, ...}: { imports = ...; }`.
        type = types.attrsOf (types.submodule ({
            name,
            config,
            extendModules,
            ...
          } @ environment: {
            # Environment modules (and profiles, which are imported into them)
            # get the same `pkgs` as the enclosing configuration, so they can
            # be written as `{pkgs, ...}: { ... }`.
            config._module.args.pkgs = lib.mkDefault pkgs;

            options = {
              name = mkOption {
                type = types.str;
                default = name;
                description = ''
                  Environment identifier. Defaults to the attribute name in
                  {option}`environments`.
                '';
              };

              enable = mkOption {
                type = types.bool;
                default = true;
                example = false;
                description = ''
                  Whether to enable this sandbox environment. The flake module
                  exports only enabled environments as packages.
                '';
              };

              extend = mkOption {
                type = types.raw;
                readOnly = true;
                default = modules:
                  (extendModules {
                    modules = lib.toList modules;
                  }).config;
                example = lib.literalExpression ''
                  (config.environments.my-environment.extend [
                    ({pkgs, ...}: {
                      packages = with pkgs; [hello];
                    })
                  ]).script
                '';
                description = ''
                  Function that applies additional modules to this environment
                  and returns the resulting configuration (with its own
                  `script`, and its own `extend`). The original environment is
                  unchanged.

                  The result is an evaluated configuration, not a module, so it
                  cannot be used as the definition of another entry in
                  {option}`environments`. To define a new named environment,
                  import the same profiles instead.
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
                example = lib.literalExpression ''
                  {
                    GREETING = "wear sunscreen";
                    PROJECT_CACHE = {
                      value = "\"$HOME/.cache/project\"";
                      quote = false;
                    };
                  }
                '';
                description = ''
                  Environment variables to set inside the sandbox. Plain
                  strings are passed literally. For shell syntax such as `~` or
                  `$VAR`, expanded on the host when the sandbox starts, use
                  `{ value = ...; quote = false; }`.
                '';
              };

              envPassthrough = mkOption {
                type = types.listOf (types.strMatching "^[a-zA-Z_][0-9a-zA-Z_]*$");
                default = [];
                example = ["TERM" "COLORTERM" "TZ"];
                description = ''
                  Names of host environment variables to pass into the sandbox
                  unchanged, if they are set. The sandbox otherwise starts with
                  an empty environment. Values in
                  {option}`environments.<name>.env` take precedence.

                  The `basic-tooling` profile passes `TERM` and `COLORTERM`
                  and sets `LANG=C.UTF-8`, a locale that needs no locale data.
                  Passing other locales (`LANG`, `LC_*`) only helps if the
                  sandbox can find their data, e.g. via `LOCALE_ARCHIVE`.
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

                        :::{.warning}
                        These commands run on the host, unsandboxed, against a
                        project directory the sandboxed CLI may have modified.
                        Running tools that read project configuration here
                        (for example {command}`git status`, which honors
                        `core.fsmonitor` from repository config) can execute
                        code the CLI planted.
                        :::
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
                      inherit (config) name args env envPassthrough packages;

                      applySeccomp = config.seccomp.enable;
                      inherit (config.seccomp) denyTerminalInjection;

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

                      stateDirs = lib.filter (dir: dir.enable) (lib.attrValues config.filesystem.stateDirs);
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
                  # Lets LLM profiles keep CLI-specific settings here (e.g. the
                  # `claude-code` profile's `disallowedTools`).
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
                  options = {
                    enable = lib.mkEnableOption "HTTP proxy with domain allowlist filtering" // {default = true;};

                    package = lib.mkPackageOption pkgs "glider" {};

                    allowList = mkOption {
                      type = types.listOf types.str;
                      default = [];
                      description = ''
                        Domain names allowed through the proxy. Each entry also
                        allows its subdomains, on any port. Requests for other
                        destinations, including IP addresses, are rejected
                        without being resolved.
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
                  System calls are filtered using [the `apply-seccomp` program](https://github.com/anthropic-experimental/sandbox-runtime/tree/7a725a314f8ce0a6404f275292d8eec557ba949a/vendor/seccomp-src)
                  from the [`anthropic-experimental/sandbox-runtime`](https://github.com/anthropic-experimental/sandbox-runtime)
                  project.

                  See [the "Unix Socket Restrictions (Linux)" section](https://github.com/anthropic-experimental/sandbox-runtime#unix-socket-restrictions-linux)
                  from that project's documentation for details on the goals of
                  this program and how it achieves them.
                  :::
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

                        :::{.warning}
                        Among other things, this blocks creating `AF_UNIX`
                        sockets. With it disabled, the CLI can connect to any
                        Unix socket reachable through a bind mount (read-only
                        binds don't prevent `connect(2)`), such as the Nix
                        daemon socket under `/nix/var/nix`, and so reach
                        services outside the proxy.
                        :::
                      '';
                    };

                    denyTerminalInjection = mkOption {
                      type = types.bool;
                      default = true;
                      description = ''
                        Apply a seccomp filter to the whole sandbox that refuses
                        the `TIOCSTI` and `TIOCLINUX` ioctls.

                        The sandbox shares the host's terminal. Without this
                        filter, a process inside can push keystrokes into the
                        terminal's input queue, and whatever is still queued
                        when the sandbox exits is run by the host shell
                        (CVE-2017-5226). Linux 6.2 and later can refuse
                        `TIOCSTI` system-wide (`dev.tty.legacy_tiocsti = 0`),
                        but not every distribution enables that.

                        This is independent of
                        {option}`environments.<name>.seccomp.enable`.
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
                        sandbox. When a root is a gitlink file (a submodule or
                        linked worktree), both the file and the directory it
                        points to are locked, as long as both are inside the
                        project.

                        This stops the sandboxed CLI from modifying existing
                        repositories to plant code that runs on the host
                        *after* the sandbox exits — for example
                        `.git/hooks/*`, or `core.fsmonitor`, `core.hooksPath`,
                        or aliases in `.git/config`, or the `.jj` equivalents.

                        If a metadata root, or the path a gitlink points to,
                        is reached through a symlink inside the project, the
                        sandbox refuses to start: the CLI could replace that
                        symlink, which a bind mount cannot cover.

                        :::{.warning}
                        Only metadata roots that exist at launch are protected.
                        Read-only binds cannot stop the CLI from creating a new
                        repository (say, `some/dir/.git`) elsewhere in the
                        project, and host-side tools such as
                        {command}`git status` will honor its configuration.
                        Hooks that live in the working tree (e.g.
                        `core.hooksPath = .husky`, hooks symlinked to tracked
                        files, or `pre-commit` configuration) are not
                        protected either.
                        :::

                        :::{.note}
                        Locking is whole-root: with this enabled the CLI cannot
                        write to `.git`/`.jj` at all, so committing from inside
                        the sandbox fails, and so do most {command}`jj`
                        commands, which snapshot the working copy. Disable this
                        option (or narrow
                        {option}`environments.<name>.filesystem.vcsMetadataDirs`)
                        if the CLI must write version-control state.
                        :::
                      '';
                    };

                    vcsMetadataDirs = mkOption {
                      type = types.listOf (types.strMatching "[^/:]+");
                      default = [".git" ".jj"];
                      description = ''
                        Names recognized as version-control metadata roots.
                        Every match found under the project directory is bound
                        read-only when
                        {option}`environments.<name>.filesystem.denyVcsMetadata`
                        is enabled. Entries are {command}`find -name` patterns,
                        so shell globs work; they may not contain `/` or `:`.

                        Recognition is by name and resolved at runtime, so
                        nested repositories, submodules, and linked worktrees
                        are all covered by the same rule.
                      '';
                    };

                    stateDirs = mkOption {
                      default = {};
                      example = lib.literalExpression ''
                        {
                          claude-code.target = "~/.claude";
                        }
                      '';
                      description = ''
                        Persistent directories owned by the sandbox, typically
                        an LLM CLI's configuration and login state.

                        Each entry is stored on the host at
                        `''${XDG_STATE_HOME:-~/.local/state}/bubbllmwrap/<name>`
                        (created with mode `0700` if missing) and bound
                        read-write at its `target` inside the sandbox.

                        Use this instead of binding the host's own configuration
                        directory. Many CLIs run commands named in their config
                        (hooks, MCP servers, notifiers), so a writable bind of
                        the host's config lets the sandboxed CLI plant commands
                        that the host CLI later runs unsandboxed.
                      '';
                      type = types.attrsOf (types.submodule ({name, ...}: {
                        options = {
                          enable =
                            lib.mkEnableOption "this state directory"
                            // {default = true;};

                          name = mkOption {
                            type = types.strMatching "[A-Za-z0-9_][A-Za-z0-9._-]*";
                            default = name;
                            defaultText = lib.literalMD "the attribute name";
                            description = ''
                              Name of the directory under the host-side state
                              root. Environments that use the same name share
                              the directory.
                            '';
                          };

                          target = mkOption {
                            type = types.strMatching "(/|~/).*";
                            example = "~/.claude";
                            description = ''
                              Where to mount the directory inside the sandbox:
                              an absolute path, or a path starting with `~/`,
                              which is resolved against the home directory.
                            '';
                          };
                        };
                      }));
                    };
                  };
                };
              };
            };
          }));
      };
    };
  })

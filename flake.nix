{
  description = "Bubblewrap sandbox LLM CLI environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";

    flake-compat.url = "github:nix-community/flake-compat";
    flake-compat.flake = false;
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({
        config,
        flake-parts-lib,
        inputs,
        lib,
        moduleWithSystem,
        self,
        ...
      } @ localFlake: let
        flakeModule = flake-parts-lib.importApply ./nix/modules/flake localFlake;
      in {
        debug = true;

        systems = [
          "aarch64-linux"
          "x86_64-linux"
        ];

        imports = [
          inputs.flake-parts.flakeModules.flakeModules
          inputs.flake-parts.flakeModules.modules
          inputs.flake-parts.flakeModules.partitions
          flakeModule
          ./nix/packages.nix
        ];

        partitionedAttrs = lib.flip lib.genAttrs (lib.const "dev") [
          "apps"
          "checks"
          "devShells"
          "formatter"
        ];

        partitions = {
          dev = {
            extraInputsFlake = ./dev;
            module = {
              inputs,
              lib,
              ...
            }: {
              imports = [
                inputs.devshell.flakeModule
                inputs.treefmt-nix.flakeModule
                ./nix/checks.nix
              ];

              perSystem = {
                config,
                pkgs,
                system,
                ...
              }: {
                bubbllmwrap = bwrap: {
                  # Example of overriding an LLM profile's package: contributors
                  # get Claude Code from `claude-code-nix` (which tracks releases
                  # more closely) instead of nixpkgs. The canned profiles set
                  # `llm.package` with `mkDefault`, so a plain definition wins.
                  profiles.claude-code.llm.package = inputs.claude-code-nix.packages.${system}.claude-code;

                  # Contributor environment: Codex with this project's dev shell.
                  # Lives in the `dev` partition so that evaluating it doesn't
                  # pull the dev inputs into consumers' evaluations.
                  environments.devshellm = lib.const {
                    imports = [bwrap.config.profiles.codex];
                    hooks.enter = "source ${config.devShells.default}/env.bash";
                  };
                };

                apps.devshellm = {
                  type = "app";
                  program = lib.getExe config.bubbllmwrap.environments.devshellm.script;
                  meta.description = "Codex sandbox with this project's dev shell";
                };

                devshells.default = {
                  commands = [
                    {
                      package = pkgs.hello;
                    }

                    {
                      package = pkgs.act;
                    }

                    {
                      name = "mkoptdocs";
                      category = "maintenance";
                      command = ''
                        docs="$(${pkgs.nix}/bin/nix "$@" build --print-out-paths --no-link "''${PRJ_ROOT}#docs")" || exit

                        seen=0
                        while read -r path; do
                          seen="$((seen + 1))"
                          if [ "$seen" -gt 1 ]; then
                            printf 1>&2 -- 'error: more than one output path...\n'
                            exit 1
                          fi
                          install -Dm0644 "$path" "''${PRJ_ROOT}/docs/OPTIONS.md"
                        done <<DOCS
                        $docs
                        DOCS
                      '';
                      help = "Generate flake module documentation";
                    }
                  ];
                };

                treefmt = {
                  projectRootFile = "flake.nix";
                  programs.alejandra.enable = true;
                  programs.prettier = {
                    enable = true;
                    excludes = ["docs/OPTIONS.md"];
                  };
                  programs.shellcheck.enable = true;
                  programs.shfmt.enable = true;
                };
              };
            };
          };
        };

        perSystem = {config, ...}: {
          lib = {
            inherit (config.legacyPackages) evalSandbox;
          };

          bubbllmwrap = {modulesPath, ...}: {
            imports = [(modulesPath + "/canned.nix")];
          };
        };

        # Provide `lib.<system>` output (with stub option declaration for
        # `perSystem.lib`, via `adHoc = true`).
        # https://flake.parts/options/flake-parts.html?highlight=transposition#opt-transposition
        transposition.lib.adHoc = true;

        flake = {
          flakeModules = config.flake.modules.flake;

          modules = {
            flake = {
              default = flakeModule;
              bubbllmwrap = flakeModule;
            };
          };
        };
      });
}

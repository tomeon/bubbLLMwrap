{
  description = "Bubblewrap sandbox LLM CLI environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    claude-code-nix.url = "github:sadjow/claude-code-nix";
    claude-code-nix.inputs.nixpkgs.follows = "nixpkgs";

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
          "checks"
          "devShells"
          "formatter"
        ];

        partitions = {
          dev = {
            extraInputsFlake = ./dev;
            module = {inputs, ...}: {
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
                _module.args.pkgs = import inputs.nixpkgs {
                  inherit system;
                  overlays = [inputs.claude-code-nix.overlays.default];
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

        perSystem = {
          config,
          lib,
          self',
          system,
          ...
        }: {
          lib = lib.filterAttrs (lib.const lib.isFunction) config.legacyPackages;

          bubbllmwrap = {
            modulesPath,
            pkgs,
            ...
          } @ bwrap: {
            imports = [(modulesPath + "/canned.nix")];

            _module.args.pkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [inputs.claude-code-nix.overlays.default];
            };

            environments.devshellm = lib.const {
              imports = [bwrap.config.profiles.codex];
              hooks.enter = "source ${self'.devShells.default}/env.bash";
            };
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

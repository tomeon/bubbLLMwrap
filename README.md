# bubbLLMwrap

A Nix flake that runs LLM coding CLIs — [Claude Code](https://github.com/anthropics/claude-code)
and [Codex](https://github.com/openai/codex) — inside a [bubblewrap](https://github.com/containers/bubblewrap)
sandbox with filesystem isolation, [seccomp system-call filtering](#security-model),
and an [allowlist HTTP proxy](#security-model).

Environments are assembled from composable [profiles](#profiles) (one per LLM,
language, or tool group) using a NixOS-style module system, so you can mix and
match toolchains and [extend them](#customizing-environments) in your own
flake.

## Requirements

- Linux (`x86_64` or `aarch64`)
- Nix with flakes enabled (a `default.nix` flake-compat shim is provided for
  non-flake usage)

Claude Code is unfree software. Depending on your local Nix/nixpkgs
configuration, running a `claude-code-*` environment may require allowing
unfree packages — set `NIXPKGS_ALLOW_UNFREE=1` and pass `--impure` to `nix run`
(or the relevant `nix3` command). See [Quick start](#quick-start) for an
example.

## Configuration reference

Every environment option (packages, environment variables, bubblewrap args,
hooks, `llm`, `proxy`, `seccomp`, ...) is documented in the generated module
options reference:

**➡ [Module options reference](docs/OPTIONS.md)**

For regenerating that reference and other contributor workflows, see
[`docs/HACKING.md`](docs/HACKING.md).

## Quick start

Run a [canned environment](#canned-environments) in the current directory:

```shell-session
$ nix run github:tomeon/bubbLLMwrap#claude-code-go
```

If your Nix configuration does not already allow unfree packages, enable them
for this invocation:

```shell-session
$ NIXPKGS_ALLOW_UNFREE=1 nix run --impure github:tomeon/bubbLLMwrap#claude-code-go
```

Run against a specific project directory:

```shell-session
$ nix run github:tomeon/bubbLLMwrap#claude-code-go -- --sandbox-project-dir /path/to/project
```

Inside the sandbox the project is mounted read-write at the same path as in the
process that started the sandbox, and the LLM CLI launches automatically.

> There is no default/base environment — pick an `<llm>-<language>` target
> explicitly.

### Canned environments

Each environment is the cross-product of an LLM profile and a language/tooling
profile, named `<llm>-<language>`:

| LLM           | Languages / tooling                                  |
| ------------- | ---------------------------------------------------- |
| `claude-code` | `cpp`, `devops`, `go`, `js`, `nix`, `python`, `rust` |
| `codex`       | `cpp`, `devops`, `go`, `js`, `nix`, `python`, `rust` |

e.g. `claude-code-python`, `codex-rust`. List them with
`nix flake show github:tomeon/bubbLLMwrap`.

## Profiles

Profiles are modules merged into an [environment](#canned-environments).
Built-ins:

### LLM profiles

| Profile       | CLI                | Notable defaults                                                                                                                                                           |
| ------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude-code` | `pkgs.claude-code` | `--dangerously-skip-permissions`, web/`curl`/`wget` tools disabled, telemetry off, binds `~/.claude` & `~/.claude.json`, allows `api.anthropic.com`, `platform.claude.com` |
| `codex`       | `pkgs.codex`       | `--full-auto`, binds `~/.codex`, allows `api.github.com`, `auth.openai.com`, `chatgpt.com`                                                                                 |

Both build on `basic-tooling`, which provides: bash, coreutils, curl,
diffutils, dnsutils, fd, file, findutils, gawk, getent, git, gnugrep, gnused,
gnutar, gzip, iproute2, jq, jujutsu, less, man, patch, procps, ripgrep, rsync,
tree, unzip, util-linux, vim, which, yq, zip — and read-only binds for
`~/.gitconfig`, `~/.config/git`, and `~/.config/jj`.

### Language / tooling profiles

| Profile  | Tools                                                                             | Cache binds (read-only)                                                                               |
| -------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `nix`    | nix, alejandra                                                                    | `/nix/var/nix`, `/etc/nix`, `~/.config/nix`                                                           |
| `go`     | go, gopls, delve, golangci-lint, gotools, gofumpt                                 | `~/go/pkg/mod`, `~/.cache/go-build`, `~/.config/go`                                                   |
| `python` | python3, pip, virtualenv, poetry, ruff, pyright, uv                               | `~/.cache/{pip,pypoetry,uv}`, `~/.config/{pypoetry,uv}`, `~/.pip`, `~/.pypirc`                        |
| `rust`   | rustc, cargo, rustfmt, clippy, rust-analyzer                                      | `~/.cargo/{registry,git,config,config.toml,credentials}`                                              |
| `cpp`    | ccache, gcc, clang, cmake, gnumake, clang-tools                                   | `~/.cache/ccache`, `~/.ccache`                                                                        |
| `js`     | nodejs, yarn, pnpm, bun, typescript, typescript-language-server, eslint, prettier | `~/.npm`, `~/.yarn`, `~/.cache/yarn`, `~/.local/share/pnpm`, `~/.bun`, npm/yarn/pnpm rc & config dirs |
| `devops` | podman, kubernetes-helm, kubectl, opentofu, pgcli, cloudflared                    | `~/.kube`, `~/.aws`, `~/.cache/helm`, `~/.terraform.d`, `~/.docker`, `~/.config/{containers,helm}`    |

## Using it in your own flake

### With `flake-parts`

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    bubbllmwrap.url = "github:tomeon/bubbLLMwrap";

    # Optional: align inputs
    bubbllmwrap.inputs.nixpkgs.follows = "nixpkgs";
    bubbllmwrap.inputs.flake-parts.follows = "flake-parts";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];

      imports = [inputs.bubbllmwrap.flakeModules.bubbllmwrap];

      perSystem = {pkgs, ...}: {
        bubbllmwrap = {config, modulesPath, ...}: {
          # Pull in the built-in profiles (claude-code, codex, go, python, ...).
          imports = [(modulesPath + "/canned.nix")];

          # A custom profile...
          profiles.my-tooling.packages = with pkgs; [cowsay fortune];

          # ...combined with built-ins into a runnable environment.
          # Produces a `claude-code-mine` package output.
          environments.claude-code-mine.imports = with config.profiles; [
            claude-code
            go
            my-tooling
          ];
        };
      };
    };
}
```

The flake module exposes each environment as a `packages.<system>.<name>`
output (toggle with `bubbllmwrap.includePackages = false`).

### Plain flake (no `flake-parts`)

Use `evalSandbox`; an appropriate `pkgs` (with the Claude Code overlay) is
supplied for you:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bubbllmwrap.url = "github:tomeon/bubbLLMwrap";
  };

  outputs = {bubbllmwrap, ...}: let
    system = "x86_64-linux";

    sandbox = bubbllmwrap.lib.${system}.evalSandbox ({config, modulesPath, ...}: {
      imports = [(modulesPath + "/canned.nix")];

      environments.my-env = {pkgs, ...}: {
        imports = with config.profiles; [codex python];
        packages = with pkgs; [cowsay];
      };
    });
  in {
    packages.${system}.my-env = sandbox.config.environments.my-env.script;
  };
}
```

## Customizing environments

Environment options (see the [reference](docs/OPTIONS.md)) include:

- `packages` — extra packages on `PATH`
- `env` — environment variables (a string, or `{ value; quote; }` to control shell quoting)
- `args` — extra `bwrap` arguments (e.g. `--ro-bind-try` mounts)
- `hooks.{pre,enter,exit,post}` — shell run before / inside / after the sandbox
- `llm.{package,cmd,args,prompt}` — which CLI to run and how
- `proxy.{enable,allowList,port,extraConfig,extraRules}` — allowlist HTTP proxy ([glider](https://github.com/nadoo/glider))
- `seccomp.enable` — system-call filtering via `apply-seccomp` (default on)

Extend an existing environment without redefining it via `.extend`:

```nix
environments.claude-code-go-extra =
  config.environments.claude-code-go.extend ({pkgs, ...}: {
    packages = with pkgs; [air];
    proxy.allowList = ["proxy.golang.org"];
  });
```

## Security model

- **Process isolation** — `--unshare-all` and `--die-with-parent`; an isolated
  PID/network/IPC/etc. namespace.
- **System-call filtering** — the LLM CLI runs under
  [`apply-seccomp`](https://github.com/anthropic-experimental/sandbox-runtime)
  (blocks `AF_UNIX` socket abuse, `io_uring`, and ptrace of the proxy
  infrastructure); disable per-environment with `seccomp.enable = false`.
- **Filesystem** — only the project directory and
  `/tmp` are writable; `/nix/store`, `/etc/passwd`, `/etc/group`, and the
  profile cache directories are read-only; nothing else is visible.
- **Network** — all traffic flows through a [glider](https://github.com/nadoo/glider)
  proxy that allows only the domains in `proxy.allowList`; everything else is
  rejected.
- **Privilege** — runs as the host user with no added capabilities.
- **Telemetry** — disabled for the bundled CLIs.

## Contributing

Contributor workflows — dev shell, regenerating the options reference,
formatting, and tests — are documented in [`docs/HACKING.md`](docs/HACKING.md).

## License

MIT — see [LICENSE](LICENSE). Copyright © 2025 Mateusz Gawin, © 2026 Matt Schreiber.

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

> There is no default package; name an environment explicitly.

### Passing arguments

The launcher's arguments are:

```
[--sandbox-project-dir DIR] [--] [BWRAP_ARGS...] [-- LLM_ARGS...]
```

Anything after the first `--` (or after `--sandbox-project-dir DIR`) goes to
`bwrap`, up to the next `--`; what follows that goes to the LLM CLI. So passing
flags to the LLM takes two `--` in the launcher's own arguments, plus the one
`nix run` needs:

```shell-session
$ nix run github:tomeon/bubbLLMwrap#claude-code-go -- -- -- --model opus
$ nix run github:tomeon/bubbLLMwrap#claude-code-go -- --ro-bind-try ~/notes ~/notes -- --model opus
```

### First run: logging in

The `claude-code` and `codex` profiles do not share your host's `~/.claude`,
`~/.claude.json`, or `~/.codex` with the sandbox. Both CLIs run commands named
in their configuration (hooks, MCP servers, notifiers), so a writable bind of
the host's config would let a sandboxed session plant commands that your host
CLI later runs outside the sandbox. Instead, each profile gets its own
persistent directory on the host, bound at the usual path inside the sandbox:

| Profile       | Host directory                                              | Inside the sandbox                         |
| ------------- | ----------------------------------------------------------- | ------------------------------------------ |
| `claude-code` | `${XDG_STATE_HOME:-~/.local/state}/bubbllmwrap/claude-code` | `~/.claude` (with `CLAUDE_CONFIG_DIR` set) |
| `codex`       | `${XDG_STATE_HOME:-~/.local/state}/bubbllmwrap/codex`       | `~/.codex`                                 |

All `claude-code-*` environments share one directory, as do all `codex-*`
ones, so you log in once per CLI, inside the sandbox. Settings, `CLAUDE.md`,
commands, and agents you want in the sandbox go in that directory too. See
[`filesystem.stateDirs`](docs/OPTIONS.md) to add or change these directories.

A browser login that redirects to `localhost` can't reach the CLI inside the
sandbox; use the CLI's paste-the-code, device-code, or API-key login instead.
The sandbox starts with an empty environment. To pass an API key from your
host environment, name it in `envPassthrough`, e.g.
`envPassthrough = ["ANTHROPIC_API_KEY"];`.

### Canned environments

Each environment is the cross-product of an LLM profile and a language/tooling
profile, named `<llm>-<language>`. The bare `<llm>` environments have
`basic-tooling` only:

| LLM           | Languages / tooling                                          |
| ------------- | ------------------------------------------------------------ |
| `claude-code` | (none), `cpp`, `devops`, `go`, `js`, `nix`, `python`, `rust` |
| `codex`       | (none), `cpp`, `devops`, `go`, `js`, `nix`, `python`, `rust` |

e.g. `claude-code`, `claude-code-python`, `codex-rust`. List them with
`nix flake show github:tomeon/bubbLLMwrap`.

## Profiles

Profiles are modules merged into an [environment](#canned-environments).
Built-ins:

### LLM profiles

| Profile       | CLI                | Notable defaults                                                                                                                                                                                               |
| ------------- | ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `claude-code` | `pkgs.claude-code` | `--dangerously-skip-permissions`, web/`curl`/`wget` tools disabled, telemetry off, [own config directory](#first-run-logging-in), allows `api.anthropic.com`, `mcp-proxy.anthropic.com`, `platform.claude.com` |
| `codex`       | `pkgs.codex`       | `--full-auto`, [own config directory](#first-run-logging-in), allows `api.github.com`, `auth.openai.com`, `chatgpt.com`                                                                                        |

Both build on `basic-tooling`, which provides: bash, coreutils, curl,
diffutils, dnsutils, fd, file, findutils, gawk, getent, git, gnugrep, gnused,
gnutar, gzip, iproute2, jq, jujutsu, less, man, patch, procps, ripgrep, rsync,
tree, unzip, util-linux, vim, which, yq, zip — and read-only binds for
`~/.gitconfig`, `~/.config/git`, and `~/.config/jj`.

### Language / tooling profiles

| Profile  | Tools                                                                             | Cache binds (read-only)                                                                               |
| -------- | --------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `nix`    | nix, alejandra                                                                    | `/etc/nix`, `~/.config/nix` (not `/nix/var/nix`, which holds the daemon socket)                       |
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
          # Produces a `claude-code-mine` package output. Environment
          # definitions that use `imports` must be functions; a plain attrset
          # only sets options.
          environments.claude-code-mine = _: {
            imports = with config.profiles; [
              claude-code
              go
              my-tooling
            ];
          };
        };
      };
    };
}
```

The flake module exposes each environment as a `packages.<system>.<name>`
output (toggle with `bubbllmwrap.includePackages = false`).

### Plain flake (no `flake-parts`)

Use `evalSandbox`; an appropriate `pkgs` (bubbLLMwrap's nixpkgs with the Claude
Code overlay) is supplied for you. Claude Code is unfree, so allow unfree
packages as described [above](#requirements), or set `_module.args.pkgs` to
your own nixpkgs instance:

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
- `env` — environment variables; plain strings are literal, `{ value; quote = false; }` is shell syntax (e.g. `~`, `$VAR`)
- `envPassthrough` — host environment variables to keep (the sandbox otherwise starts with an empty environment)
- `args` — extra `bwrap` arguments (e.g. `--ro-bind-try` mounts)
- `hooks.{pre,enter,exit,post}` — shell run before / inside / after the sandbox
- `llm.{package,cmd,args,prompt}` — which CLI to run and how
- `proxy.{enable,allowList,extraConfig,extraRules}` — allowlist HTTP proxy ([glider](https://github.com/nadoo/glider))
- `seccomp.enable` — system-call filtering via `apply-seccomp` (default on)
- `seccomp.denyTerminalInjection` — block terminal input injection for the whole sandbox (default on)
- `filesystem.{denyVcsMetadata,vcsMetadataDirs}` — lock version-control metadata read-only (default on)
- `filesystem.stateDirs` — persistent directories owned by the sandbox, such as an LLM's config

`.extend` applies extra modules to an existing environment and returns the
result, e.g. to build a variant's script without defining a new environment:

```nix
packages.claude-code-go-extra =
  (config.environments.claude-code-go.extend ({pkgs, ...}: {
    packages = with pkgs; [air];
    proxy.allowList = ["proxy.golang.org"];
  })).script;
```

The result is an evaluated configuration, not a module, so it can't be the
definition of another entry in `environments`. For a new named environment,
import the same profiles:

```nix
environments.claude-code-go-extra = {pkgs, ...}: {
  imports = with config.profiles; [claude-code go];
  packages = with pkgs; [air];
  proxy.allowList = ["proxy.golang.org"];
};
```

## Security model

The LLM CLI is treated as untrusted: prompt injection or hostile repository
content can steer it.

- **Process isolation** — `--unshare-all` and `--die-with-parent`; an isolated
  PID/network/IPC/etc. namespace.
- **System-call filtering** — the LLM CLI runs under
  [`apply-seccomp`](https://github.com/anthropic-experimental/sandbox-runtime)
  (blocks `AF_UNIX` socket creation and `io_uring`, and hides the sandbox's
  own helper processes); disable per-environment with `seccomp.enable = false`.
  A second filter covers the whole sandbox and refuses the `TIOCSTI` and
  `TIOCLINUX` ioctls, so nothing inside can push keystrokes into your terminal
  for the host shell to run after exit (CVE-2017-5226).
- **Filesystem** — the sandbox root is a fresh tmpfs, writable but discarded on
  exit. The project directory is mounted read-write. `/nix/store`,
  `/etc/passwd`, `/etc/group`, and the profiles' config and cache binds are
  read-only. The LLM's [own config directory](#first-run-logging-in) is
  read-write. Nothing else from the host is visible.
- **Version-control metadata** — every `.git` and `.jj` found under the project
  at launch (including submodule and worktree gitlink files) is mounted
  read-only, so the CLI can't add hooks or change repository config. If one is
  reached through a symlink inside the project, which the CLI could replace,
  the sandbox refuses to start. This can't stop the CLI from _creating_ a new
  repository elsewhere in the project, which host-side `git` would then honor
  (e.g. its `core.fsmonitor`), and it doesn't protect hooks that live in the
  working tree (`core.hooksPath = .husky`, symlinked hooks, `pre-commit`
  configs). Review what a session changed before running VCS commands in it on
  the host.
- **Network** — the sandbox has its own network namespace, so all IP traffic
  flows through a [glider](https://github.com/nadoo/glider) proxy that allows
  only the domains in `proxy.allowList` (and their subdomains); everything else
  is rejected. With `proxy.enable = false` there is no IP network at all.
  Unix sockets are a separate channel: a read-only bind doesn't stop
  `connect(2)`, so a host socket reachable through a bind (for example the Nix
  daemon's, under `/nix/var/nix`) is a way out that the proxy doesn't see. The
  `apply-seccomp` filter blocks creating Unix sockets, so this only applies
  with `seccomp.enable = false`. No built-in profile binds such a socket.
- **Privilege** — runs as the host user with no added capabilities.
- **Telemetry** — disabled for the bundled CLIs.

Not covered: code you later run yourself (build scripts, tests, `flake.nix`) is
whatever the LLM wrote. Language profiles also bind some credential files
read-only (`~/.npmrc`, `~/.pypirc`, `~/.cargo/credentials`, and `~/.aws` etc.
in `devops`); if you allowlist the matching registry, the CLI can use them. See
[`TODO.md`](TODO.md) for planned work.

## Contributing

Contributor workflows — dev shell, regenerating the options reference,
formatting, and tests — are documented in [`docs/HACKING.md`](docs/HACKING.md).

## License

MIT — see [LICENSE](LICENSE). Copyright © 2025 Mateusz Gawin, © 2026 Matt Schreiber.

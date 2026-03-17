# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Project overview

**bubbLLMwrap** is a Nix flake that runs LLM coding CLIs (Claude Code and Codex)
inside a [bubblewrap](https://github.com/containers/bubblewrap) sandbox. It
provides filesystem isolation, seccomp system-call filtering, and an allowlist
HTTP proxy. Environments are assembled from composable **profiles** using a
NixOS-style module system, and the flake is meant to be imported and extended by
other flakes.

This project was forked from `matgawin/bubblewrap-claude` and substantially
rebuilt; the function-based API (`mkSandbox`, `deriveProfile`, `mkDevShell`) from
that project no longer exists. The interface is now a module schema.

## Architecture

The flake is built with [flake-parts](https://flake.parts/). The two
user-facing concepts are:

- **profiles** (`config.profiles.<name>`) — named, mix-and-match modules
  (deferred modules) describing a group of related options (an LLM, a language
  toolchain, a set of tools).
- **environments** (`config.environments.<name>`) — a profile composition that
  produces a runnable sandbox `script`. Each environment's `script` is exported
  as a `packages.<system>.<name>` output.

Key files:

- `flake.nix`: flake-parts entrypoint. Declares systems, imports the flake
  module and packages, sets up the `dev` partition (dev shell, formatter,
  checks), and configures the project's own `bubbllmwrap` environments.
- `nix/modules/flake/default.nix`: the flake-parts integration module exported
  as `flakeModules.bubbllmwrap` (and `.default`). Adds the `perSystem.bubbllmwrap`
  option and maps each environment to a package output.
- `nix/lib/modules/options.nix`: the sandbox option schema (`profiles`,
  `environments.<name>.{packages,env,args,hooks,llm,proxy,seccomp,extend,script,…}`).
  This is the source of truth for `docs/OPTIONS.md`.
- `nix/lib/modules/eval-args.nix`: assembles the module list and `specialArgs`
  (notably `modulesPath`) for evaluation.
- `nix/pkgs/eval-sandbox/default.nix`: backs `lib.<system>.evalSandbox`, the
  entrypoint for consumers not using flake-parts.
- `nix/modules/bubbllmwrap/canned.nix`: auto-discovers every profile under
  `profiles/` and builds the canned `<llm>-<language>` environments as the
  cross-product of LLM and language profiles.
- `nix/modules/bubbllmwrap/profiles/`: the built-in profiles, grouped into
  `llm/`, `language/`, and `tooling/`.
- `nix/pkgs/`: the sandbox launcher (`sandbox/`), the glider proxy
  (`sandbox-proxy/`), the `apply-seccomp` wrapper, and supporting packages.

## Profiles and environments

Built-in profiles:

- LLM: `claude-code`, `codex` (both import `basic-tooling`)
- Tooling: `basic-tooling` (base utilities, git/jj config binds), `devops`
- Language: `cpp`, `go`, `js`, `nix`, `python`, `rust`

`canned.nix` produces the cross-product environments `<llm>-<language>`, e.g.
`claude-code-go`, `codex-python`. There is **no** bare `claude-code`/`codex`
environment and **no** default package — environments are always named
`<llm>-<language>`.

An environment is defined by importing profiles and overriding options:

```nix
environments.my-env = {config, pkgs, ...}: {
  imports = with config.profiles; [claude-code go];
  packages = with pkgs; [air];
  proxy.allowList = ["proxy.golang.org"];
};
```

Use `config.environments.<name>.extend [ module… ]` to derive a new environment
from an existing one without redefining it.

### Option conventions

- `args` and `env` values accept either a plain string or a
  `{ value; quote; }` submodule. `quote = true` shell-quotes the value; leave it
  `false` (the default) when you want shell interpolation (e.g. `~` or `$VAR`).
- `hooks.{pre,post}` run on the host before/after `bwrap`; `hooks.{enter,exit}`
  run inside the sandbox.
- `proxy.allowList` is the set of domains reachable from inside the sandbox;
  everything else is rejected by glider.
- `seccomp.enable` (default `true`) runs the CLI under `apply-seccomp`.

## Commands

```bash
# Enter the dev shell (formatter, linters, helper commands)
nix develop          # or: direnv allow

# Run a canned environment in the current directory
nix run .#claude-code-go

# Allow unfree (Claude Code) if your Nix config doesn't already
NIXPKGS_ALLOW_UNFREE=1 nix run --impure .#claude-code-go

# Run against a specific project directory
nix run .#claude-code-go -- --sandbox-project-dir /path/to/project

# List all environments / packages
nix flake show

# Format the tree (treefmt: alejandra, prettier, shfmt, shellcheck)
nix fmt

# Run the VM tests
nix flake check
nix build .#checks.x86_64-linux.eval-sandbox -L
```

## Module options documentation

`docs/OPTIONS.md` is **generated** from `nix/lib/modules/options.nix`. After
changing any option, regenerate and commit it:

```bash
nix build .#docs     # builds the CommonMark output
# or, inside the dev shell:
mkdocs               # builds .#docs and installs it to docs/OPTIONS.md
```

Do not hand-edit `docs/OPTIONS.md` (it is also excluded from prettier).

## Conventions

- The `dev` partition isolates contributor-only inputs (devshell, treefmt,
  checks) so consumers of the flake don't pull them in. Dev-only outputs
  (`checks`, `devShells`, `formatter`) live there.
- New profiles go under `nix/modules/bubbllmwrap/profiles/<group>/<name>.nix`
  and are auto-discovered by `canned.nix` — add the name to the `language`/`llm`
  lists in `canned.nix` if it should participate in the canned cross-product.
- Read-only cache/config binds use `--ro-bind-try` so a missing host path is not
  an error.
- See `docs/HACKING.md` for contributor workflows and `TODO.md` for planned
  hardening work (mandatory deny paths, proxy env fixes, symlink validation).

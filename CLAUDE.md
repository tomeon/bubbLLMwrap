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
  as a `packages.<system>.<name>` output (unless its `enable` is `false`).

Key files:

- `flake.nix`: flake-parts entrypoint. Declares systems, imports the flake
  module and packages, sets up `pkgs` (nixpkgs plus the Claude Code overlay),
  sets up the `dev` partition (dev shell, formatter, checks, and the
  `devshellm` contributor app), and configures the project's own `bubbllmwrap`
  environments.
- `nix/modules/flake/default.nix`: the flake-parts integration module exported
  as `flakeModules.bubbllmwrap` (and `.default`). Adds the `perSystem.bubbllmwrap`
  option and maps each environment to a package output.
- `nix/lib/modules/options.nix`: the sandbox option schema (`profiles`,
  `environments.<name>.{packages,env,args,hooks,llm,proxy,seccomp,filesystem,extend,script,…}`).
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
- `nix/pkgs/`: the sandbox launcher (`sandbox/`, with shared shell functions
  in `sandbox-lib/`), the glider proxy (`sandbox-proxy/`), the `apply-seccomp`
  wrapper, the whole-sandbox seccomp filter (`sandbox-seccomp-filter/`), and
  supporting packages.

## Profiles and environments

Built-in profiles:

- LLM: `claude-code`, `codex` (both import `basic-tooling`)
- Tooling: `basic-tooling` (base utilities, git/jj config binds), `devops`
- Language: `cpp`, `go`, `js`, `nix`, `python`, `rust`

`canned.nix` produces the cross-product environments `<llm>-<language>`, e.g.
`claude-code-go`, `codex-python`, plus bare `claude-code` and `codex`
environments with `basic-tooling` only. There is **no** default package.

An environment is defined by importing profiles and overriding options.
Profiles live in the enclosing configuration's `config`; inside an environment
module, `config` is the environment's own, while `pkgs` is passed through:

```nix
{config, ...}: {
  environments.my-env = {pkgs, ...}: {
    imports = with config.profiles; [claude-code go];
    packages = with pkgs; [air];
    proxy.allowList = ["proxy.golang.org"];
  };
}
```

`config.environments.<name>.extend [ module… ]` applies extra modules and
returns the resulting configuration (e.g. to take its `.script`). It is not a
module, so it can't define another `environments` entry; for a new named
environment, import the same profiles.

### Option conventions

- `args` and `env` values accept either a plain string or a
  `{ value; quote; }` submodule. `quote = true` passes the value literally;
  `quote = false` inserts it into the launcher as shell syntax (e.g. `~` or
  `$VAR`, expanded on the host). The defaults differ: `env` values are literal
  (`quote = true`), while `args` are shell syntax (`quote = false`) because
  profiles rely on `~` expansion in bind paths.
- `envPassthrough` names host variables kept across `--clearenv`;
  `basic-tooling` passes `TERM`/`COLORTERM` and sets `LANG=C.UTF-8`.
- `hooks.{pre,post}` run on the host before/after `bwrap`; `hooks.{enter,exit}`
  run inside the sandbox.
- `proxy.allowList` is the set of domains reachable from inside the sandbox;
  everything else is rejected by glider.
- `seccomp.enable` (default `true`) runs the CLI under `apply-seccomp`;
  `seccomp.denyTerminalInjection` (default `true`) applies a separate filter
  to the whole sandbox that blocks `TIOCSTI`/`TIOCLINUX`.
- `filesystem.denyVcsMetadata` (default `true`) mounts every `.git`/`.jj`
  found under the project read-only, including gitlink files, and refuses to
  start if one is reached through a symlink inside the project.
- `filesystem.stateDirs.<name>.target` gives the sandbox its own persistent
  directory (on the host under `${XDG_STATE_HOME:-~/.local/state}/bubbllmwrap`).
  The LLM profiles use it for their config instead of binding the host's
  `~/.claude`/`~/.codex`, which the host CLI would execute commands from.
- Environments are a plain `types.submodule`: an attrset definition only sets
  options, so a definition that uses `imports` (or declares options) must be a
  function, e.g. `environments.foo = _: { imports = [ … ]; };`.

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
mkoptdocs            # builds .#docs and installs it to docs/OPTIONS.md
```

Do not hand-edit `docs/OPTIONS.md` (it is also excluded from prettier).

## Conventions

- The `dev` partition isolates contributor-only inputs (devshell, treefmt,
  checks) so consumers of the flake don't pull them in. Dev-only outputs
  (`apps`, `checks`, `devShells`, `formatter`) live there.
- New profiles go under `nix/modules/bubbllmwrap/profiles/<group>/<name>.nix`
  and are auto-discovered by `canned.nix` — add the name to the `language`/`llm`
  lists in `canned.nix` if it should participate in the canned cross-product.
- Read-only cache/config binds use `--ro-bind-try` so a missing host path is not
  an error.
- See `docs/HACKING.md` for contributor workflows and `TODO.md` for the threat
  model and planned hardening work.

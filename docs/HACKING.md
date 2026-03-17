# Hacking on bubbLLMwrap

## Development shell

`nix develop` (or `direnv allow` if you use [direnv](https://direnv.net/))
drops you into a dev shell with the formatter, linters, and helper commands
defined for this project. The shell lives in the `dev` partition
(`dev/flake.nix` plus the `dev` partition in `flake.nix`), so its inputs don't
burden consumers of the flake.

## Regenerating the module options reference

[`docs/OPTIONS.md`](OPTIONS.md) is generated from the option declarations in
`nix/lib/modules/options.nix`. Regenerate it whenever you add, remove, or
change an option:

```shell-session
$ nix build .#docs
```

This builds the CommonMark output as a store path. From inside the dev shell
the `mkoptdocs` builds `.#docs` and installs the result over the SCM-tracked
copy at `docs/OPTIONS.md`:

```shell-session
$ mkoptdocs
```

Commit the regenerated `docs/OPTIONS.md` together with the option change.

## Formatting

Formatting is handled by [treefmt](https://github.com/numtide/treefmt) via
[treefmt-nix](https://github.com/numtide/treefmt-nix):
[alejandra](https://github.com/kamadorueda/alejandra) for Nix,
[Prettier](https://prettier.io/) for Markdown and friends, and
[shfmt](https://github.com/mvdan/sh) and
[ShellCheck](https://www.shellcheck.net/) for shell scripts. `docs/OPTIONS.md`
is excluded from prettier because it is generated.

```shell-session
$ nix fmt
```

## Tests

NixOS VM tests live under [`nix/checks`]().

Run the whole suite:

```shell-session
$ nix flake check
```

Or run a single check:

```
$ nix build .#checks.x86_64-linux.eval-sandbox -L
```

See [`nix/checks/README.md`](../nix/checks/README.md) for what the tests cover.

## Project layout

| Path                                 | Purpose                                                                              |
| ------------------------------------ | ------------------------------------------------------------------------------------ |
| `flake.nix`                          | flake-parts entrypoint; wires modules, partitions, and package outputs               |
| `nix/modules/flake/`                 | flake-parts integration module exported as `flakeModules.bubbllmwrap`                |
| `nix/lib/modules/`                   | the sandbox option schema (`options.nix`) and the `evalSandbox` plumbing             |
| `nix/modules/bubbllmwrap/profiles/`  | built-in profiles (`llm/`, `language/`, `tooling/`)                                  |
| `nix/modules/bubbllmwrap/canned.nix` | auto-discovers profiles and builds the `<llm>-<language>` environments               |
| `nix/pkgs/`                          | the sandbox launcher, glider proxy, `apply-seccomp` wrapper, and supporting packages |

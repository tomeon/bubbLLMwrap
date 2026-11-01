# TODO

Hardening, correctness, and maintenance work. Items are marked `[ ]`
(outstanding), `[~]` (partially done), or `[x]` (done — kept briefly for
context, remove once stale). Severity tags (**high** / **medium** / **low**)
are relative to the threat model below. Item numbers are stable; finished items
move to [Completed](#completed). Line references are as of the commit that last
changed this file.

## Threat model

The LLM CLI is untrusted: prompt injection or hostile repository content can
steer it. The sandbox should stop it from (a) touching host state it wasn't
given, (b) reaching the network outside `proxy.allowList`, and (c) planting
anything the host runs _implicitly_ after the session ends (VCS hooks, tool
configs, terminal input). Code the user knowingly runs later (`make`, test
suites, `flake.nix`) is the unavoidable cost of letting an LLM write code, and
is out of scope. Most items below concern (c).

Design rule for (c): ship mechanisms that work the same for every tool, and
leave the policy (which paths matter) to the user. Avoid per-tool deny lists
that this project would have to keep up to date.

## Before merging to `main`

- [ ] **Watch the first CI run on this branch.** The VM test needs KVM. Confirm
      the `ubuntu-24.04-arm` runner provides it. The VM test's new assertions (VCS
      lock, state directories, `TIOCSTI`) were validated by running the same
      environments outside a VM, not inside one.
- [ ] **Decide on item 17** (logging in inside the sandbox), since the
      `claude-code` and `codex` profiles no longer share the host's login.

Everything else that was listed here is done; see [Completed](#completed).

## Outstanding

### [~] 1. Post-session execution via the project directory — **high**

**Current state.** `filesystem.denyVcsMetadata` (on by default) finds every
entry named in `filesystem.vcsMetadataDirs` (default `.git`, `.jj`) under the
project at launch and `--ro-bind`s it over the writable project bind
(`nix/pkgs/sandbox-lib/sandbox-lib.sh`, `__sandbox_add_vcs_deny_args`). Gitlink
files (submodules, linked worktrees) are locked along with the directory they
point to. Binds are mapped from the resolved host path to the path the project
is mounted at, so symlinked project paths are covered. Finding metadata roots by
name, instead of keeping a per-file deny list, covers hooks, `core.fsmonitor`,
aliases, and anything else inside a root without listing them, and supporting a
new VCS takes one list entry.

**Inherent limitation.** Read-only binds only protect metadata roots that exist
at launch. They can't stop the CLI from creating new ones, and `bwrap` has no
way to deny a path by name before it exists. Reproduced: with `sub/.git`
locked, `mv sub sub2 && mkdir -p sub/.git/hooks` succeeds, because only the
mount point itself is `EBUSY`. That leaves a planted repo at the original path
on the host. Simpler variants:

- `mkdir any/subdir/.git`.
- `./.git` when the project is a subdirectory of a repo. The new `.git` then
  shadows the real repo for host `git` commands run there.

git runs `core.fsmonitor` from repo config
([git-config](https://git-scm.com/docs/git-config#Documentation/git-config.txt-corefsmonitor)),
so a plain `git status` is enough to trigger it, including one run by a shell
prompt.

srt covers not-yet-existing paths by mounting `/dev/null`, or an empty
read-only directory, at the first missing component of each path on a fixed
list
([srt README](https://github.com/anthropic-experimental/sandbox-runtime#readme)).
That only works for paths named in advance. It is exactly the per-path deny
list the design rule rules out, and it still can't cover "a `.git` in any
subdirectory".

**Other problems with the current lock:**

- jj snapshots the working copy (writing to `.jj`) on almost every command, so
  with `.jj` locked most `jj` commands probably fail inside the sandbox (to
  verify; `--ignore-working-copy` may be the workaround). The option
  description now says so.
- The `find` at `sandbox-lib.sh:239` walks the whole tree on every launch, with
  no `-xdev` and no depth or exclude limits. That is slow on large trees
  (`node_modules`, `target/`), and it crosses into other mounted filesystems.
  Consider `-xdev` and an optional depth limit or exclude list; both trade
  coverage for speed.
- A `.git` that is a _symlink_ to a directory inside the project is locked at
  its target, but the symlink itself can still be replaced.

**Next steps** (agreed: A, then B). Neither needs per-tool lists, and both
leave policy to the user.

- **A. Session change report (cheap, works for any VCS).** At launch, create a
  marker file in the host-side runtime directory. After `bwrap` exits, list
  every changed path with `find "$project" -xdev -cnewer "$marker"`. An
  unprivileged process can't set ctime: it updates on every inode change, and
  `utimensat` only sets atime and mtime. So the sandbox can't hide renames, new
  directories, or edits. Highlight entries that match user-set patterns
  (default: `vcsMetadataDirs`, perhaps every dot-entry). This detects rather
  than prevents, but it makes planted files hard to miss for every tool at
  once. Ship it as a `filesystem.changeReport` option or as a reusable
  `hooks.post` snippet.
- **B. Overlay mode (thorough, works for any VCS).** Mount the project with
  `--overlay-src "$project" --overlay "$upper" "$work" "$project"`. Every write
  then goes to a per-session upper directory, and the host tree is untouched
  until the user reviews and applies the changes. In this mode the VCS lock
  isn't needed (the CLI can even commit, into the overlay). It also covers IDE
  configs, `.envrc`, nested repos, and anything else, with no lists.
  Requirements:
  - `bwrap` 0.11.0 or later, not installed setuid
    ([NEWS](https://github.com/containers/bubblewrap/blob/main/NEWS.md),
    [`bwrap(1)`](https://github.com/containers/bubblewrap/blob/main/bwrap.xml)).
    The pinned nixpkgs has 0.12.0.
  - Kernel support for overlayfs in user namespaces (mainline since 5.11,
    [patch](https://lore.kernel.org/all/20201207163255.564116-11-mszeredi@redhat.com/)).
  - Upper and work directories outside the project, because `bwrap` forbids
    overlay directories that are ancestors of one another.

  Most of the work is on the apply side: list the changes (whiteouts are
  deletions), flag the same user patterns as in A, and copy files without
  running anything from the upper directory. Possible interface:
  `filesystem.projectMode = "bind" | "overlay"` plus a
  `--sandbox-review <session>` subcommand.

- **Keep the current lock** as the default in `bind` mode. Its option
  description states that it only stops existing metadata roots from being
  modified.

### [~] 4. Project directory validation — **medium**

Done: the project path is made absolute (relative `--sandbox-project-dir`
values used to mount the project over the sandbox root), symlinks are resolved
for the bind source while the mount point keeps the path as given, and a
missing `--sandbox-project-dir` value gets a clear error
(`__sandbox_resolve_project_dir` in `sandbox-lib.sh`).

Remaining: **dangerous roots.** Running in `$HOME` or `/` binds the whole tree
read-write, including `~/.bashrc`, `~/.ssh`, and every tool config. That is
easy to do by accident, because the project defaults to `$PWD`. After
resolving symlinks, refuse `/`, `$HOME`, and any ancestor of `$HOME` unless the
user passes an explicit override flag.

### [ ] 5. Canned profiles mount publishing credentials — **medium**

Several profiles bind credential files read-only by default:

- `~/.cargo/credentials` (`profiles/language/rust.nix:23-25`)
- `~/.pypirc` (`profiles/language/python.nix:31-33`)
- `~/.npmrc` (`profiles/language/js.nix:27-29`)
- `~/.aws`, `~/.kube`, and `~/.docker` (`profiles/tooling/devops.nix`)

The proxy limits where these can be sent. But the obvious way to make these
profiles useful is to allowlist the registry (`registry.npmjs.org`,
`upload.pypi.org`, `crates.io`), and at that point an injected agent can
publish packages as the user. This exposure comes from the project's own
defaults rather than from anything users configure. The README's security
model now mentions it.

Make credential binds opt-in, either as a per-profile sub-option or as
structured binds that are off by default (item 8). Keep caches and non-secret
config on by default. Two details: `~/.npmrc` holds both registry config and
tokens, and current cargo uses `credentials.toml`.

### [ ] 6. The `nix` profile exposes the Nix daemon socket — **medium**

The `nix` profile binds `/nix/var/nix` (`profiles/language/nix.nix:7-9`),
which includes `daemon-socket/socket`. A read-only bind doesn't stop
`connect(2)` to a Unix socket; reproduced with `bwrap --unshare-all`. With
`seccomp.enable = false`, the CLI can talk to the daemon, whose substitutions
and fixed-output builds have network access outside the proxy. With seccomp
on, `socket(AF_UNIX)` is blocked, so `nix` commands that need the daemon
probably fail. Check what the profile actually supports, and bind only the
subpaths it needs. (The `seccomp.enable` description now warns about sockets
reachable through binds.)

### [ ] 7. Passing variables through `--clearenv` — **medium**

`sandbox.sh:128` uses `--clearenv`, so `TERM`, `COLORTERM`, `LANG`, `LC_*`,
and `TZ` are unset inside the sandbox (reproduced). TUIs will likely degrade,
and `vim`/`less` will complain. Add an explicit passthrough option, e.g.
`envPassthrough = ["TERM" "COLORTERM" "LANG" "LC_ALL" "TZ"]`, emitted as
`--setenv` with the host's values. It would also be the cleanest way to pass
`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, or Claude Code's
`CLAUDE_CODE_OAUTH_TOKEN`
([env vars](https://code.claude.com/docs/en/env-vars)); for now the README
shows interpolating them through `env`.

### [~] 8. `args`/`env` quoting is unsafe by default — **medium**

Done: `claude-code.nix` used `lib.escapeRegex` to shell-escape
`--disallowedTools`, which split rules containing spaces; it now uses
`lib.escapeShellArg`.

Remaining: plain-string `args` and `env` values default to `quote = false`,
and they are spliced unquoted into a bash array literal
(`sandbox/default.nix:86`). So `env.GREETING = "hello world"` becomes two
words. `bwrap` takes `world` as the program to run and everything after it as
that program's arguments. The project bind, `--chdir`, and `HOME` silently
disappear, and the launch fails. Options:

- Make `quote = true` the default, so shell interpolation is the opt-in.
- Add a structured `binds` option: an attrset keyed by path, with entries like
  `{ source; mode = "ro" | "rw"; optional = true; enable = true; }`. The
  generator emits correctly quoted arguments and does the `$HOME` expansion
  itself. Profiles stop writing argument triples by hand. Users can disable one
  inherited bind (`binds."~/.aws".enable = false`) instead of `mkForce`-ing the
  whole `args` list, and item 5 follows directly.

### [~] 9. Proxy: remaining issues — **low**

_(Was "proxy environment variable improvements"; the variables themselves are
done.)_

- `extraRules` is appended once per allowlisted domain, and dropped entirely
  when the allowlist is empty (`sandbox-proxy/default.nix:20-27`). It should be
  appended once.
- `proxy.port` is documented but never read; the in-sandbox ports are fixed at
  3128 and 1028. Remove the option or implement it.
- Both `GIT_SSH_COMMAND` values (`sandbox/default.nix:154`, `:199`) call `ssh`
  and `socat`, and neither is on the sandbox `PATH` (`:50`); `socat` exists
  only inside the s6 service wrappers. Use store paths, or drop the variable.
  The `# TODO` at `:196` is stale.
- Document how the allowlist matches in the option description. glider matches
  a domain and all of its subdomains, ignores the port, and doesn't resolve
  names that match no rule, so there's no DNS side channel
  ([`rule/proxy.go`](https://github.com/nadoo/glider/blob/main/rule/proxy.go)).
  Also document that filtering at the `CONNECT` level can't see the TLS SNI or
  `Host` header. An allowlisted domain on a shared CDN is only as narrow as
  that CDN's protection against domain fronting.

### [ ] 10. Parent proxy chaining — **low**

**The problem**: Developers behind corporate proxies can't use the sandbox,
because glider's allowed domains use `forward=direct://` instead of chaining
through the corporate proxy, and `--clearenv` removes
`HTTP_PROXY`/`HTTPS_PROXY`.

**What's involved**: glider already supports upstream proxy forwarders. In
`sandbox-proxy/default.nix`, the rulefile hardcodes `forward=direct://` and
the config `forward=reject://`. The change is:

```
forward=http://corporate-proxy:8080
domain=api.anthropic.com
```

instead of `forward=direct://` for allowed domains, keeping `reject://` as the
default for everything else. At the module level:

- Add a `proxy.parentProxy` option (a URL, or a `{ http, https, noProxy }`
  attrset) in `nix/lib/modules/options.nix`.
- Alternatively, read `HTTP_PROXY`/`HTTPS_PROXY` at runtime in
  `sandbox-proxy.sh`, which runs on the host. The rulefile is currently a store
  path, so that needs runtime templating.

Keep `forward=direct://` when no parent proxy is set.

### [~] 11. Test coverage — **medium**

Done: the VM test (`nix/checks/eval-sandbox.nix`) now also checks that writes
under `.git/hooks` fail, that each state directory is writable, and that
`TIOCSTI` is refused (probed under `script`, so the probe has a controlling
terminal).

Remaining cases:

- `proxy.enable = false` (the rcfile branches that create `down` files) and
  `seccomp.enable = false`. Confirm the nested namespace from `apply-seccomp`
  doesn't interfere with s6 or the socat bridge.
- Seccomp actually blocking `socket(AF_UNIX)`.
- The VCS lock beyond the basic case: a nested repo; a submodule or worktree
  gitlink; a symlinked project path; a self-referencing gitlink. (All verified
  by hand outside a VM; see the commit that fixed them.)
- A project path containing spaces, a relative `--sandbox-project-dir`, and
  passing arguments through to the LLM (verified by hand outside a VM).
- One real toolchain operation per language profile (e.g. `go build`,
  `cargo build --offline`); see item 16.

### [~] 12. Module interface and public API — **medium**

Done before merge: see [Completed](#completed). Remaining:

- `llm.package` defaults to `pkgs.coreutils` (`options.nix:328`), so an
  environment without an LLM profile builds a script that runs `coreutils`.
  Make the option required, or fall back to an interactive shell.
- `llm.prompt` is set with `config =` at normal priority (`options.nix:373`),
  so a user's prompt is appended to the default instead of replacing it. If
  that isn't intended, set it with `default` instead.
- The launcher derivations are built from bubbLLMwrap's own nixpkgs
  (`self'.legacyPackages`), while profile packages come from the environment's
  `pkgs`. So consumers' overlays don't reach `bash`, `s6`, `socat`, or
  `apply-seccomp`, and a closure can contain two nixpkgs instances. Consider
  building the launcher from the environment's `pkgs`.
- `debug = true` (`flake.nix:28`) adds `debug` and `allSystems` outputs for
  every consumer, and makes `nix flake check` warn about an unknown output
  `allSystems`.
- `llm` keeps `freeformType = types.anything` (`options.nix:323`) so LLM
  profiles can stash CLI-specific settings (`disallowedTools`). Typos under
  `llm.*` are therefore still accepted silently.

### [~] 14. Small correctness fixes — **low**

Done: `set -x` before `bwrap` printed the full command line, including any
secret passed through `env`, on every launch. It now runs only when
`SANDBOX_DEBUG` is set.

Remaining:

- `${llmCmd} || exit` (`sandbox/default.nix:209`) skips `hooks.exit` when the
  CLI fails. When the CLI succeeds, the final `exit` returns the hook's status
  instead of the CLI's. Run the exit hook unconditionally, and exit with the
  CLI's status.
- `__sandbox_cleanup` reads `${SANDBOX_S6_SVSCAN[1]}` without a default
  (`sandbox-lib.sh:23`). Under `set -u` (as in `sandbox-proxy.sh`), an early
  failure aborts the cleanup before its `rm -rf`, which leaks the runtime
  directory.
- When `XDG_RUNTIME_DIR` is unusable, the runtime directory falls back to
  `${TMPDIR:-/tmp}/user/$uid` (`sandbox-lib.sh:87`), created with `mkdir -p`
  and never checked. On such hosts another local user can create it first.
  Check that it is owned by the user and has mode `0700`.

### [ ] 15. Dependency updates — **low**

The removed `update-claude.yml` workflow used to bump Claude Code. Claude Code
now comes from the `claude-code-nix` input, so it only changes when someone
updates `flake.lock`. Add a scheduled workflow that updates both `flake.lock`
and `dev/flake.lock`.

When bumping the `apply-seccomp` pin, note that newer srt releases add a second
filter that refuses namespace and mount calls
([srt README](https://github.com/anthropic-experimental/sandbox-runtime#readme)).
That may break nested sandboxes, such as `podman` in the `devops` profile.

### [ ] 16. Read-only toolchain caches — **low, to verify**

Language profiles bind caches read-only (`~/.cache/go-build`, `~/.npm`,
`~/.cargo/registry`, …). Tools that write to their cache on every run
(`go build`, `npm install`) may fail outright instead of running without the
cache. Verify each profile. `--overlay-src DIR --tmp-overlay DIR` (`bwrap`
0.11.0 or later) gives a writable view whose writes are discarded at exit,
which suits caches well.

### [ ] 17. Logging in inside the sandbox — **medium, to verify**

Since item 2, the `claude-code` and `codex` profiles keep their config and
login in a sandbox-owned directory, so each CLI needs one login inside the
sandbox. Neither login flow has been tested end to end:

- A browser login that redirects to `localhost` can't reach the CLI inside the
  sandbox's network namespace. Claude Code can fall back to pasting a code;
  check what Codex offers (device code, API key).
- The token exchange must reach an allowlisted domain. Token _refresh_ already
  works inside the sandbox (it did when the host's `~/.claude` was shared), but
  the initial login may need more domains.
- Existing users lose their host settings, `CLAUDE.md`, commands, and MCP
  servers inside the sandbox until they copy what they want into the state
  directory. The README explains this; consider a one-time, opt-in seeding
  hook that copies only non-executable files.

---

## Completed

### [x] 2. Writable host LLM config directories

The `claude-code` profile used to bind the host's `~/.claude` and
`~/.claude.json` read-write, and `codex` the host's `~/.codex`. Both CLIs run
commands from those files (hooks and MCP servers in Claude Code,
[settings docs](https://code.claude.com/docs/en/settings); `notify`, MCP
servers, and hooks in Codex,
[config reference](https://learn.chatgpt.com/docs/config-file/config-reference)),
so a session could plant commands that the host CLI later ran unsandboxed.

The new, generic `filesystem.stateDirs.<name>.target` option gives an
environment a persistent directory on the host under
`${XDG_STATE_HOME:-~/.local/state}/bubbllmwrap/<name>` (mode `0700`), bound at
`target` inside the sandbox. The LLM profiles use it for `~/.claude` (with
`CLAUDE_CONFIG_DIR`, which also moves `.claude.json` there,
[claude-directory](https://code.claude.com/docs/en/claude-directory)) and
`~/.codex` (with `CODEX_HOME`). Follow-up: item 17.

### [x] 3. Terminal input injection (TIOCSTI)

`bwrap` runs without `--new-session`, so the sandbox shares the host's terminal
session, and `ioctl(TIOCSTI)` could queue keystrokes for the host shell
(CVE-2017-5226; [`bwrap(1)`](https://github.com/containers/bubblewrap/blob/main/bwrap.xml)
recommends seccomp for exactly this). Linux 6.2's `dev.tty.legacy_tiocsti`
sysctl can refuse it, but the upstream default allows it
([`CONFIG_LEGACY_TIOCSTI`](https://www.kernelconfig.io/config_legacy_tiocsti)).

`nix/pkgs/sandbox-seccomp-filter` now builds a small BPF program with
libseccomp (native architecture plus its 32-bit compat ABIs) that refuses
`TIOCSTI` and `TIOCLINUX` with `EPERM`. The launcher passes it to `bwrap` with
`--add-seccomp-fd`, so it covers the whole sandbox. Controlled by
`seccomp.denyTerminalInjection` (default on). Verified: without the filter, a
byte is injected; with it, `EPERM`. `--new-session` plus a pty relay remains an
option if more terminal hardening is wanted.

### [x] 13. Documentation accuracy

Fixed:

- the README's "writable" claim and security model (tmpfs root, the VCS lock
  and its limits, state directories, terminal filter, credential binds);
- the `evalSandbox` overlay claim (now true: the top-level `pkgs` carries the
  Claude Code overlay);
- the bare `claude-code`/`codex` environments, which now appear in the README
  and `CLAUDE.md`;
- the `mkoptdocs` name;
- the empty `HACKING.md` link;
- the undocumented argument syntax, now in the README's "Passing arguments";
- the system prompt that claimed "no risk" and "all operations are logged";
- the srt link revision;
- a warning on `hooks.post`.

### [x] Pre-merge fixes on `claude/nixos-modular-interface-e5YW4`

- `docs/OPTIONS.md` regenerated. CI now also runs on `pull_request` and
  `workflow_dispatch`.
- VCS lock:
  - binds are mapped to the project's mount path, so symlinked project paths
    are covered;
  - gitlink files are locked;
  - gitlinks are followed one level only, which fixes a crash on
    self-referencing gitlinks;
  - `vcsMetadataDirs` entries may not contain `/` or `:`.
- `freeformType` was removed from environments and `proxy`, so typos there are
  errors now. This also matters for a plain attrset definition such as
  `environments.foo.imports = [...]` (the form the README used to show): the
  `types.submodule` shorthand treats it as config, and the freeform type used
  to swallow `imports` silently, so no profiles were applied. It is now an
  evaluation error. Definitions that use `imports` must be functions
  (`environments.foo = _: { imports = [...]; };`), and the README and
  flake-module examples now use that form.
- `environments.<name>.enable` is honored by the flake module.
- `lib.<system>` exports only `evalSandbox`.
- `legacyPackages` no longer carries the `makeScope` plumbing. Its `packages`
  function broke `nix build .#packages.<system>.<name>`.
- `packages` lists `apply-seccomp` and `docs` explicitly.
- `devshellm` moved into the `dev` partition and became an app
  (`nix run .#devshellm`), so consumers never evaluate it.

### [x] Seccomp BPF filtering for Unix sockets and io_uring

`apply-seccomp` is built from `anthropic-experimental/sandbox-runtime` in Nix
(`nix/pkgs/apply-seccomp/default.nix`), not vendored as a binary. The rcfile
runs the CLI through it, inside a nested user, PID, and mount namespace.
`seccomp.enable` turns it off. Follow-up tests are in item 11.

### [x] Proxy environment variables

`NO_PROXY`/`no_proxy`, `socks5h://` `ALL_PROXY`, `ftp_proxy`, `grpc_proxy`,
`RSYNC_PROXY`, and a socks5 `GIT_SSH_COMMAND` fallback are set in the rcfile.
Leftovers are in item 9.

### [x] `--clearenv`

The host environment no longer leaks into the sandbox. Follow-up in item 7.

### [x] Dead code in `sandbox/default.nix`

`defaultSystemPrompt`, `concat`, and `packagePrompt` have been removed.

---

## What I wouldn't port

**Dynamic config updates (`--control-fd`)**: this project's design is "build a
complete environment, launch it, done." There's no long-running host process
managing the sandbox. Adding one would be a fundamental architecture change for
little benefit in the interactive CLI use case.

**macOS Seatbelt support**: bubblewrap is Linux-only. This is a platform
limitation, not something to port.

**Deny-then-allow filesystem model**: the allowlist-only model (nothing mounted
means nothing accessible) is already stricter than srt's. The only place that
needs finer control is inside the project directory; see item 1, where an
overlay mode is more general than deny lists.

**srt's fixed mandatory-deny list and nested-repo glob scanning**: both depend
on naming dangerous paths in advance. The current lock already finds metadata
roots at any depth, and item 1's change report and overlay mode cover what a
list can't.

**Violation monitoring**: Linux has no equivalent of Seatbelt's log stream.
The proxy already blocks, and could log, denied requests; glider's verbose log
already records which domains were blocked. strace-based monitoring would add
complexity for little benefit.

---

## Priority order

1. **The "Before merging" list** (first CI run; item 17).
2. **Item 1A** (session change report).
3. **Item 4** (refuse `$HOME` and `/` as the project directory).
4. **Items 5 and 6** (defaults that widen exposure).
5. **Items 7 and 8** (environment passthrough; quoting and structured binds).
6. **Item 1B** (overlay mode).
7. **Item 11** (tests), added alongside each of the above.
8. Everything else.

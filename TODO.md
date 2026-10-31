# TODO

Hardening, correctness, and maintenance work. Items are marked `[ ]`
(outstanding), `[~]` (partially done), or `[x]` (done — kept briefly for
context, remove once stale). Severity tags (**high** / **medium** / **low**)
are relative to the threat model below. Line references are as of `406203d`.

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

- [ ] **Regenerate `docs/OPTIONS.md`.** It lacks the new `filesystem.*`
      options, so the `options-docs` check fails.
- [ ] **Run CI on this branch.** `.github/workflows/flake-check.yml:3-5`
      triggers only on `push` to `main`, so this branch has never been through CI.
      Add `pull_request` and `workflow_dispatch`. Also confirm the VM test gets KVM
      on the `ubuntu-24.04-arm` runner.
- [ ] **Fix the VCS-lock bugs in item 1.** As shipped, the lock does nothing
      when the project path contains a symlink, and it leaves gitlink files
      writable.
- [ ] **Settle the public interface (item 12)** before consumers depend on it:
      the `lib.<system>` output, the exported `packages`, the no-op
      `environments.<name>.enable`, and the `freeformType`s.
- [ ] **Make the docs match the code (item 13)**, in particular on whether bare
      `claude-code`/`codex` environments exist.

## Outstanding

### [~] 1. Post-session execution via the project directory — **high**

_(Was "mandatory deny paths".)_

**Current state.** `filesystem.denyVcsMetadata` (on by default) finds every
directory named in `filesystem.vcsMetadataDirs` (default `.git`, `.jj`) under
the project at launch, and `--ro-bind`s each one over the writable project bind
(`nix/pkgs/sandbox-lib/sandbox-lib.sh:184-264`, `nix/pkgs/sandbox/sandbox.sh:112`).
Finding metadata roots by name, instead of keeping a per-file deny list, is the
right approach. It covers hooks, `core.fsmonitor`, aliases, and anything else
inside a root without listing them, and supporting a new VCS takes one list
entry.

**Confirmed bugs.** Reproduced with `bwrap` 0.9.0 and the shell functions
sourced directly.

- _The lock misses when the project path contains a symlink._ Each bind uses
  the resolved (`realpath`) path as both source and destination, but the
  project is mounted at the unresolved `$project_dir` (`sandbox.sh:111`). With
  `/home → /var/home` (Fedora Atomic) or any symlinked checkout, the read-only
  bind lands at a path the CLI never uses, and `.git/hooks/` stays writable.
  Fix: bind `"$real"` at `"$project_dir${real#"$real_project_dir"}"`. Tested:
  with that mapping, writes fail with `EROFS` and renaming the root fails with
  `EBUSY`. See also item 4.
- _Gitlink files stay writable._ In a submodule or linked worktree, `.git` is a
  file. The code locks the file's `gitdir:` target but not the file itself
  (`sandbox-lib.sh:250-262`). The CLI can rewrite it to point at a directory it
  controls that contains a hostile `config`, and the next host-side
  `git status` there follows it. Fix: also `--ro-bind` the gitlink file. srt
  does this too ("its `.git` is a file: on Linux that file is blocked",
  [srt README](https://github.com/anthropic-experimental/sandbox-runtime#readme)).
- _A self-referencing gitlink crashes the launcher._ A `.git` file containing
  `gitdir: .git` recurses until bash segfaults (exit 139). The launch fails
  closed, but one session can break every later launch in that project. Fix:
  don't follow a gitlink to another file, or record the path as seen before
  recursing.

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
  verify; `--ignore-working-copy` may be the workaround). The option's
  description only mentions failed git commits.
- The `find` at `sandbox-lib.sh:223` walks the whole tree on every launch, with
  no `-xdev` and no depth or exclude limits. That is slow on large trees
  (`node_modules`, `target/`), and it crosses into other mounted filesystems.
  Add `-xdev`, plus an optional depth limit or exclude list.
- `vcsMetadataDirs` is a `listOf str`, joined with `:` and passed to
  `find -name`. An entry containing `:` breaks the splitting, and one
  containing `/` can never match. Constrain the type
  (`strMatching "[^/:]+"`), and document that entries are `find -name` globs.

**Generic directions.** None of these needs per-tool lists, and all leave
policy to the user.

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
  - Kernel support for overlayfs in user namespaces (mainline since 5.11,
    [patch](https://lore.kernel.org/all/20201207163255.564116-11-mszeredi@redhat.com/)).
  - Upper and work directories outside the project, because `bwrap` forbids
    overlay directories that are ancestors of one another.

  Most of the work is on the apply side: list the changes (whiteouts are
  deletions), flag the same user patterns as in A, and copy files without
  running anything from the upper directory. Possible interface:
  `filesystem.projectMode = "bind" | "overlay"` plus a
  `--sandbox-review <session>` subcommand.

- **Keep the current lock** as the default in `bind` mode once the bugs are
  fixed. Document plainly that it only stops existing metadata roots from
  being modified.

Suggested order: fix the bugs, then A (small), then B.

### [ ] 2. Writable host LLM config directories — **high**

The `claude-code` profile binds `~/.claude` and `~/.claude.json` read-write
(`profiles/llm/claude-code.nix:40-48`), and `codex` binds `~/.codex`
read-write (`profiles/llm/codex.nix:33-37`). The host's own CLI runs commands
from these files:

- Claude Code: hooks in `~/.claude/settings.json` and MCP server commands in
  `~/.claude.json`
  ([settings docs](https://code.claude.com/docs/en/settings)).
- Codex: `notify`, `mcp_servers.<id>.command`, and command hooks in
  `~/.codex/config.toml`
  ([config reference](https://learn.chatgpt.com/docs/config-file/config-reference)).

A sandboxed session can add any of these, and they run outside the sandbox the
next time the user starts the CLI on the host. It is the same class of problem
as item 1, outside the project directory. The README's security model doesn't
mention it.

Generic fix: don't share host config with the sandbox. Give each environment
(or all sandboxes) its own persistent state directory, e.g.
`$XDG_STATE_HOME/bubbllmwrap/<llm>`. Bind it at the path the CLI expects, or
point the CLI at it with `CLAUDE_CONFIG_DIR` / `CODEX_HOME`. The host CLI then
never reads config written by the sandbox. The cost is a one-time login inside
the sandbox. Users who want shared credentials can opt in to binding just the
credential file. Check first whether the CLI replaces that file with
`rename(2)`, which fails on a bind-mounted file. This could be an
`llm.stateDir` option.

### [ ] 3. Terminal input injection (TIOCSTI) — **high, kernel-dependent**

`bwrap` runs without `--new-session` (`sandbox.sh:88-118`), so the sandbox
shares the host's terminal session. A process inside can push bytes into the
terminal's input queue with `ioctl(TIOCSTI)`, and whatever is still queued
when the sandbox exits is read by the host shell (CVE-2017-5226). `bwrap(1)`:
"if you don't use --new-session, it is recommended to use seccomp to disallow
the TIOCSTI ioctl"
([bwrap.xml](https://github.com/containers/bubblewrap/blob/main/bwrap.xml)).

`apply-seccomp` doesn't cover this. srt documents its filter as blocking
`AF_UNIX` sockets and io_uring, not TIOCSTI, and it only wraps the LLM process
anyway. Linux 6.2 and later can refuse TIOCSTI to unprivileged processes
(`dev.tty.legacy_tiocsti=0`), but the upstream default still allows it, and
distributions differ
([`CONFIG_LEGACY_TIOCSTI`](https://www.kernelconfig.io/config_legacy_tiocsti)).

Options:

- A small seccomp filter for the whole sandbox, built with libseccomp at Nix
  build time and passed with `bwrap --add-seccomp-fd`, that returns `EPERM`
  for `ioctl(TIOCSTI)` (and `TIOCLINUX`, which matters on virtual consoles).
  This is the smallest change and doesn't affect the TUI.
- `--new-session` plus a pty relay: the sandbox gets its own pty, and the
  launcher copies bytes between it and the real terminal. More robust, but more
  code, and it needs care with Ctrl-C and window-size forwarding.
  `--new-session` alone stops job-control signals from reaching the TUI.

### [~] 4. Project directory validation — **medium**

_(Was "symlink validation".)_ `sandbox.sh:36-41` only checks that
`$project_dir` is a directory.

- **Dangerous roots.** Running in `$HOME` or `/` binds the whole tree
  read-write, including `~/.bashrc`, `~/.ssh`, and every tool config. That is
  easy to do by accident, because the project defaults to `$PWD`. After
  resolving symlinks, refuse `/`, `$HOME`, and any ancestor of `$HOME` unless
  the user passes an explicit override flag. This also covers the old concern
  about `$project_dir` being a symlink to `/`.
- **Relative paths don't work.** `--sandbox-project-dir .` becomes
  `--bind . .`, which mounts the project over the sandbox root, so the launch
  fails (reproduced: `execvp … No such file or directory`). Convert the path
  to absolute up front.
- **Symlinks.** Keep two values: the absolute path as given (used as the
  in-sandbox mount point and for `--chdir`, so the README's "same path" promise
  holds), and the resolved path (used as the bind source and as the root of the
  item 1 scan). This also fixes the path bug in item 1.

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
defaults rather than from anything users configure.

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
subpaths it needs.

More generally, any socket that a user's bind exposes bypasses the proxy when
seccomp is off. Say so in the `seccomp.enable` description.

### [ ] 7. Passing variables through `--clearenv` — **medium**

`sandbox.sh:109` uses `--clearenv`, so `TERM`, `COLORTERM`, `LANG`, `LC_*`,
and `TZ` are unset inside the sandbox (reproduced). TUIs will likely degrade,
and `vim`/`less` will complain. Add an explicit passthrough option, e.g.
`envPassthrough = ["TERM" "COLORTERM" "LANG" "LC_ALL" "TZ"]`, emitted as
`--setenv` with the host's values. It is also the right way to pass API keys
(`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`). Interpolating them in `env` instead
puts them in `set -x` output (item 14).

### [ ] 8. `args`/`env` quoting is unsafe by default — **medium**

Plain-string `args` and `env` values default to `quote = false`, and they are
spliced unquoted into a bash array literal (`sandbox/default.nix:82-85`). So
`env.GREETING = "hello world"` becomes two words. `bwrap` takes `world` as the
program to run and everything after it as that program's arguments. The
project bind, `--chdir`, and `HOME` silently disappear, and the launch fails.

Similarly, `claude-code.nix:33` shell-escapes `--disallowedTools` with
`lib.escapeRegex`. That happens to escape `(`, `)`, and `*`, but not spaces, so
a rule like `Bash(rm -rf:*)` splits into two arguments. Use
`lib.escapeShellArg`.

Options:

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
- Both `GIT_SSH_COMMAND` values (`sandbox/default.nix:146`, `:191`) call `ssh`
  and `socat`, and neither is on the sandbox `PATH` (`:47`); `socat` exists
  only inside the s6 service wrappers. Use store paths, or drop the variable.
  The `# TODO` at `:188` is stale.
- Document how the allowlist matches. glider matches a domain and all of its
  subdomains, ignores the port, and doesn't resolve names that match no rule,
  so there's no DNS side channel
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

### [ ] 11. Test coverage — **medium**

_(Was "test coverage for the proxy-disabled rcfile path".)_ The VM test
(`nix/checks/eval-sandbox.nix`) forces `proxy.enable = true`, and only checks
that each package's `mainProgram` is on `PATH`. Add cases for:

- `proxy.enable = false` (the rcfile branches that create `down` files) and
  `seccomp.enable = false`. Confirm the nested namespace from `apply-seccomp`
  doesn't interfere with s6 or the socat bridge.
- Seccomp actually blocking `socket(AF_UNIX)`.
- The VCS lock: writes under `.git/` fail; a nested repo; a submodule or
  worktree gitlink; a symlinked project path; a self-referencing gitlink.
- A project path containing spaces, a relative `--sandbox-project-dir`, and
  passing arguments through to the LLM.
- One real toolchain operation per language profile (e.g. `go build`,
  `cargo build --offline`); see item 16.

### [ ] 12. Module interface and public API — **medium** (settle before merge)

- `environments.<name>.enable` is never read:
  `nix/modules/flake/default.nix:74` exports every environment. Filter on it.
- `freeformType = types.anything` on environments, `llm`, and `proxy`
  (`options.nix:122`, `:298`, `:365`) silently accepts typos such as
  `hook.pre` or `proxy.allowlist`. The only use of a freeform attribute is
  `llm.disallowedTools`, and the claude-code profile can declare that as a
  real option, since profiles are modules.
- `llm.package` defaults to `pkgs.coreutils` (`options.nix:303`), so an
  environment without an LLM profile builds a script that runs `coreutils`.
  Make the option required, or fall back to an interactive shell.
- `llm.prompt` is set with `config =` at normal priority (`options.nix:348`),
  so a user's prompt is appended to the default instead of replacing it. If
  that isn't intended, set it with `default` instead.
- `lib.<system>` is `filterAttrs isFunction legacyPackages` (`flake.nix:125`).
  That also publishes `callPackage`, `newScope`, `overrideScope`,
  `makeSandbox*`, and so on. List the intended exports explicitly.
- `devshellm` (`flake.nix:139`) is a contributor environment, but it is
  exported as a public package. It references `self'.devShells.default`, which
  pulls in the `dev` partition's inputs whenever the package is evaluated
  (e.g. by `nix flake check`). Move it into the `dev` partition.
- The launcher derivations are built from bubbLLMwrap's own nixpkgs
  (`self'.legacyPackages`), while profile packages come from the consumer's
  `pkgs`. So consumers' overlays don't reach `bash`, `s6`, `socat`, or
  `apply-seccomp`, and a closure can contain two nixpkgs instances. Consider
  building the launcher from the environment's `pkgs`.
- `debug = true` (`flake.nix:28`) adds `debug` and `allSystems` outputs for
  every consumer.

### [ ] 13. Documentation accuracy — **medium**

- `README.md:211-213` says only the project directory and `/tmp` are writable.
  In fact the sandbox root is a writable tmpfs (discarded at exit), and
  `~/.claude`, `~/.claude.json`, and `~/.codex` are bound read-write
  (item 2). The security model also doesn't mention the VCS lock or its limits.
- The README says `evalSandbox` supplies a `pkgs` "with the Claude Code
  overlay". It doesn't: the top-level `perSystem` never sets
  `_module.args.pkgs`, so `evalSandbox` gets plain
  `inputs.nixpkgs.legacyPackages.<system>`. The overlay is applied only in the
  `dev` partition and in this flake's own `bubbllmwrap` config. Fix either the
  code or the claim, and mention that unfree packages must be allowed.
- `canned.nix:63` includes `null`, which produces bare `claude-code` and
  `codex` environments, but `CLAUDE.md:63` and the README say there are none.
- `CLAUDE.md:125` calls the docs command `mkdocs`; it is `mkoptdocs`.
- `docs/HACKING.md:47` has an empty link target for `nix/checks`.
- The launcher's argument syntax is undocumented. It is
  `[--sandbox-project-dir DIR] [--] [BWRAP_ARGS…] [-- LLM_ARGS…]`, so passing
  flags to the LLM takes `-- --` in the launcher's own arguments (three `--`
  with `nix run`). Tested: `-- --model x` hands `--model x` to `bwrap`.
  Document this, or simplify it.
- `nix/lib/modules/sandbox-prompt.txt` tells the model there is "no risk of
  affecting the host system" and that "all operations are logged". Neither is
  true, and the CLI runs with `--dangerously-skip-permissions`. The prompt
  should state the actual boundaries.
- The `seccomp` option description links srt at `34a39e0`
  (`options.nix:428`), but `apply-seccomp` builds `7a725a3`.
- `hooks.post` runs on the host against files the sandbox has modified, so
  running `git` there is exactly the risk in item 1. Note this in its
  description.

### [ ] 14. Small correctness fixes — **low**

- `set -x` before `bwrap` (`sandbox.sh:87`) prints the full command line on
  every launch, including any secret passed through `env`. Put it behind a
  debug variable.
- `${llmCmd} || exit` (`sandbox/default.nix:201`) skips `hooks.exit` when the
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

---

## Completed

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

1. **The "Before merging" list** (docs, CI trigger, VCS-lock bugs, interface
   decisions).
2. **Items 2 and 3** (writable host LLM config; TIOCSTI). Both let code run
   directly on the host, and both are small changes.
3. **Item 4** (project directory validation), done together with the item 1
   bug fixes.
4. **Items 5 and 6** (defaults that widen exposure).
5. **Items 7 and 8** (environment passthrough; quoting and structured binds).
6. **Item 1A, then 1B** (change report; overlay mode).
7. **Item 11** (tests), added alongside each of the above.
8. Everything else.

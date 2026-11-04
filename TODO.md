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

- [ ] **Get CI running.** No Flake Check run exists for this PR, and GitHub
      lists no such workflow for the repository even though `main` has
      `.github/workflows/flake-check.yml`. That usually means Actions are
      disabled for the repository (the default for forks). Once enabled, watch
      the first run: the VM test's assertions so far were validated by running
      the same environments outside a VM, not inside one. Without `/dev/kvm`
      (possibly the `ubuntu-24.04-arm` runner), the workflow evaluates every
      check, builds the non-VM ones, and skips the VM test with a warning.
- [ ] **Decide on item 17** (logging in inside the sandbox), since the
      `claude-code` and `codex` profiles no longer share the host's login.
- [ ] **Decide on item 5** (credential binds), which GitHub Advanced Security
      also flagged on the PR, and whether this flake's own `pkgs` should allow
      the unfree `claude-code` package (CodeRabbit's suggestion; today users
      set `NIXPKGS_ALLOW_UNFREE=1` and pass `--impure`, as the README says).

Everything else that was listed here is done; see [Completed](#completed).

## Outstanding

### [~] 1. Post-session execution via the project directory — **high**

**Current state.** `filesystem.denyVcsMetadata` (on by default) finds every
entry named in `filesystem.vcsMetadataDirs` (default `.git`, `.jj`) under the
project at launch and `--ro-bind`s it over the writable project bind
(`nix/pkgs/sandbox-lib/sandbox-lib.sh`, `__sandbox_add_vcs_deny_args`). Gitlink
files (submodules, linked worktrees) are locked along with the directory they
point to. Binds are mapped from the resolved host path to the path the project
is mounted at, so symlinked project paths are covered. Metadata reached through
a symlink inside the project (a symlinked `.git`, or a gitlink whose path runs
through one) makes the launcher refuse to start: a bind mount can't cover the
symlink itself, so the CLI could replace it. Finding metadata roots by
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
- The `find` at `sandbox-lib.sh:245` walks the whole tree on every launch, with
  no `-xdev` and no depth or exclude limits. That is slow on large trees
  (`node_modules`, `target/`), and it crosses into other mounted filesystems.
  Consider `-xdev` and an optional depth limit or exclude list; both trade
  coverage for speed.
- Hooks that live in the working tree aren't protected: `core.hooksPath`
  pointing into the project (husky's `.husky`), hooks in `.git/hooks` that
  are symlinks to tracked files, and hook runners such as `pre-commit` that
  read tracked config. Running `git commit` on the host then runs whatever the
  CLI left there. This is close to "code the user knowingly runs", but it's
  easy to miss; the change report (A) is the generic mitigation.

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

_(GitHub Advanced Security flagged the same binds on the PR, also noting
`~/.yarnrc`, `~/.yarnrc.yml`, and `~/.config/containers`, and that anything the
CLI reads ends up with the model provider.)_

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

**Options considered.** Read-only binds stop tampering, not reading, and
reading is the risk: whatever the CLI reads can leave through any allowlisted
host, and at the least it reaches the model provider in the transcript. Ways
to keep the secret on the host and give the sandbox narrower access instead:

- **Kubernetes.** Run `kubectl proxy --unix-socket` on the host, optionally
  with `--accept-paths`/`--reject-paths`
  ([docs](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_proxy)),
  and give the sandbox a kubeconfig that points at it (the socket can be
  bridged like glider's). The CLI can still act with the user's cluster
  permissions, but can't take the token away.
- **AWS.** The CLI and every SDK support the container credential provider
  (`AWS_CONTAINER_CREDENTIALS_FULL_URI` plus `AWS_CONTAINER_AUTHORIZATION_TOKEN`,
  [docs](https://docs.aws.amazon.com/sdkref/latest/guide/feature-container-credentials.html)).
  `aws-vault exec --ecs-server` serves short-lived credentials from such an
  endpoint ([usage](https://github.com/99designs/aws-vault/blob/master/USAGE.md)),
  so the sandbox sees only temporary keys, which a role or session policy can
  narrow. Alternatively, [aws-sigv4-proxy](https://github.com/awslabs/aws-sigv4-proxy)
  signs requests on the host, so no AWS key enters the sandbox at all.
- **Token-in-a-header services** (npm, PyPI, crates.io, GitHub, most APIs).
  The host-side proxy could add the `Authorization` header for specific hosts.
  That needs TLS interception with a CA only the sandbox trusts (it already
  uses a CA bundle we control), which glider can't do, so it means another
  proxy. It is generic (host → header) and keeps tokens out of the sandbox
  entirely, but doesn't cover request signing (AWS SigV4) or client
  certificates.

Until then: opt-in, read-only binds, and the README should recommend
narrowly scoped, short-lived tokens for anything bound.

### [~] 8. `args` quoting is unsafe by default — **medium**

Done:

- `env` values are now literal by default (`quote = true`); shell syntax is
  the opt-in (`{ value; quote = false; }`).
- `claude-code.nix` used `lib.escapeRegex` to shell-escape
  `--disallowedTools`, which split rules containing spaces; it now uses
  `lib.escapeShellArg`.

Remaining: plain-string `args` still default to `quote = false` and are
spliced unquoted into a bash array literal (`sandbox/default.nix:100`), so an
argument containing a space becomes two arguments. They were left alone because
the profiles rely on `~` expansion in bind paths, and flipping the default
would silently turn every `--ro-bind-try ~/...` into a no-op. The better fix:

- Add a structured `binds` option: an attrset keyed by path, with entries like
  `{ source; mode = "ro" | "rw"; optional = true; enable = true; }`. The
  generator emits correctly quoted arguments and does the `$HOME` expansion
  itself. Profiles stop writing argument triples by hand. Users can disable one
  inherited bind (`binds."~/.aws".enable = false`) instead of `mkForce`-ing the
  whole `args` list, and item 5 follows directly.

### [~] 9. Proxy: remaining issues — **low**

Done: `extraRules` is appended once (it used to repeat per domain and vanish
with an empty allowlist); `proxy.port`, which did nothing, is removed;
`GIT_SSH_COMMAND` calls `socat` by store path; the `allowList` description
says it covers subdomains and any port (glider matches by domain suffix and
doesn't resolve names that match no rule,
[`rule/proxy.go`](https://github.com/nadoo/glider/blob/main/rule/proxy.go)).

Remaining:

- `GIT_SSH_COMMAND` still runs `ssh` from `PATH`, and no profile installs
  `openssh`, so SSH needs `packages = [pkgs.openssh]` (and keys).
- Document that filtering at the `CONNECT` level can't see the TLS SNI or
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

Done: the VM test (`nix/checks/eval-sandbox.nix`) now also checks that

- writes under `.git/hooks` fail;
- each state directory is writable;
- `TIOCSTI` is refused (probed under `script`, so the probe has a controlling
  terminal);
- plain `env` strings arrive literally and `quote = false` ones are expanded;
- `TERM` is passed through;
- the CLI's exit status survives the exit hook, which still runs;
- a symlinked `.git` is refused;
- an unprivileged user without a login session (so no `/run/user/<uid>`) can
  start a sandbox.

Remaining cases:

- `proxy.enable = false` (the rcfile branches that create `down` files) and
  `seccomp.enable = false`. Confirm the nested namespace from `apply-seccomp`
  doesn't interfere with s6 or the socat bridge.
- Seccomp actually blocking `socket(AF_UNIX)`.
- The VCS lock beyond the basic case: a nested repo; a submodule or worktree
  gitlink; a gitlink reached through a symlink; a symlinked project path; a
  self-referencing gitlink. (All verified by hand outside a VM.)
- A project path containing spaces and a relative `--sandbox-project-dir`
  (verified by hand outside a VM).
- One real toolchain operation per language profile (e.g. `go build`,
  `cargo build --offline`); see item 16.

### [~] 12. Module interface and public API — **medium**

Done before merge: see [Completed](#completed). Remaining:

- `llm.package` defaults to `pkgs.coreutils` (`options.nix:366`), so an
  environment without an LLM profile builds a script that runs `coreutils`.
  Make the option required, or fall back to an interactive shell.
- `llm.prompt` is set with `config =` at normal priority (`options.nix:411`),
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
- `llm` keeps `freeformType = types.anything` (`options.nix:361`) so LLM
  profiles can stash CLI-specific settings (`disallowedTools`). Typos under
  `llm.*` are therefore still accepted silently.

### [ ] 15. Dependency updates — **low**

The removed `update-claude.yml` workflow used to bump Claude Code. The canned
profiles now take Claude Code from nixpkgs (and the `dev` partition from
`claude-code-nix`), so it only changes when someone updates `flake.lock` or
`dev/flake.lock`. Add a scheduled workflow that updates both.

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
- the `evalSandbox` overlay claim (moot now: there is no overlay, and the
  canned profiles use nixpkgs' `claude-code`);
- the bare `claude-code`/`codex` environments, which now appear in the README
  and `CLAUDE.md`;
- the `mkoptdocs` name;
- the empty `HACKING.md` link;
- the undocumented argument syntax, now in the README's "Passing arguments";
- the system prompt that claimed "no risk" and "all operations are logged";
- the srt link revision;
- a warning on `hooks.post`.

### [x] Fixes from the CodeRabbit review of `70e3e18`

- 6\. The `nix` profile bound `/nix/var/nix`, which holds the Nix daemon
  socket; a read-only bind doesn't stop `connect(2)` (reproduced), so with
  `seccomp.enable = false` the CLI could have the daemon build or substitute
  outside the proxy. The bind is gone (with seccomp on, the daemon was
  unreachable anyway), and the README's network bullet now explains Unix
  sockets as a channel the proxy doesn't see.
- Environment modules didn't receive `pkgs`, so `environments.foo =
{pkgs, ...}: ...`, `.extend ({pkgs, ...}: ...)`, and profiles written that
  way failed with "called without required argument 'pkgs'". The environment
  submodule now passes the enclosing `pkgs` through.
- The documented `environments.new = config.environments.old.extend ...`
  pattern recursed infinitely (it predates this branch): `.extend` returns an
  evaluated configuration, which can't be another entry's definition. The
  README, `CLAUDE.md`, and the option's own example now show `.extend` for
  standalone use (e.g. its `.script`) and profile imports for new named
  environments. `CLAUDE.md`'s example also read `profiles` from the
  environment's own `config`.
- `dev/flake.nix` declared its own `claude-code-nix`, which replaced the root
  input inside the `dev` partition (with a separately locked nixpkgs). Since
  resolved the other way, on request: the root flake no longer has
  `claude-code-nix` (canned profiles use nixpkgs' `claude-code`), and the `dev`
  partition keeps it as a worked example of overriding `llm.package`. Its pin
  was bumped to the revision the root lock had used, since the old dev pin
  carried an older Claude Code than nixpkgs.
- The `seccomp` option's `:::{.note}` was never closed.
- `makeSandboxScanDir`'s `passthru.install` interpolated `finalAttrs` (not a
  derivation) instead of `finalAttrs.finalPackage`.
- CI: skip only the VM test when `/dev/kvm` is missing, and declare
  `permissions: contents: read`.

### [x] Fixes from the Codex review of `c29405b`

- A `.git` symlink inside the project (or a gitlink whose path runs through
  one) could be replaced from inside the sandbox, bypassing the VCS lock; the
  launcher now refuses to start (item 1).
- With no usable `XDG_RUNTIME_DIR`, the runtime directory fell back to
  `${TMPDIR:-/tmp}/user/$uid` without creating it, so non-root launches
  failed, and the failure wasn't propagated. It now uses `mktemp -d` directly
  in `TMPDIR` (private and atomic), and errors propagate. This also removes
  the old concern about another user pre-creating that directory.
- `env` values are literal by default (item 8).
- `envPassthrough` keeps named host variables across `--clearenv`;
  `basic-tooling` passes `TERM` and `COLORTERM` and sets `LANG=C.UTF-8`
  (glibc's built-in UTF-8 locale, so no locale data is needed). This was
  item 7.
- The exit hook runs even when the CLI fails, and the sandbox exits with the
  CLI's status, not the hook's.
- `__sandbox_cleanup` runs from an `EXIT` trap, and under `set -e` (the proxy
  wrapper) a failure there replaced the sandbox's exit status with 1. It failed
  intermittently: `s6-svscanctl -q` doesn't wait for the s6-supervise
  processes, which race the `rm -rf` of the runtime directory, and an unset
  `SANDBOX_S6_SVSCAN` tripped `set -u`. Cleanup now runs with `set +e`, retries
  the removal briefly, warns if it still fails, and always succeeds.
- `extraRules`, `proxy.port`, and `GIT_SSH_COMMAND`'s `socat` path (item 9).
- Found while testing: runtime arguments for the LLM were expanded unquoted
  when the rcfile defined its alias, so only the first one reached the CLI
  (`-- -- --model opus` lost `opus`). They are now passed intact.

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

The host environment no longer leaks into the sandbox; variables to keep are
listed in `envPassthrough`.

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
4. **Item 5** (credential binds, a default that widens exposure).
5. **Item 8** (structured binds, which also fixes `args` quoting).
6. **Item 1B** (overlay mode).
7. **Item 11** (tests), added alongside each of the above.
8. Everything else.

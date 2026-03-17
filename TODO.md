# TODO

Hardening and correctness work, largely ported from the `srt`
(anthropic-experimental/sandbox-runtime) design. Items are marked `[ ]`
(outstanding), `[~]` (partially done), or `[x]` (done — kept briefly for
context, remove once stale).

## Completed

### [x] Seccomp BPF filtering for Unix socket and io_uring blocking

`apply-seccomp` is now packaged as a Nix derivation
(`nix/pkgs/apply-seccomp/default.nix`) that builds the seccomp helper from
`anthropic-experimental/sandbox-runtime` via `bun` rather than vendoring a
pre-compiled binary. It is wired into the rcfile (`sandbox/default.nix`,
`llmMaybeWrapped` / the LLM `alias`) so the CLI execs through `apply-seccomp`,
which applies the BPF filter inside a nested user+PID+mount namespace (blocking
`io_uring` and Unix-socket bridging, and hiding the socat/s6 infrastructure from
the CLI). A `seccomp.enable` module option (default `true`,
`nix/lib/modules/options.nix`) disables it when a tool legitimately needs the
blocked syscalls.

Follow-ups worth confirming under a VM test: that the nested namespace does not
interfere with the s6 supervision tree or the socat proxy bridge, and that
`seccomp.enable = false` produces a working environment.

---

## Outstanding

### [ ] 1. Mandatory deny paths within the project directory

**The problem**: The project directory is bind-mounted writable
(`sandbox.sh:89`, `--bind "$project_dir" "$project_dir_bind"`). Nothing stops
the LLM CLI from writing `.git/hooks/pre-commit`, `.vscode/settings.json`,
`.idea/` configs, `.bashrc`, `.gitconfig`, or `.claude/commands/` inside the
project. These all execute code on the host when the user later runs git, opens
the project in an IDE, or starts a new Claude session — after leaving the
sandbox. **Still fully outstanding** — no deny-path scanning exists, and
`nix/pkgs/sandbox-scan-dir` is unrelated (it builds s6 scan directories, not a
filesystem deny list).

**What's involved**: The deny mounts need to happen as bwrap arguments, which
means before `bwrap` is invoked. The project directory isn't known until
runtime, so this can't be done at Nix evaluation time. The natural place is in
the `vars` script (`sandbox/default.nix`) or `sandbox.sh` itself, where
`__sandbox_bwrap_args` is assembled.

A shell function would scan the project directory for a fixed list of dangerous
paths (`.git/hooks`, `.git/config`, `.vscode/`, `.idea/`, `.claude/commands/`,
`.claude/agents/`, `.bashrc`, `.gitconfig`, `.gitmodules`, `.mcp.json`). For
each:

- If the path exists and is a directory: `--ro-bind "$path" "$path"` (makes it
  read-only inside the sandbox)
- If the path exists and is a file: `--ro-bind /dev/null "$path"` (hides it)
- If the path doesn't exist but its parent is within the writable project dir:
  `--ro-bind /dev/null` at the first non-existent component to prevent `mkdir`
  from creating it. This is the trickiest part — srt's
  `findFirstNonExistentComponent` logic, but in bash.
- If `.git` is a file (git worktree): skip `.git/hooks` and `.git/config` since
  they can't exist under a file.

The paths would be relative to `$project_dir_bind` (`~/project`). The bwrap
mount ordering already works — later `--ro-bind` arguments override earlier
`--bind` for the same path, and `__sandbox_bwrap_args` is already expanded
before the `--bind "$project_dir"` line, so an appended deny list would need to
be spliced in _after_ the project bind instead.

No ripgrep needed. Unlike srt, which searches nested repos to arbitrary depth,
this project could start with just the top-level project directory. The fixed
list is small enough to check with `test -e` / `test -d` in a loop.

A new module option (`filesystem.mandatoryDenyPaths` or similar) could allow
profiles to extend the list, defaulting to the srt set.

### [x] 2. Proxy environment variable improvements

**Done so far** (`sandbox/default.nix`, rcfile):

- `all_proxy` / `ALL_PROXY` are now `socks5h://localhost:1028` (DNS resolved
  through the proxy). Also sets `ftp_proxy`, `grpc_proxy`, `RSYNC_PROXY`.
- `GIT_SSH_COMMAND` is emitted for the HTTP proxy and is now correctly formed
  (`ssh -o ProxyCommand='socat - PROXY:localhost:%h:%p,proxyport=3128'`), along
  with `DOCKER_*` and `CLOUDSDK_*` proxy variables.

**Still outstanding**:

- `NO_PROXY` / `no_proxy` are **not** set anywhere (confirmed: no occurrences in
  `nix/`). Without them, proxy-aware tools try to proxy connections to
  `localhost` — which is the proxy itself — and can loop. Set them (scoped to
  the proxy-enabled branches) to at least `localhost,127.0.0.1,::1`.
- See the inline `# TODO` at `sandbox/default.nix:153` — make `GIT_SSH_COMMAND`
  fall back to the socks5 proxy when only the socks5 proxy is enabled. A working
  form is `ssh -o ProxyCommand='socat - SOCKS5-CONNECT:localhost:1028:%h:%p'`
  (socat ≥ 1.7.4.0), or `ssh -o ProxyCommand='nc -X 5 -x localhost:1028 %h %p'`
  with OpenBSD netcat.

These belong in the rcfile's conditional proxy blocks (they depend on which
proxy socket exists).

**Note on env passthrough (not a security issue)**: `sandbox.sh` does not
`--clearenv`, so the host's ambient environment (including host
`HTTP_PROXY`/`no_proxy`) leaks into the sandbox. This is **not** a hardening
concern: with the net namespace unshared, all egress goes through glider, and a
leaked proxy var only ever points somewhere with no route — so it degrades to
"no network," never to exfiltration or an allowlist bypass. In the
proxy-disabled config the sandbox is airgapped anyway, so leakage is moot there.

The rcfile already reassigns the `*_proxy` vars it sets (`declare -rx` clobbers
the inherited values), so the only practical residue is a leaked host `no_proxy`
in the proxy-enabled config: if it lists an allowlisted domain, a proxy-aware
tool connects directly, bypasses the sandbox proxy, and the fetch fails. Pinning
`NO_PROXY`/`no_proxy` to `localhost,127.0.0.1,::1` overrides that — a robustness
fix, not a security one.

### [ ] 3. Symlink validation before bwrap invocation

**The problem**: `sandbox.sh:89` does `--bind "$project_dir" "$project_dir_bind"`.
`sandbox.sh` only checks that `$project_dir` is a directory (line 38); it does
not resolve symlinks. If `$project_dir` is itself a symlink, or contains
symlinks at the mount point, bwrap follows them. A symlink at `$project_dir`
pointing to `/` would make the entire host filesystem writable inside the
sandbox.

**What's involved**: A pre-flight check in `sandbox.sh`, between the argument
parsing / directory check (lines 18–41) and the bwrap invocation (line 67):

- `readlink -f "$project_dir"` to resolve the project directory and verify it's
  sane (not `/`, not `$HOME`, not a system directory).
- Optionally, check that the resolved path is within expected boundaries (e.g.,
  under `$HOME` or at least not a system path).
- This is a few lines of bash. srt's `isSymlinkOutsideBoundary` is 100+ lines
  because it handles macOS `/private/tmp` canonicalization; the Linux-only
  version is much simpler.

For the mandatory deny paths (item 1), symlink checking within the project
directory would also be needed — if `.git` is a symlink to something outside the
project, mounting `/dev/null` over it would affect the symlink target on the
host filesystem. The check: `realpath "$path"` and verify the result is still
under `$project_dir`.

### [ ] 4. Parent proxy chaining

**The problem**: Developers behind corporate proxies can't use the sandbox
because Glider's `forward=reject://` default doesn't chain through the corporate
proxy, and the sandbox strips `HTTP_PROXY`/`HTTPS_PROXY` from the environment.

**What's involved**: Glider already supports upstream proxy forwarders. In
`sandbox-proxy/default.nix`, the rulefile currently hardcodes `forward=direct://`
and the config `forward=reject://`. The change:

```
forward=http://corporate-proxy:8080
domain=api.anthropic.com
```

instead of `forward=direct://` for allowed domains, keeping `reject://` as the
default for non-matching domains.

At the module level:

- Add a `proxy.parentProxy` option (URL or `{ http, https, noProxy }` attrset)
  in `nix/lib/modules/options.nix`.
- At runtime in `sandbox-proxy.sh`, read `HTTP_PROXY`/`HTTPS_PROXY` from the
  host environment before entering the sandbox (they're available at that
  point).
- Thread the parent proxy URL into the Glider rulefile/config generation.

Use `forward=direct://` when no parent proxy is set (current behavior).

### [ ] 5. Test coverage for the proxy-disabled rcfile path

**Fixed**: the two bugs originally noted here are resolved — the `else` branches
of the proxy conditionals now correctly reference `''${__sandbox_s6_scan_dir?}`
(`sandbox/default.nix:138`, `:160`), and the stray `$` in the socks5 guard
(`:155`) is gone.

**Still outstanding**: because `proxy.enable` defaults to `true`, those branches
only run when the proxy is disabled and are not exercised by the default
environments. Add a check (or extend the eval/VM tests) covering an environment
with `proxy.enable = false` so regressions in the proxy-disabled path are
caught.

### [ ] 6. Remove dead code in `sandbox/default.nix`

`defaultSystemPrompt` (line 30), `concat` (line 41), and `packagePrompt`
(line 50) are defined but never used. `defaultSystemPrompt` additionally reads
`./sandbox-prompt.txt`, which does not exist in `nix/pkgs/sandbox/` (the prompt
lives at `nix/lib/modules/sandbox-prompt.txt` and is consumed by
`options.nix`). The dead binding is only harmless because Nix never forces it.
Delete the three bindings.

---

## What I wouldn't port

**Dynamic config updates (`--control-fd`)**: this project's design is "build a
complete environment, launch it, done." There's no long-running host process
managing the sandbox. Adding one would be a fundamental architecture change for
limited benefit in the interactive CLI use case.

**macOS Seatbelt support**: bubblewrap is Linux-only. This is a platform
limitation, not something to port.

**Deny-then-allow filesystem model**: the allowlist-only model (nothing mounted
= nothing accessible) is already more restrictive than srt's model. The
granularity needed is only within the project directory, which is covered by
mandatory deny paths (item 1).

**Violation monitoring**: Linux doesn't have Seatbelt's log stream. The proxy
already blocks and could log denials. Adding strace-based monitoring would add
complexity with limited payoff. The useful signal (which domains were blocked)
is already available from Glider's verbose logging.

**`expandGlobPattern` / ripgrep scanning for nested repos**: srt scans 3 levels
deep for dangerous files in subdirectories. For a single project directory,
checking the top-level is likely sufficient. Nested repos with their own
`.git/hooks` are a real but less acute risk. If needed, `find` with
`-maxdepth 3` in the pre-bwrap check is simpler than pulling in ripgrep.

---

## Priority order

1. **Item 1 (mandatory deny paths)** — highest value; closes the most obvious
   escape vector (persisting malicious code in the project for post-sandbox
   execution).
2. **Item 2 (proxy env vars)** — small changes (add `NO_PROXY`, add the socks5
   `GIT_SSH_COMMAND` fallback) that make the existing proxy work for localhost
   and socks5-only traffic.
3. **Item 6 / item 5 (dead-code cleanup + proxy-disabled test)** — cheap
   correctness and coverage work.
4. **Item 3 (symlink validation)** — small defensive addition; also a
   prerequisite for doing item 1 safely.
5. **Item 4 (parent proxy)** — usability feature for corporate environments.

## environments

Attribute set of sandbox environments\. Each environment combines one
or more profiles and produces a runnable sandbox script\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.enable



Whether to enable this sandbox environment\. The flake module
exports only enabled environments as packages\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
false
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.packages



Packages to be made available inside the sandbox\.



*Type:*
list of package



*Default:*

```nix
[ ]
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.args



Additional arguments to pass to the bubblewrap
` bwrap ` executable\.



*Type:*
list of ((submodule) or string convertible to it)



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "--ro-bind-try"
  "\"\${PRJ_DATA_DIR}:/data\""
]
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.args\.\*\.quote



Whether to shell-quote the value\. When ` false ` (the default for
` args `), the value is inserted into the launcher script as shell
syntax: ` ~ ` and ` $VAR ` expand on the host when the sandbox starts,
and unquoted spaces split it into several arguments\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.args\.\*\.value



The value of the argument\.



*Type:*
string

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.bubblewrap



The bubblewrap package to use\.



*Type:*
package



*Default:*

```nix
pkgs.bubblewrap
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.env



Environment variables to set inside the sandbox\. Plain
strings are passed literally\. For shell syntax such as ` ~ ` or
` $VAR `, expanded on the host when the sandbox starts, use
` { value = ...; quote = false; } `\.



*Type:*
attribute set of ((submodule) or string convertible to it)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  GREETING = "wear sunscreen";
  PROJECT_CACHE = {
    value = "\"$HOME/.cache/project\"";
    quote = false;
  };
}

```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.env\.\<name>\.quote



Whether to shell-quote the value\. When ` true ` (the default for
` env `), the value is passed literally\. Set it to ` false ` to insert
the value as shell syntax instead, e\.g\. to expand ` ~ ` or ` $VAR ` on
the host when the sandbox starts; then quote any expansion that may
contain spaces\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.env\.\<name>\.value



The value of the argument\.



*Type:*
string

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.envPassthrough



Names of host environment variables to pass into the sandbox
unchanged, if they are set\. The sandbox otherwise starts with
an empty environment\. Values in
` environments.<name>.env ` take precedence\.

The ` basic-tooling ` profile passes ` TERM ` and ` COLORTERM `
and sets ` LANG=C.UTF-8 `, a locale that needs no locale data\.
Passing other locales (` LANG `, ` LC_* `) only helps if the
sandbox can find their data, e\.g\. via ` LOCALE_ARCHIVE `\.



*Type:*
list of string matching the pattern ^\[a-zA-Z_]\[0-9a-zA-Z_]\*$



*Default:*

```nix
[ ]
```



*Example:*

```nix
[
  "TERM"
  "COLORTERM"
  "TZ"
]
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.extend



Function that permits extending this environment by applying
additional modules\.



*Type:*
raw value *(read only)*



*Default:*

```nix
<function>
```



*Example:*

```nix
{
  my-extended-environment = environments.my-environment.extend [
    ({pkgs, ...}: {
      packages = with pkgs; [
        hello
        worldofgoo
      ];
    })
  ];
}

```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.filesystem



Host filesystem protections applied to the writable project
directory before ` bwrap ` is invoked\.



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.filesystem\.denyVcsMetadata



Bind every recognized version-control metadata root
(see ` environments.<name>.filesystem.vcsMetadataDirs `)
found under the project directory read-only inside the
sandbox\. When a root is a gitlink file (a submodule or
linked worktree), both the file and the directory it
points to are locked, as long as both are inside the
project\.

This stops the sandboxed CLI from modifying existing
repositories to plant code that runs on the host
*after* the sandbox exits — for example
` .git/hooks/* `, or ` core.fsmonitor `, ` core.hooksPath `,
or aliases in ` .git/config `, or the ` .jj ` equivalents\.

If a metadata root, or the path a gitlink points to,
is reached through a symlink inside the project, the
sandbox refuses to start: the CLI could replace that
symlink, which a bind mount cannot cover\.

**Warning:** Only metadata roots that exist at launch are protected\.
Read-only binds cannot stop the CLI from creating a new
repository (say, ` some/dir/.git `) elsewhere in the
project, and host-side tools such as
` git status ` will honor its configuration\.
Hooks that live in the working tree (e\.g\.
` core.hooksPath = .husky `, hooks symlinked to tracked
files, or ` pre-commit ` configuration) are not
protected either\.

**Note:** Locking is whole-root: with this enabled the CLI cannot
write to ` .git `/` .jj ` at all, so committing from inside
the sandbox fails, and so do most ` jj `
commands, which snapshot the working copy\. Disable this
option (or narrow
` environments.<name>.filesystem.vcsMetadataDirs `)
if the CLI must write version-control state\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.filesystem\.stateDirs



Persistent directories owned by the sandbox, typically
an LLM CLI’s configuration and login state\.

Each entry is stored on the host at
` ${XDG_STATE_HOME:-~/.local/state}/bubbllmwrap/<name> `
(created with mode ` 0700 ` if missing) and bound
read-write at its ` target ` inside the sandbox\.

Use this instead of binding the host’s own configuration
directory\. Many CLIs run commands named in their config
(hooks, MCP servers, notifiers), so a writable bind of
the host’s config lets the sandboxed CLI plant commands
that the host CLI later runs unsandboxed\.



*Type:*
attribute set of (submodule)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  claude-code.target = "~/.claude";
}

```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.filesystem\.stateDirs\.\<name>\.enable



Whether to enable this state directory\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
true
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.filesystem\.stateDirs\.\<name>\.name



Name of the directory under the host-side state
root\. Environments that use the same name share
the directory\.



*Type:*
string matching the pattern \[A-Za-z0-9_]\[A-Za-z0-9\._-]\*



*Default:*
the attribute name

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.filesystem\.stateDirs\.\<name>\.target



Where to mount the directory inside the sandbox:
an absolute path, or a path starting with ` ~/ `,
which is resolved against the home directory\.



*Type:*
string matching the pattern (/|~/)\.\*



*Example:*

```nix
"~/.claude"
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.filesystem\.vcsMetadataDirs



Names recognized as version-control metadata roots\.
Every match found under the project directory is bound
read-only when
` environments.<name>.filesystem.denyVcsMetadata `
is enabled\. Entries are ` find -name ` patterns,
so shell globs work; they may not contain ` / ` or ` : `\.

Recognition is by name and resolved at runtime, so
nested repositories, submodules, and linked worktrees
are all covered by the same rule\.



*Type:*
list of string matching the pattern \[^/:]+



*Default:*

```nix
[
  ".git"
  ".jj"
]
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.hooks



Lifecycle hooks to run before, during, and after entering the
bubblewrap sandbox\.



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.hooks\.enter



Commands to run upon entering the bubblewrap sandbox\.



*Type:*
strings concatenated with “\\n”



*Default:*

```nix
""
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.hooks\.exit



Commands to run upon exiting the bubblewrap sandbox\.



*Type:*
strings concatenated with “\\n”



*Default:*

```nix
""
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.hooks\.post



Commands to run after exiting the bubblewrap sandbox\.

**Warning:** These commands run on the host, unsandboxed, against a
project directory the sandboxed CLI may have modified\.
Running tools that read project configuration here
(for example ` git status `, which honors
` core.fsmonitor ` from repository config) can execute
code the CLI planted\.



*Type:*
strings concatenated with “\\n”



*Default:*

```nix
""
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.hooks\.pre



Commands to run before entering the bubblewrap sandbox\.



*Type:*
strings concatenated with “\\n”



*Default:*

```nix
""
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.llm



LLM CLI configuration (package, command, arguments, and
prompt) used inside this environment\.



*Type:*
open submodule of anything



*Default:*

```nix
{ }
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.llm\.package



The LLM CLI package\.



*Type:*
package



*Default:*

```nix
"<derivation>"
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.llm\.args



Additional command-line arguments to pass to the CLI\.



*Type:*
list of ((submodule) or string convertible to it)



*Default:*

```nix
[ ]
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.llm\.args\.\*\.quote



Whether to shell-quote the value\. When ` false ` (the default for
` args `), the value is inserted into the launcher script as shell
syntax: ` ~ ` and ` $VAR ` expand on the host when the sandbox starts,
and unquoted spaces split it into several arguments\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.llm\.args\.\*\.value



The value of the argument\.



*Type:*
string

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.llm\.cmd



Name of the CLI executable\.



*Type:*
non-empty string



*Default:*

```nix
"llm.config.package.meta.mainProgram or lib.getName llm.config.package"
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.llm\.prompt



Custom system prompt text for the LLM CLI within this
sandbox\.

**Note:** This option is merely a convenience; in order to use
the prompt stored herein, you will have to pass it as
the value of an environment variable, CLI argument, or
configuration file parameter for the LLM CLI in
question\.  For instance, with ` claude-code `,
you could use this prompt as the value of the
` --append-system-prompt ` CLI argument\.



*Type:*
strings concatenated with “\\n”



*Default:*

```nix
""
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.name



Environment identifier\. Defaults to the attribute name in
` environments `\.



*Type:*
string



*Default:*

```nix
"‹name›"
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.proxy



HTTP proxy configuration for filtering of network traffic to
and from the sandbox\.

**Note:** Uses the [glider](https://github\.com/nadoo/glider) forward
proxy\.



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.proxy\.enable



Whether to enable HTTP proxy with domain allowlist filtering\.



*Type:*
boolean



*Default:*

```nix
true
```



*Example:*

```nix
true
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.proxy\.package



The glider package to use\.



*Type:*
package



*Default:*

```nix
pkgs.glider
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.proxy\.allowList



Domain names allowed through the proxy\. Each entry also
allows its subdomains, on any port\. Requests for other
destinations, including IP addresses, are rejected
without being resolved\.



*Type:*
list of string



*Default:*

```nix
[ ]
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.proxy\.extraConfig



Additional Glider configuration lines to append\.



*Type:*
strings concatenated with “\\n”



*Default:*

```nix
""
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.proxy\.extraRules



Addition Glider rule specifications\.



*Type:*
strings concatenated with “\\n”



*Default:*

```nix
""
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.proxy\.script



This option has no description\.



*Type:*
package *(read only)*



*Default:*

```nix
"<derivation>"
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.script



The generated script that enters the environment\.



*Type:*
package *(read only)*



*Default:*

```nix
"<derivation>"
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.seccomp



Options related to system call filtering in the sandbox
using the ` apply-seccomp ` program\.

**Note:** System calls are filtered using [the ` apply-seccomp ` program](https://github\.com/anthropic-experimental/sandbox-runtime/tree/7a725a314f8ce0a6404f275292d8eec557ba949a/vendor/seccomp-src)
from the [` anthropic-experimental/sandbox-runtime `](https://github\.com/anthropic-experimental/sandbox-runtime)
project\.

See [the “Unix Socket Restrictions (Linux)” section](https://github\.com/anthropic-experimental/sandbox-runtime\#unix-socket-restrictions-linux)
from that project’s documentation for details on the goals of
this program and how it achieves them\.



*Type:*
submodule



*Default:*

```nix
{ }
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.seccomp\.enable



When enabled, run the LLM CLI under the
` apply-seccomp ` wrapper command that causes
certain system calls to be blocked\.

**Warning:** Among other things, this blocks creating ` AF_UNIX `
sockets\. With it disabled, the CLI can connect to any
Unix socket reachable through a bind mount (read-only
binds don’t prevent ` connect(2) `), such as the Nix
daemon socket under ` /nix/var/nix `, and so reach
services outside the proxy\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.seccomp\.denyTerminalInjection



Apply a seccomp filter to the whole sandbox that refuses
the ` TIOCSTI ` and ` TIOCLINUX ` ioctls\.

The sandbox shares the host’s terminal\. Without this
filter, a process inside can push keystrokes into the
terminal’s input queue, and whatever is still queued
when the sandbox exits is run by the host shell
(CVE-2017-5226)\. Linux 6\.2 and later can refuse
` TIOCSTI ` system-wide (` dev.tty.legacy_tiocsti = 0 `),
but not every distribution enables that\.

This is independent of
` environments.<name>.seccomp.enable `\.



*Type:*
boolean



*Default:*

```nix
true
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## profiles



Attribute set of configurations meant to be imported into one or more
entries in the ` environments ` attribute set\.

Use this for attaching names to groups of related options you’d like to
mix-and-match in ` environments `\.



*Type:*
attribute set of module



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  config,
  lib,
  pkgs,
  ...
}: {
  profiles = {
    basic-tooling = {
      packages = with pkgs; [
        jq
        procps
        stdenv
      ];
    };

    my-little-language = {

    };
  };
}

environments = {
  my-stuff = _: {
    imports = with config.profiles; [
      basic-tooling
      my-little-language
    ];
  };
};

```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



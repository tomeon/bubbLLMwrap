## environments

Attribute set of sandbox environments\. Each environment combines one
or more profiles and produces a runnable sandbox script\.



*Type:*
attribute set of (open submodule of anything)



*Default:*

```nix
{ }
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.enable



Whether to enable this sandbox environment\.



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



Whether to shell quote the value of this argument \.  Set this to
false if you want to do things like interpolate environment
variables’ values in this value\.



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



Environment variables to set inside the sandbox\.



*Type:*
attribute set of ((submodule) or string convertible to it)



*Default:*

```nix
{ }
```



*Example:*

```nix
{
  BAZ = {
    quote = true;
    value = "wear sunscreen";
  };
  FOO = "\"$BAR\"";
}
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.env\.\<name>\.quote



Whether to shell quote the value of this argument \.  Set this to
false if you want to do things like interpolate environment
variables’ values in this value\.



*Type:*
boolean



*Default:*

```nix
false
```

*Declared by:*
 - [nix/lib/modules/options\.nix](../nix/lib/modules/options.nix)



## environments\.\<name>\.env\.\<name>\.value



The value of the argument\.



*Type:*
string

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



Whether to shell quote the value of this argument \.  Set this to
false if you want to do things like interpolate environment
variables’ values in this value\.



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



Environment identifier\. Defaults to the attribute name in the
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
open submodule of anything



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



List of domain names allowed through the proxy\.  All other
domains are blocked with a ` 403 Unauthorized ` response\.



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



## environments\.\<name>\.proxy\.port



Port for the proxy to listen on\. ` 0 ` means a random high
port will be selected at runtime\.



*Type:*
16 bit unsigned integer; between 0 and 65535 (both inclusive)



*Default:*

```nix
0
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

**Note:** System calls are filtered using [the ` apply-seccomp ` program](https://github\.com/anthropic-experimental/sandbox-runtime/tree/34a39e0139d9d3a386abccb8dbf4c0411b4d1028/vendor/seccomp-src)
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



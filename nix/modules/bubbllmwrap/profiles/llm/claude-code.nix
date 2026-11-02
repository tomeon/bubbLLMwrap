{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}: {
  _file = ./claude-code.nix;

  imports = [
    (modulesPath + "/profiles/tooling/basic.nix")
  ];

  profiles = {
    claude-code = lib.const {
      imports = [config.profiles.basic-tooling];

      llm = llm: {
        disallowedTools = [
          "WebSearch"
          "WebFetch"
          "Read(/nix/store/**)"
          "Bash(curl:*)"
          "Bash(wget:*)"
        ];

        package = pkgs.claude-code;

        args = [
          "--dangerously-skip-permissions"

          "--disallowedTools"
          (lib.escapeShellArg (lib.concatStringsSep "," llm.config.disallowedTools))

          "--append-system-prompt"
          (lib.escapeShellArg llm.config.prompt)
        ];
      };

      # Sandbox-owned config and login state, not the host's `~/.claude` and
      # `~/.claude.json`: the host CLI runs hooks and MCP server commands from
      # those, so a writable bind would let the sandbox plant commands that run
      # unsandboxed later. `CLAUDE_CONFIG_DIR` moves `.claude.json` into the
      # same directory.
      filesystem.stateDirs.claude-code.target = "~/.claude";

      env = {
        CLAUDE_CONFIG_DIR = {
          value = "~/.claude";
          quote = false;
        };
        CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC = "1";
        DISABLE_AUTOUPDATER = "1";
        DISABLE_ERROR_REPORTING = "1";
        DISABLE_BUG_COMMAND = "1";
        DISABLE_INSTALLATION_CHECKS = "1";
        DISABLE_NON_ESSENTIAL_MODEL_CALLS = "1";
        DISABLE_TELEMETRY = "1";
        ANTHROPIC_API_URL = "https://api.anthropic.com";
      };

      proxy.allowList = [
        "api.anthropic.com"
        "mcp-proxy.anthropic.com"
        "platform.claude.com"
      ];
    };
  };
}

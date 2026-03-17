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
          (lib.escapeRegex (lib.concatStringsSep "," llm.config.disallowedTools))

          "--append-system-prompt"
          (lib.escapeShellArg llm.config.prompt)
        ];
      };

      args = [
        "--bind-try"
        "~/.claude"
        "~/.claude"

        "--bind-try"
        "~/.claude.json"
        "~/.claude.json"
      ];

      env = {
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

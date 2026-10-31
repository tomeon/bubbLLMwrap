{
  config,
  lib,
  modulesPath,
  pkgs,
  ...
}: {
  _file = ./codex.nix;

  imports = [(modulesPath + "/profiles/tooling/basic.nix")];

  profiles = {
    codex = lib.const {
      imports = [config.profiles.basic-tooling];

      llm = {
        package = pkgs.codex;

        # https://developers.openai.com/codex/config-reference
        # https://developers.openai.com/codex/config-schema.json
        args = [
          "--full-auto"
        ];
      };

      proxy.allowList = [
        "api.github.com"
        "auth.openai.com"
        "chatgpt.com"
        #"ab.chatgpt.com"
      ];

      # Sandbox-owned config and login state, not the host's `~/.codex`: the
      # host CLI runs `notify`, MCP server, and hook commands from its config,
      # so a writable bind would let the sandbox plant commands that run
      # unsandboxed later.
      filesystem.stateDirs.codex.target = "~/.codex";

      env.CODEX_HOME = "~/.codex";
    };
  };
}

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

      args = [
        "--bind-try"
        "~/.codex"
        "~/.codex"
      ];
    };
  };
}

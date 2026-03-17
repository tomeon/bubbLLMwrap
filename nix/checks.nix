{self, ...}: {
  perSystem = {config, ...}: {
    checks = {
      eval-sandbox = config.legacyPackages.callPackage ./checks/eval-sandbox.nix {
        inherit (config) bubbllmwrap;
      };

      options-docs = config.legacyPackages.callPackage ./checks/options-docs.nix {
        inherit self;
      };
    };
  };
}

{self, ...}: {
  perSystem = {
    bubbllmwrapScope,
    config,
    ...
  }: {
    checks = {
      eval-sandbox = bubbllmwrapScope.callPackage ./checks/eval-sandbox.nix {
        inherit (config) bubbllmwrap;
      };

      options-docs = bubbllmwrapScope.callPackage ./checks/options-docs.nix {
        inherit self;
      };
    };
  };
}

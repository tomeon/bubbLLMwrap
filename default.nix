# flake-compat shim for non-flake Nix usage
(import
  (
    let
      lock = builtins.fromJSON (builtins.readFile ./flake.lock);
      nodeName =
        lock.nodes.root.inputs.flake-compat
        or (throw "flake-compat input not found in flake.lock");
      node = lock.nodes.${nodeName};
    in
      fetchTarball {
        url = "https://github.com/${node.locked.owner}/${node.locked.repo}/archive/${node.locked.rev}.tar.gz";
        sha256 = node.locked.narHash;
      }
  )
  {src = ./.;})
.defaultNix

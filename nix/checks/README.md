# NixOS Sandbox Tests

This directory contains NixOS VM tests for the bubblewrap sandbox.

## Test file

- `eval-sandbox.nix`: a NixOS VM test that exercises **every canned environment**
  (the `<llm>-<language>` cross-product). For each environment it swaps in a fake
  LLM CLI that runs assertions covering:
  - Environment variables (simple, quoted-with-spaces, numeric)
  - Package availability (each profile package's `mainProgram` is on `PATH`)
  - Project directory access (reads `./test.txt` from the bind-mounted project)
  - Filesystem isolation (`cd /nope` is refused)
  - Proxy configuration (`http(s)_proxy` / `HTTP(S)_PROXY` are set)
  - Network filtering (an allowed host returns `200`; a blocked host returns `403`/`502`)
  - Lifecycle hooks (`pre`, `enter`, `exit`, `post` phases run)

The check is wired up in [`nix/checks.nix`](../checks.nix) as
`checks.<system>.eval-sandbox`.

## Running tests

```bash
# Run the sandbox test
nix build .#checks.x86_64-linux.eval-sandbox -L

# Or use nix flake check to run all checks
nix flake check
```

## Test structure

The test:

- Derives a test environment from each canned environment via `.extend`,
  forcing in a fake LLM package that serves as the assertion runner.
- Boots a single NixOS VM running nginx, which serves both an allowed and a
  blocked virtual host (resolved via `/etc/hosts`) to validate proxy filtering.
- Runs each environment's generated `script` against a temporary project
  directory and asserts it exits successfully.

The test runs inside a NixOS VM with the permissions bubblewrap needs, making it
possible to test actual isolation.

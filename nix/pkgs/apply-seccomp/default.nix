{
  lib,
  fetchFromGitHub,
  libseccomp,
  runCommandCC,
  bun,
}:
runCommandCC "apply-seccomp" {
  src = fetchFromGitHub {
    owner = "anthropic-experimental";
    repo = "sandbox-runtime";
    rev = "7a725a314f8ce0a6404f275292d8eec557ba949a";
    hash = "sha256-1QwUOtgOYcVm61nLCeQL46O/+G/LyXSv+ZnC3la2Ajc=";
  };

  executable = true;
  preferLocalBuild = true;
  allowSubstitutes = false;

  nativeBuildInputs = [bun libseccomp];

  meta = {
    description = "Apply seccomp BPF filter in an isolated PID namespace";
    longDescription = ''
      This program applies a baked-in seccomp BPF filter, isolates the target
      command in a nested user+PID+mount namespace so it cannot see or ptrace
      any process that lacks the filter, applies the filter with
      prctl(PR_SET_SECCOMP), and execs the command.
    '';
    license = lib.licenses.asl20;
    mainProgram = "apply-seccomp";
  };
} ''
  cp -r --no-preserve=mode -t . "''${src}/vendor"
  sed -i -e "s/'-static', //" ./vendor/seccomp/build.ts
  bun ./vendor/seccomp/build.ts
  for exe in ./vendor/seccomp/*/apply-seccomp; do
    install -Dm0755 "$exe" "''${out}/bin/apply-seccomp"
  done
''

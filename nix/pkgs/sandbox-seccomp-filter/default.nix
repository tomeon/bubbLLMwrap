# Seccomp BPF program applied to the whole sandbox via `bwrap --add-seccomp-fd`.
# See ./filter.c for what it blocks and why.
{
  lib,
  libseccomp,
  runCommandCC,
}:
runCommandCC "sandbox-seccomp-filter.bpf" {
  src = ./filter.c;
  buildInputs = [libseccomp];

  meta = {
    description = "Seccomp BPF program that blocks terminal input injection (TIOCSTI/TIOCLINUX)";
    platforms = lib.platforms.linux;
  };
} ''
  $CC -O2 -Wall -Wextra -Werror -o gen "$src" -lseccomp
  ./gen > "$out"
  test -s "$out"
''

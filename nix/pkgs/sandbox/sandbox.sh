#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=../sandbox-lib/sandbox-lib.sh
source "$SANDBOX_LIB" || exit

# Need this for defining the `USER` environment variable in the sandbox.
__sandbox_infer_user

# Protect against these variables being clobbered in the `pre` hook.
for __sandbox_var in "${!SANDBOX_@}"; do
  readonly "$__sandbox_var"
done

unset __sandbox_var

while (("$#" > 0)); do
  case "$1" in
  --sandbox-project-dir)
    if (("$#" < 2)); then
      printf 1>&2 -- 'Error: %s requires an argument\n' "$1"
      exit 1
    fi
    project_dir="$2"
    shift
    ;;
  --)
    shift
    break
    ;;
  *)
    break
    ;;
  esac

  shift
done

project_dir="${project_dir:-"${PWD:-"$(pwd 2>/dev/null)"}"}"

# Sets `__sandbox_project_dir` (absolute, symlinks kept: the in-sandbox mount
# point) and `__sandbox_project_dir_real` (symlinks resolved: the bind source).
__sandbox_resolve_project_dir "$project_dir" || exit

# Keep `project_dir` available to the `pre` hook, now as an absolute path.
project_dir="$__sandbox_project_dir"

printf 1>&2 -- 'Starting bubblewrap sandbox in %q\n' "$project_dir"

if [[ -v HOME ]] && [[ -n $HOME ]]; then
  home="${HOME}"
else
  home=~
fi

if [[ -v SANDBOX_VARS ]] && [[ -n $SANDBOX_VARS ]]; then
  # shellcheck disable=SC1090
  source "$SANDBOX_VARS"
fi

if [[ -v SANDBOX_PRE_HOOK ]] && [[ -n $SANDBOX_PRE_HOOK ]]; then
  # shellcheck disable=SC1090
  source "$SANDBOX_PRE_HOOK"
fi

if ! [[ -v __sandbox_bwrap_args ]]; then
  declare -ar __sandbox_bwrap_args=()
fi

# Sandbox-owned persistent directories (e.g. LLM config and login state).
__sandbox_add_state_dir_args "$home" || exit

# Read-only binds that lock version-control metadata roots under the project.
# These must land *after* the writable project bind below so bwrap's
# last-writer-wins ordering makes them stick.
__sandbox_add_vcs_deny_args "$__sandbox_project_dir_real" "$__sandbox_project_dir" || exit

# Seccomp filter for the whole sandbox; blocks terminal input injection
# (TIOCSTI/TIOCLINUX). bwrap reads the compiled BPF program from this fd.
declare -a __sandbox_seccomp_args=()
if [[ -n ${SANDBOX_SECCOMP_FILTER:-} ]]; then
  exec {__sandbox_seccomp_fd}<"$SANDBOX_SECCOMP_FILTER"
  __sandbox_seccomp_args+=(--add-seccomp-fd "$__sandbox_seccomp_fd")
fi

declare -a __sandbox_bwrap_args_runtime=()

while (("$#" > 0)); do
  case "$1" in
  --)
    shift
    break
    ;;
  *)
    __sandbox_bwrap_args_runtime+=("$1")
    ;;
  esac

  shift
done

if [[ -n ${SANDBOX_DEBUG:-} ]]; then
  set -x
fi

bwrap \
  --die-with-parent \
  --unshare-all \
  --proc /proc \
  --dev /dev \
  --tmpfs /tmp \
  --dir /var \
  --dir /run \
  --dir /usr/bin \
  --dir /bin \
  --dir /etc/ssl \
  --dir /etc/ssl/certs \
  --ro-bind "${SANDBOX_RESOLV_CONF?}" /etc/resolv.conf \
  --ro-bind "${SANDBOX_HOSTS?}" /etc/hosts \
  --ro-bind "${SANDBOX_CA_BUNDLE?}" /etc/ssl/certs/ca-bundle.crt \
  --symlink /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt \
  --symlink "${SANDBOX_USR_BIN_ENV?}" /usr/bin/env \
  --symlink "${SANDBOX_BIN_SH?}" /bin/sh \
  --ro-bind /nix/store /nix/store \
  --ro-bind /etc/passwd /etc/passwd \
  --ro-bind /etc/group /etc/group \
  --clearenv \
  "${__sandbox_seccomp_args[@]}" \
  "${__sandbox_bwrap_args[@]}" \
  "${__sandbox_state_args[@]}" \
  --bind "$__sandbox_project_dir_real" "$__sandbox_project_dir" \
  "${__sandbox_deny_args[@]}" \
  --chdir "$__sandbox_project_dir" \
  --setenv HOME "$home" \
  --setenv USER "$__sandbox_user" \
  --setenv PATH "${SANDBOX_PATH?}" \
  "${__sandbox_bwrap_args_runtime[@]}" \
  -- \
  "$SANDBOX_ENTRYPOINT" "$@" || __sandbox_rc="$?"

__sandbox_rc="${__sandbox_rc:-0}"
readonly __sandbox_rc

if [[ -v SANDBOX_POST_HOOK ]] && [[ -n $SANDBOX_POST_HOOK ]]; then
  # shellcheck disable=SC1090
  source "$SANDBOX_POST_HOOK"
fi

exit "$__sandbox_rc"

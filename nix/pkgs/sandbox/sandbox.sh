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

if ! [[ -d $project_dir ]]; then
  printf 1>&2 -- 'Error: project directory %q does not exist\n' "$project_dir"
  exit 1
fi

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

# Read-only binds that lock version-control metadata roots under the project.
# These must land *after* the writable `--bind "$project_dir"` below so bwrap's
# last-writer-wins ordering makes them stick.
declare -a __sandbox_deny_args=()
__sandbox_add_vcs_deny_args "$project_dir"

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

set -x
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
  "${__sandbox_bwrap_args[@]}" \
  --bind "$project_dir" "$project_dir" \
  "${__sandbox_deny_args[@]}" \
  --chdir "$project_dir" \
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

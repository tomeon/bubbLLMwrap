#!/usr/bin/env bash

if command -v s6-mkfifo &>/dev/null; then
  __sandbox_mkfifo() {
    s6-mkfifo "$@"
  }
else
  __sandbox_mkfifo() {
    mkfifo "$@"
  }
fi

declare -fr __sandbox_mkfifo

# shellcheck disable=SC2329
__sandbox_cleanup() (
  if [[ -n ${__sandbox_s6_scan_dir:-} ]]; then
    # `svscanctl -q` is liable to lose logs, but we're about to delete all logs
    # anyway.
    s6-svscanctl -q "$__sandbox_s6_scan_dir"
  fi

  if [[ -n ${SANDBOX_S6_SVSCAN[1]} ]]; then
    local __sandbox_s6_svscan_stdin="${SANDBOX_S6_SVSCAN[1]}"
    exec {__sandbox_s6_svscan_stdin}<&- || :
  fi

  if [[ -n ${SANDBOX_S6_SVSCAN[0]} ]]; then
    local __sandbox_s6_svscan_stdout="${SANDBOX_S6_SVSCAN[0]}"
    exec {__sandbox_s6_svscan_stdout}>&- || :
  fi

  if [[ -n ${SANDBOX_S6_SVSCAN_PID:-} ]]; then
    kill "${SANDBOX_S6_SVSCAN_PID?}" &>/dev/null || :
  fi

  if [[ -n ${__sandbox_runtime_dir:-} ]]; then
    rm -f -r --one-file-system --preserve-root "$__sandbox_runtime_dir"
  fi
)

declare -fr __sandbox_cleanup

__sandbox_infer_user() {
  declare -g __sandbox_user

  if ! __sandbox_user="${USER:-"$({ id -un || whoami; } 2>/dev/null)"}" || [[ -z $__sandbox_user ]]; then
    printf 1>&2 -- 'Failed to determine current user; cannot continue\n'
    return 1
  fi

  readonly __sandbox_user
}

declare -fr __sandbox_infer_user

__sandbox_infer_uid() {
  declare -g __sandbox_uid

  if ! __sandbox_uid="${EUID:-"$(id -u 2>/dev/null)"}" || [[ -z $__sandbox_uid ]]; then
    __sandbox_infer_user || return
    local pwent
    if ! pwent="$(getent passwd "$__sandbox_user")" || [[ -z $pwent ]]; then
      printf 1>&2 -- 'Failed to retrieve passwd entry for current user; cannot continue\n'
      return 1
    else
      IFS=: read -r _ _ __sandbox_uid _ <<<"$pwent"
      if ! [[ $__sandbox_uid =~ ^[[:digit:]]$ ]]; then
        printf 1>&2 -- 'Failed to detemine UID of current user; cannot continue\n'
        return 1
      fi
    fi
  fi

  readonly __sandbox_uid
}

declare -fr __sandbox_infer_uid

__sandbox_init_runtime_dir() {
  __sandbox_infer_uid || return

  declare -g __sandbox_runtime_dir_parent

  __sandbox_runtime_dir_parent="${XDG_RUNTIME_DIR:-"/run/user/${__sandbox_uid}"}"
  if ! mkdir -p "$__sandbox_runtime_dir_parent" &>/dev/null || ! [[ -d $__sandbox_runtime_dir_parent ]]; then
    __sandbox_runtime_dir_parent="${TMPDIR:-/tmp}/user/${__sandbox_uid}"
  fi

  readonly __sandbox_runtime_dir_parent

  declare -g __sandbox_runtime_dir
  __sandbox_runtime_dir="$(mktemp -d "${__sandbox_runtime_dir_parent}/bubbllmwrap-sandbox.$$.XXXXXXXXXX")"
  readonly __sandbox_runtime_dir
}

declare -fr __sandbox_init_runtime_dir

__sandbox_init_s6_scan_dir() {
  __sandbox_init_runtime_dir || return

  declare -gr __sandbox_s6_scan_dir="${__sandbox_runtime_dir}/s6"
  cp -aT "${SANDBOX_S6_SCAN_DIR?}" "$__sandbox_s6_scan_dir"
  chmod -R u+w "$__sandbox_s6_scan_dir"
}

declare -fr __sandbox_init_s6_scan_dir

__sandbox_setup() {
  trap __sandbox_cleanup INT TERM QUIT EXIT
  __sandbox_init_s6_scan_dir
}

declare -fr __sandbox_setup

__sandbox_s6_svscan() {
  local -a args=("$@")

  local notif_path
  notif_path="$(mktemp -u "${__sandbox_runtime_dir}/.s6-svscan-notif.XXXXXXXXXX")"
  __sandbox_mkfifo -m 600 "$notif_path" || {
    local rc="$?"
    rm -f "$notif_path"
    return "$rc"
  }

  local -x SANDBOX_S6_SVSCAN_LOG_FIFO="${__sandbox_s6_scan_dir?}/s6-svscan-log/fifo"
  __sandbox_mkfifo "$SANDBOX_S6_SVSCAN_LOG_FIFO"
  echo 3 >"${__sandbox_s6_scan_dir}/s6-svscan-log/notification-fd"

  declare -gx SANDBOX_S6_LOG_DIR="${__sandbox_runtime_dir}/log"

  declare -ga SANDBOX_S6_SVSCAN
  declare -g SANDBOX_S6_SVSCAN_PID

  # shellcheck disable=SC2034
  coproc SANDBOX_S6_SVSCAN {
    exec {notif_w}>"$notif_path"

    # Use `redirfd` here in order to open the FIFO non-blocking
    redirfd -r 0 /dev/null \
      redirfd -wnb 1 "$SANDBOX_S6_SVSCAN_LOG_FIFO" \
      fdmove -c 2 1 \
      s6-svscan -d "$notif_w" "${args[@]}" "${__sandbox_s6_scan_dir?}"
  }

  read -r _ <"$notif_path"

  rm -f "$notif_path"
}

declare -fr __sandbox_s6_svscan

__sandbox_s6_svwait() {
  local svc="${1?}"
  shift

  s6-svwait "$@" "${__sandbox_s6_scan_dir?}/${svc}"
}

declare -fr __sandbox_s6_svwait

# Resolve the project directory into two absolute paths:
#
# - `__sandbox_project_dir`: the path as the user names it, with symlinks kept.
#   This is where the project is mounted inside the sandbox and where the CLI
#   starts, so paths look the same inside and out.
# - `__sandbox_project_dir_real`: the same directory with symlinks resolved.
#   This is the bind source and the root of the metadata scan.
__sandbox_resolve_project_dir() {
  local dir="${1?}"

  if ! [[ -d $dir ]]; then
    printf 1>&2 -- 'Error: project directory %q does not exist\n' "$dir"
    return 1
  fi

  declare -g __sandbox_project_dir __sandbox_project_dir_real
  __sandbox_project_dir="$(realpath -s -- "$dir")" || return
  __sandbox_project_dir_real="$(realpath -e -- "$dir")" || return
  readonly __sandbox_project_dir __sandbox_project_dir_real
}

declare -fr __sandbox_resolve_project_dir

# Lock recognized version-control metadata roots read-only.
#
# The project directory is bind-mounted writable, so without this the sandboxed
# CLI could plant code that runs on the host *after* the sandbox exits — e.g.
# `.git/hooks/pre-commit` (fires on the next `git commit`), `core.fsmonitor` or
# aliases in `.git/config`, or the `.jj` equivalents. Rather than enumerate
# every dangerous file across every SCM and every nesting location (an unbounded
# game), we recognize metadata *roots* by directory name and bind each one
# read-only, wholesale. That is a strict superset of the executable surface
# inside, and roots are *discovered*, not enumerated, so submodules, linked
# worktrees, and nested repos are all covered by the same rule.
#
# This only protects roots that exist at launch: read-only binds cannot stop the
# CLI from creating a new `.git` somewhere else in the project.
#
# The recognized names arrive from the module via SANDBOX_VCS_METADATA_DIRS
# (colon-separated, e.g. ".git:.jj"; empty disables the feature).
#
# Arguments: the resolved project directory (scan root and bind-source prefix)
# and the project's mount point inside the sandbox (bind-destination prefix).
#
# Populates the global `__sandbox_deny_args` array with `--ro-bind` arguments.
__sandbox_add_vcs_deny_args() {
  local real_project_dir="${1?}" project_mount="${2?}"

  declare -ga __sandbox_deny_args
  __sandbox_deny_args=()

  local spec="${SANDBOX_VCS_METADATA_DIRS:-}"
  [[ -n $spec ]] || return 0

  local -a names=()
  IFS=: read -r -a names <<<"$spec"

  local -a find_expr=()
  local name
  for name in "${names[@]}"; do
    [[ -n $name ]] || continue
    ((${#find_expr[@]})) && find_expr+=(-o)
    find_expr+=(-name "$name")
  done
  ((${#find_expr[@]})) || return 0

  # Deduplicate binds by resolved path (a submodule gitlink and the superproject
  # scan can both point at the same directory under `.git/modules`).
  declare -gA __sandbox_vcs_seen=()

  # `-prune` stops the descent at each metadata root, so we never recurse into a
  # `.git` we have already found. Depth is unbounded on purpose — nested repos
  # can sit anywhere — at the cost of walking the whole tree on every launch.
  local found
  while IFS= read -r -d '' found; do
    __sandbox_lock_vcs_path "$real_project_dir" "$project_mount" "$found" 1
  done < <(find "$real_project_dir" \( "${find_expr[@]}" \) -prune -print0 2>/dev/null)

  unset __sandbox_vcs_seen
}

declare -fr __sandbox_add_vcs_deny_args

# Resolve a candidate metadata path and, when it lives inside the project,
# append a read-only bind for it at the matching path inside the sandbox.
#
# A `.git` *file* is a gitlink (submodule or linked worktree). The file itself
# is locked so it cannot be repointed at a directory the CLI controls, and its
# `gitdir:` target is locked too. Gitlinks are followed one level only, which
# also stops self-referencing or cyclic gitlinks.
__sandbox_lock_vcs_path() {
  local real_project_dir="${1?}" project_mount="${2?}" path="${3?}" follow="${4?}"

  local real
  real="$(realpath -e -- "$path" 2>/dev/null)" || return 0

  # Symlink-escape guard: never bind a target outside the project directory. A
  # `.git` symlinked to `/` would otherwise lock (and expose) host paths.
  if [[ $real != "$real_project_dir" && $real != "$real_project_dir"/* ]]; then
    printf 1>&2 -- 'warning: skipping VCS metadata %q — resolves outside project (%q)\n' "$path" "$real"
    return 0
  fi

  [[ -z ${__sandbox_vcs_seen["$real"]:-} ]] || return 0
  __sandbox_vcs_seen["$real"]=1

  if [[ -d $real ]] || [[ -f $real ]]; then
    local dest="${project_mount}${real#"$real_project_dir"}"
    __sandbox_deny_args+=(--ro-bind "$real" "$dest")
    printf 1>&2 -- 'locking VCS metadata read-only: %q\n' "$dest"
  fi

  if [[ -f $real ]] && ((follow)); then
    local line gitdir=
    while IFS= read -r line; do
      if [[ $line == 'gitdir: '* ]]; then
        gitdir="${line#gitdir: }"
        break
      fi
    done <"$real"
    [[ -n $gitdir ]] || return 0
    [[ $gitdir == /* ]] || gitdir="$(dirname -- "$real")/$gitdir"
    __sandbox_lock_vcs_path "$real_project_dir" "$project_mount" "$gitdir" 0
  fi
}

declare -fr __sandbox_lock_vcs_path

# Bind sandbox-owned persistent directories (an LLM CLI's config and login
# state, say) from the host into the sandbox, instead of sharing the host's own
# copies. Anything the sandbox writes there stays out of the host tool's config.
#
# Expects `__sandbox_state_dirs` (from the generated vars script) to hold
# name/target pairs. Each name maps to `<state root>/<name>` on the host, where
# the state root is `${XDG_STATE_HOME:-~/.local/state}/bubbllmwrap`; missing
# directories are created with mode 0700. Each target is an absolute path, or a
# path starting with `~/`, which is resolved against the given home directory.
#
# Populates the global `__sandbox_state_args` array with `--bind` arguments.
__sandbox_add_state_dir_args() {
  local home="${1?}"

  declare -ga __sandbox_state_args
  __sandbox_state_args=()

  [[ -v __sandbox_state_dirs ]] || return 0

  local state_root="${XDG_STATE_HOME:-}"
  [[ $state_root == /* ]] || state_root="${home}/.local/state"
  state_root+=/bubbllmwrap

  local i name target src
  for ((i = 0; i + 1 < ${#__sandbox_state_dirs[@]}; i += 2)); do
    name="${__sandbox_state_dirs[i]}"
    target="${__sandbox_state_dirs[i + 1]}"

    # A literal `~/` prefix is what we're matching, so no tilde expansion.
    # shellcheck disable=SC2088
    case "$target" in
    '~/'*) target="${home}/${target#'~/'}" ;;
    /*) ;;
    *)
      printf 1>&2 -- 'Error: state directory target %q must be absolute or start with ~/\n' "$target"
      return 1
      ;;
    esac

    src="${state_root}/${name}"
    if ! [[ -d $src ]]; then
      if ! mkdir -p -- "$state_root" || ! mkdir -m 0700 -- "$src"; then
        printf 1>&2 -- 'Error: cannot create state directory %q\n' "$src"
        return 1
      fi
    fi

    __sandbox_state_args+=(--bind "$src" "$target")
  done
}

declare -fr __sandbox_add_state_dir_args

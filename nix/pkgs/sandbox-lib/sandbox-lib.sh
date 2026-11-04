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

# Runs from an EXIT trap, so it must never fail: under `set -e` a failing trap
# replaces the script's exit status. It is a subshell, so `set +e` stays local.
# shellcheck disable=SC2329
__sandbox_cleanup() (
  set +e

  if [[ -n ${__sandbox_s6_scan_dir:-} ]]; then
    # `svscanctl -q` is liable to lose logs, but we're about to delete all logs
    # anyway.
    s6-svscanctl -q "$__sandbox_s6_scan_dir"
  fi

  if [[ -n ${SANDBOX_S6_SVSCAN[1]:-} ]]; then
    local __sandbox_s6_svscan_stdin="${SANDBOX_S6_SVSCAN[1]}"
    exec {__sandbox_s6_svscan_stdin}<&- || :
  fi

  if [[ -n ${SANDBOX_S6_SVSCAN[0]:-} ]]; then
    local __sandbox_s6_svscan_stdout="${SANDBOX_S6_SVSCAN[0]}"
    exec {__sandbox_s6_svscan_stdout}>&- || :
  fi

  if [[ -n ${SANDBOX_S6_SVSCAN_PID:-} ]]; then
    kill "${SANDBOX_S6_SVSCAN_PID?}" &>/dev/null || :
  fi

  if [[ -n ${__sandbox_runtime_dir:-} ]]; then
    # `svscanctl -q` doesn't wait for the s6-supervise processes, which may
    # still be writing under the runtime directory; retry briefly.
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      rm -f -r --one-file-system --preserve-root "$__sandbox_runtime_dir" 2>/dev/null && break
      sleep 0.1
    done

    if [[ -e $__sandbox_runtime_dir ]]; then
      printf 1>&2 -- 'warning: could not remove %q\n' "$__sandbox_runtime_dir"
    fi
  fi

  :
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

  # Use the per-user runtime directory only if it already exists and belongs
  # to us; the login manager creates it, we don't. Otherwise use TMPDIR. Either
  # way `mktemp -d` atomically creates a fresh mode-0700 directory, so a shared
  # parent such as /tmp is safe.
  local parent="${XDG_RUNTIME_DIR:-"/run/user/${__sandbox_uid}"}"
  if ! [[ -d $parent && -O $parent && ! -L $parent ]]; then
    parent="${TMPDIR:-/tmp}"
  fi

  declare -g __sandbox_runtime_dir
  __sandbox_runtime_dir="$(mktemp -d "${parent}/bubbllmwrap-sandbox.$$.XXXXXXXXXX")" || return
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
  __sandbox_init_s6_scan_dir || return
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
# A metadata path reached through a symlink that lives inside the project is
# refused outright: the sandbox could replace the symlink (bind mounts cannot
# cover a symlink itself) and so redirect host-side VCS commands to a
# repository it controls.
#
# Arguments: the resolved project directory (scan root and bind-source prefix)
# and the project's mount point inside the sandbox (bind-destination prefix).
#
# Populates the global `__sandbox_deny_args` array with `--ro-bind` arguments.
# Returns non-zero, after printing why, if the sandbox must not start.
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
    __sandbox_lock_vcs_path "$real_project_dir" "$project_mount" "$found" 1 || return
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

  local link
  if link="$(__sandbox_project_symlink_in_path "$real_project_dir" "$path")"; then
    printf 1>&2 -- 'Error: VCS metadata %q is reached through the symlink %q inside the project.\n' "$path" "$link"
    printf 1>&2 -- 'The sandbox could replace that symlink and redirect host-side VCS commands, so refusing to start.\n'
    printf 1>&2 -- 'Replace the symlink with what it points to, or disable filesystem.denyVcsMetadata.\n'
    return 1
  fi

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
    __sandbox_lock_vcs_path "$real_project_dir" "$project_mount" "$gitdir" 0 || return
  fi
}

declare -fr __sandbox_lock_vcs_path

# Resolve an absolute path one component at a time, following symlinks the way
# the kernel does, and print the first symlink found that lives inside the
# resolved project directory (the sandbox can replace such a symlink). Returns
# 1 if there is none. Symlinks outside the project, which the sandbox cannot
# modify, are followed.
__sandbox_project_symlink_in_path() {
  local real_project_dir="${1?}" path="${2?}"

  local cur=/ comp next target links=0
  local -a todo=() more=()
  IFS=/ read -r -a todo <<<"$path"

  while ((${#todo[@]})); do
    comp="${todo[0]}"
    todo=("${todo[@]:1}")

    case "$comp" in
    '' | .) continue ;;
    ..)
      cur="${cur%/*}"
      cur="${cur:-/}"
      continue
      ;;
    esac

    next="${cur%/}/${comp}"
    if [[ -L $next ]]; then
      if [[ $cur == "$real_project_dir" || $cur == "$real_project_dir"/* ]]; then
        printf '%s\n' "$next"
        return 0
      fi

      # Same limit as the kernel's MAXSYMLINKS; also stops loops.
      ((++links <= 40)) || return 1
      target="$(readlink -- "$next")" || return 1
      [[ $target != /* ]] || cur=/
      IFS=/ read -r -a more <<<"$target"
      todo=("${more[@]}" "${todo[@]}")
      continue
    fi

    cur="$next"
  done

  return 1
}

declare -fr __sandbox_project_symlink_in_path

# Print a path from the module config with a leading `~/` (or a bare `~`)
# resolved against the given home directory; anything else is printed as is.
__sandbox_expand_home() {
  local home="${1?}" path="${2?}"

  # A literal `~` is what we're matching, so no tilde expansion.
  # shellcheck disable=SC2088
  case "$path" in
  '~') printf '%s\n' "$home" ;;
  '~/'*) printf '%s\n' "${home}/${path#'~/'}" ;;
  *) printf '%s\n' "$path" ;;
  esac
}

declare -fr __sandbox_expand_home

# Turn `filesystem.mounts` into bwrap arguments.
#
# Expects `__sandbox_mounts` (from the generated vars script) to hold
# type/source/target triples, already validated and ordered by the module; the
# source is empty for types that take only a target. Paths starting with `~/`
# are resolved against the given home directory, and nothing else is expanded.
#
# Populates the global `__sandbox_mount_args` array.
__sandbox_add_mount_args() {
  local home="${1?}"

  declare -ga __sandbox_mount_args
  __sandbox_mount_args=()

  [[ -v __sandbox_mounts ]] || return 0

  local i type src dest
  for ((i = 0; i + 2 < ${#__sandbox_mounts[@]}; i += 3)); do
    type="${__sandbox_mounts[i]}"
    src="${__sandbox_mounts[i + 1]}"
    dest="$(__sandbox_expand_home "$home" "${__sandbox_mounts[i + 2]}")"

    if [[ -n $src ]]; then
      src="$(__sandbox_expand_home "$home" "$src")"
      __sandbox_mount_args+=("--${type}" "$src" "$dest")
    else
      __sandbox_mount_args+=("--${type}" "$dest")
    fi
  done
}

declare -fr __sandbox_add_mount_args

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

    target="$(__sandbox_expand_home "$home" "$target")"
    if [[ $target != /* ]]; then
      printf 1>&2 -- 'Error: state directory target %q must be absolute or start with ~/\n' "$target"
      return 1
    fi

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

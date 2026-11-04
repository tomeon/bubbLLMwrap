#!/usr/bin/env bash

set -emuo pipefail

# shellcheck source=../sandbox-lib/sandbox-lib.sh
source "$SANDBOX_LIB"

__sandbox_setup

svc_dir="${__sandbox_s6_scan_dir}/glider"
printf >"${svc_dir}/notification-fd" -- '%d\n' 3
env_dir="${__sandbox_s6_scan_dir}/glider/env"

export SANDBOX_PROXY_HTTP_SOCKET_PATH="${__sandbox_runtime_dir}/http.sock"
export SANDBOX_PROXY_SOCKS5_SOCKET_PATH="${__sandbox_runtime_dir}/socks5.sock"

printf >"${env_dir}/SANDBOX_PROXY_HTTP_SOCKET_PATH" -- '%s' \
  "$SANDBOX_PROXY_HTTP_SOCKET_PATH"

printf >"${env_dir}/SANDBOX_PROXY_SOCKS5_SOCKET_PATH" -- '%s' \
  "$SANDBOX_PROXY_SOCKS5_SOCKET_PATH"

# Only running one service.
__sandbox_s6_svscan -C 1

__sandbox_s6_svwait glider -U

# XXX no `exec`!  Otherwise our `cleanup` function will not run.
"$@"

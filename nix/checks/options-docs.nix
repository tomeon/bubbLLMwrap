{
  runCommand,
  diffutils,
  docs,
  self,
}:
runCommand "bubbllmwrap-options-docs-check" {
  src = self;
} ''
  check_docs() {
    current="$1"
    shift

    target="$1"
    shift

    if ! [ -f "$current" ]; then
      printf 1>&2 -- 'missing "%s"; please generate documentation%s.\n' \
        "$current" "''${*:+" with \`$*\`"}"
      return 1
    elif ! ${diffutils}/bin/cmp "$current" "$target" 1>/dev/null 2>&1 ; then
      printf 1>&2 -- '"%s" and "%s" differ; please generate documentation%s.\n' \
        "$current" "$target" "''${*:+" with \`$*\`"}"
      return 1
    fi
  }

  check_docs "''${src}/docs/OPTIONS.md" ${docs} mkoptdocs || rc="$?"

  if [ "''${rc:-0}" -eq 0 ]; then
    touch "$out"
  else
    exit "$rc"
  fi
''

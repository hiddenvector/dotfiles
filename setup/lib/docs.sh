#!/usr/bin/env bash
# docs/USAGE.md is generated from docs/usage/*.md so the cheatsheet, the
# browsable reference and the agent skill cannot disagree.

hv::docs_order() { printf '%s\n' core swift web python security; }

hv::docs_render() {
  local m file
  printf '# Usage Guide\n\n'
  printf '<!-- Generated from docs/usage/*.md by hv. Edit those, not this. -->\n\n'
  for m in $(hv::docs_order); do
    file="$HV_ROOT/docs/usage/$m.md"
    [ -f "$file" ] || continue
    cat "$file"
    printf '\n'
  done
}

hv::docs_generate() {
  hv::docs_render > "$HV_ROOT/docs/USAGE.md"
}

hv::docs_current() {
  [ -f "$HV_ROOT/docs/USAGE.md" ] || return 1
  hv::docs_render | diff -q - "$HV_ROOT/docs/USAGE.md" >/dev/null 2>&1
}

# Print only the fragments for the modules installed on this machine.
# Returns 1 (printing nothing) if given a module name that names none of
# hv::docs_order -- silently exiting 0 would read as "nothing to show"
# rather than "no such module".
hv::docs_cheatsheet() {
  local want="${1:-}" m file known=0
  if [ -n "$want" ] && [ "$want" != "all" ]; then
    for m in $(hv::docs_order); do
      if [ "$m" = "$want" ]; then
        known=1
      fi
    done
    if [ "$known" -ne 1 ]; then
      return 1
    fi
  fi
  for m in $(hv::docs_order); do
    file="$HV_ROOT/docs/usage/$m.md"
    [ -f "$file" ] || continue
    if [ -n "$want" ] && [ "$want" != "all" ]; then
      [ "$want" = "$m" ] || continue
    elif [ "$want" != "all" ]; then
      hv::module_enabled "$m" || continue
    fi
    cat "$file"
    printf '\n'
  done
}

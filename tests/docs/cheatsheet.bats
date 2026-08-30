#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox
  source "$HV_ROOT/setup/lib/log.sh"
  source "$HV_ROOT/setup/lib/config.sh"
  hv::config_set HV_MODULES "core web"
  hv::config_load
}

@test "cheatsheet prints only installed modules" {
  run "$HV_ROOT/bin/hv" cheatsheet
  case "$output" in *ripgrep*) ;; *) return 1 ;; esac
  case "$output" in *xcbeautify*) return 1 ;; *) ;; esac
}

@test "cheatsheet --all prints every module" {
  run "$HV_ROOT/bin/hv" cheatsheet --all
  case "$output" in *xcbeautify*) ;; *) return 1 ;; esac
}

@test "cheatsheet accepts a module name" {
  run "$HV_ROOT/bin/hv" cheatsheet swift
  case "$output" in *xcbeautify*) ;; *) return 1 ;; esac
  case "$output" in *ripgrep*) return 1 ;; *) ;; esac
}

@test "cheatsheet rejects an unknown module name" {
  run "$HV_ROOT/bin/hv" cheatsheet bogus
  [ "$status" -ne 0 ]
  case "$output" in *bogus*) ;; *) return 1 ;; esac
}

@test "USAGE.md is current" {
  source "$HV_ROOT/setup/lib/docs.sh"
  run hv::docs_current
  [ "$status" -eq 0 ]
}

@test "every module with a Brewfile has a usage fragment" {
  for m in core swift web python security; do
    [ -f "$HV_ROOT/docs/usage/$m.md" ]
  done
}

@test "core usage documents the interactive helpers" {
  for c in ff fif gcof glogf; do
    grep -q "\`$c\`" "$HV_ROOT/docs/usage/core.md"
  done
}

@test "core usage documents the bin helpers" {
  grep -q "gprune" "$HV_ROOT/docs/usage/core.md"
  grep -q "gbd" "$HV_ROOT/docs/usage/core.md"
}

#!/usr/bin/env bats

load ../helper

setup() {
  hv_setup_sandbox

  # hv_deny_dangerous's git stub refuses network subcommands (clone, push,
  # fetch, pull, remote, submodule) with a logged REFUSED line, because an
  # earlier task's test reached real `sudo` and prompted for a password.
  # gbd ends with `git push origin --delete`, and gprune starts with
  # `git fetch --prune`; both are tolerated by `|| true` under the deny
  # stub, but that would still spam a REFUSED line into the shared stub log
  # on every run, and this suite asserts a suite-wide REFUSED count of 0.
  #
  # Replace the stub, for this file only, with one that always execs the
  # real git. Every "origin" used below points at a bare repo created under
  # $BATS_TEST_TMPDIR, so push/fetch here are genuinely local operations,
  # not a hole to the network — this exercises gbd's and gprune's remote
  # code paths for real instead of merely tolerating a refusal.
  cat > "$HV_STUB_DIR/git" <<GITALLOW
#!/usr/bin/env bash
exec "$HV_REAL_GIT" "\$@"
GITALLOW
  chmod +x "$HV_STUB_DIR/git"

  export REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$REPO"
  cd "$REPO" || exit 1
  git init -q -b main
  git config user.email t@t.t
  git config user.name Test
  git commit -q --allow-empty -m init
}

@test "gbd refuses to delete main" {
  run "$HV_ROOT/bin/gbd" main
  [ "$status" -eq 3 ]
  [[ "$stderr$output" == *"protected"* ]]
}

@test "gbd refuses to delete master" {
  run "$HV_ROOT/bin/gbd" master
  [ "$status" -eq 3 ]
}

@test "gbd refuses to delete develop" {
  run "$HV_ROOT/bin/gbd" develop
  [ "$status" -eq 3 ]
}

@test "gbd requires a branch name" {
  run "$HV_ROOT/bin/gbd"
  [ "$status" -eq 2 ]
  [[ "$stderr$output" == *"usage"* ]]
}

@test "gbd deletes a merged branch locally and on the remote" {
  # A genuinely local bare repo stands in for "origin" so gbd's final
  # `git push origin --delete` line runs for real instead of being tolerated.
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git branch feature
  git push -q origin feature

  run "$HV_ROOT/bin/gbd" feature
  [ "$status" -eq 0 ]

  run git branch --list feature
  [ "$output" = "" ]

  run git ls-remote --heads origin feature
  [ "$output" = "" ]
}

@test "gbd -D force-deletes an unmerged branch" {
  git switch -q -c feature
  git commit -q --allow-empty -m work
  git switch -q main
  run "$HV_ROOT/bin/gbd" -D feature
  [ "$status" -eq 0 ]
}

@test "gprune runs without a remote and leaves main alone" {
  run "$HV_ROOT/bin/gprune"
  run git branch --list main
  [[ "$output" == *"main"* ]]
}

@test "gprune skips the current and mainline branches but prunes a gone one" {
  # Real "gone" upstreams, against a genuinely local bare repo, so gprune's
  # own `git fetch --prune` is what discovers them - not a fixture.
  git init -q --bare "$BATS_TEST_TMPDIR/remote.git"
  git remote add origin "$BATS_TEST_TMPDIR/remote.git"
  git push -q origin main

  # Mainline-named branch with a gone upstream: protected by name.
  git branch develop
  git push -q -u origin develop
  git push -q origin --delete develop

  # Non-mainline branch with a gone upstream, currently checked out:
  # protected because it's the branch gprune is running from.
  git switch -q -c feature-active
  git push -q -u origin feature-active
  git push -q origin --delete feature-active

  # Non-mainline, not current, gone upstream: the one gprune should delete.
  git branch stale
  git push -q -u origin stale
  git push -q origin --delete stale

  run "$HV_ROOT/bin/gprune"
  [ "$status" -eq 0 ]

  run git branch --list develop
  [[ "$output" == *"develop"* ]]

  run git branch --list feature-active
  [[ "$output" == *"feature-active"* ]]

  run git branch --list main
  [[ "$output" == *"main"* ]]

  run git branch --list stale
  [ "$output" = "" ]
}

@test "helpers need no TTY" {
  run bash -c "'$HV_ROOT/bin/gbd' main < /dev/null"
  [ "$status" -eq 3 ]
}

@test "interactive helpers are not in bin" {
  for f in ff ffa fif gcof glogf j; do
    [ ! -e "$HV_ROOT/bin/$f" ]
  done
}

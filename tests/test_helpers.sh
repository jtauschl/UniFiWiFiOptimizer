#!/usr/bin/env bash
# Shared pass/fail bookkeeping and assertion helpers for the tests/*.sh
# fixture suites. Sourced after unifiwifioptimizer itself, so functions here
# must not collide with names in the main script.

pass_count=0
fail_count=0

assert_eq() {
  local expected=$1 actual=$2 msg=$3
  if [[ "$expected" == "$actual" ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$msg" "$expected" "$actual" >&2
  fi
}

assert_contains() {
  local haystack=$1 needle=$2 msg=$3
  if [[ "$haystack" == *"$needle"* ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n  expected to contain: %s\n  actual: %s\n' "$msg" "$needle" "$haystack" >&2
  fi
}

assert_success() {
  local fn=$1 arg=$2 msg=$3
  if "$fn" "$arg"; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n  expected %s %q to succeed\n' "$msg" "$fn" "$arg" >&2
  fi
}

assert_failure() {
  local fn=$1 arg=$2 msg=$3
  if ! "$fn" "$arg"; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n  expected %s %q to fail\n' "$msg" "$fn" "$arg" >&2
  fi
}

assert_empty() {
  local actual=$1 msg=$2
  if [[ -z "$actual" ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n  expected empty output, got: %s\n' "$msg" "$actual" >&2
  fi
}

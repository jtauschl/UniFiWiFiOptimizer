#!/usr/bin/env bash
# Fixture tests for TX power recommendation logic (ALGORITHM.md §4/§5):
# calculate_tx_recommendation() (shared by analyze_band() and
# prepare_site_tx_checks()) and the "fix TX power first" hint surfaced by
# print_general_check_roaming_assistant(). Sources unifiwifioptimizer
# directly -- the source guard at the end of the file means main() does not
# run, so scan-loop/API side effects never happen here.
#
# shellcheck disable=SC2034,SC2154
# SC2034: several globals set here (TX_LO, TX_HI, HYSTERESIS_*, ...) are
#   read by the sourced functions in unifiwifioptimizer, not referenced
#   directly in this file.
# SC2154: _result/_tx_uncapped/_tx_zero_sightings are set by
#   calculate_tx_recommendation() in the sourced script.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${TEST_DIR}/../unifiwifioptimizer"

# shellcheck source=/dev/null
source "$TOOL"
# shellcheck source=./test_helpers.sh
source "${TEST_DIR}/test_helpers.sh"

assert_not_contains() {
  local haystack=$1 needle=$2 msg=$3
  if [[ "$haystack" != *"$needle"* ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n  expected NOT to contain: %s\n  actual: %s\n' "$msg" "$needle" "$haystack" >&2
  fi
}

setup_fixture() {
  tmpdir=$(mktemp -d)
  ENV_FILE="${tmpdir}/controller.env"
  SITES_FILE="${tmpdir}/sites.tsv"
  WLANS_FILE="${tmpdir}/wlans.tsv"
  NEIGHBORS_FILE="${tmpdir}/neighbors.tsv"
  PROFILES_TSV="${tmpdir}/profiles.tsv"
  APS_FILE="${tmpdir}/aps.tsv"
  CONTROLLER_SITES_FILE="${tmpdir}/controller-sites.txt"
  TX_LO=-73
  TX_HI=$((TX_LO + CORRIDOR_WIDTH))
  ROAM_OFFSET_DB=0
  ROAM_MARGIN_DB=5
  ROAM_FLOOR=-78
  ROAM_CEILING=-67
  : >"$WLANS_FILE"
  : >"$NEIGHBORS_FILE"
  : >"$APS_FILE"
}

teardown_fixture() {
  [[ -n "${tmpdir:-}" && -d "$tmpdir" ]] && rm -rf "$tmpdir"
}

fixture_ap() {
  local site=$1 ap=$2 mac=$3
  printf '%s\t%s\t%s\t10.0.0.1\tTestModel\n' "$site" "$ap" "$mac" >>"$APS_FILE"
}

fixture_neighbors() {
  local site=$1 ap=$2 peers=$3
  printf '%s\t%s\t%s\n' "$site" "$ap" "$peers" >>"$NEIGHBORS_FILE"
}

fixture_peer_5g_sighting() {
  local site=$1 peer=$2 mac5g=$3 rssi=$4
  local prefix
  prefix=$(ap_scan_prefix "$site" "$peer")
  printf '%s\t%s\n' "$mac5g" "$rssi" >>"$(scan_rssi_cache_path "${prefix}.5g")"
}

fixture_peer_2g_sighting() {
  local site=$1 peer=$2 mac24=$3 rssi=$4
  local prefix
  prefix=$(ap_scan_prefix "$site" "$peer")
  printf '%s\t%s\n' "$mac24" "$rssi" >>"$(scan_rssi_cache_path "${prefix}.2g")"
}

# Writes a site_radio_tsv_path() row matching get_radio_info()'s expected
# field order: ch24|ht24|tx24|min_tx24|max_tx24|txmode24|min_rssi24|
# min_rssi_en24|ch5|ht5|tx5|min_tx5|max_tx5|txmode5|min_rssi5|min_rssi_en5|
# roam_enabled|roam_rssi|ib24|ib5|dfs5 (21 fields).
fixture_radio() {
  local site=$1 ap=$2 tx24=$3 min_tx24=$4 max_tx24=$5 tx5=$6 min_tx5=$7 max_tx5=$8
  printf '%s\t6|20|%s|%s|%s|custom|-75|false|100|80|%s|%s|%s|custom|-79|false|false||false|false|false\n' \
    "$ap" "$tx24" "$min_tx24" "$max_tx24" "$tx5" "$min_tx5" "$max_tx5" \
    >>"$(site_radio_tsv_path "$site")"
}

# ==============================================================================
# Test: calculate_tx_recommendation() -- zero sightings with a configured
# peer jumps straight to max_tx (deliberately aggressive, see ALGORITHM.md).
# ==============================================================================
test_zero_sightings_with_peer_goes_to_max() {
  TX_LO=-76
  TX_HI=-70
  calculate_tx_recommendation 6 6 23 0 0 1 false
  assert_eq "23" "$_result" "zero sightings with a configured peer must recommend max_tx"
  assert_eq "23" "$_tx_uncapped" "zero sightings: _tx_uncapped must equal max_tx (no shift was computed)"
  assert_eq "true" "$_tx_zero_sightings" "zero sightings flag must be true when peer_count > 0"
}

# ==============================================================================
# Test: calculate_tx_recommendation() -- zero sightings with NO configured
# peer at all leaves current_tx untouched (nothing to reach).
# ==============================================================================
test_zero_sightings_no_peer_unchanged() {
  TX_LO=-76
  TX_HI=-70
  calculate_tx_recommendation 6 6 23 0 0 0 false
  assert_eq "6" "$_result" "zero configured peers: current_tx must be unchanged"
  assert_eq "6" "$_tx_uncapped" "zero configured peers: _tx_uncapped must equal current_tx"
  assert_eq "false" "$_tx_zero_sightings" "zero-sightings flag must be false when peer_count == 0 (nothing to flag)"
}

# ==============================================================================
# Test: calculate_tx_recommendation() -- normal in-corridor case is
# unaffected by the extraction (regression guard against the original
# inline analyze_band() logic).
# ==============================================================================
test_in_corridor_unchanged() {
  TX_LO=-76
  TX_HI=-70
  # avg = -73, within [-76, -70] corridor -> no change recommended.
  calculate_tx_recommendation 19 6 23 -146 2 2 false
  assert_eq "19" "$_result" "average RSSI within corridor must not change recommended TX"
}

# ==============================================================================
# Test: calculate_tx_recommendation() -- partial-missing-peer nudge (count_nbr
# > 0, but not all configured peers sighted) still applies the pre-existing
# +1 dBm nudge, unaffected by the new zero-sightings branch.
# ==============================================================================
test_partial_missing_peer_nudge_preserved() {
  TX_LO=-76
  TX_HI=-70
  # Single sighted neighbor exactly at corridor center -> no shift from the
  # corridor calc alone, but has_missing_peer_partial=true nudges +1 dBm.
  calculate_tx_recommendation 6 6 23 -73 1 2 true
  assert_eq "7" "$_result" "partial-missing-peer case must still apply the +1 dBm nudge"
  assert_eq "false" "$_tx_zero_sightings" "partial-missing-peer case (count_nbr>0) must not set the zero-sightings flag"
}

# ==============================================================================
# Test: print_rec_tx_zero_sightings() -- when TX is genuinely raised (current
# != recommended), the change must be flagged (regression guard).
# ==============================================================================
test_print_rec_tx_zero_sightings_flags_real_change() {
  has_changes=false
  local output_file
  output_file=$(mktemp)
  print_rec_tx_zero_sightings 23 custom 6 >"$output_file"
  local output
  output=$(cat "$output_file")
  rm -f "$output_file"
  assert_eq "true" "$has_changes" "raising TX to max from a lower current value must flag a change"
  assert_contains "$output" "raised to radio maximum" "message must describe the raise when a real change occurs"
}

# ==============================================================================
# Test: print_rec_tx_zero_sightings() -- an AP already at radio maximum with
# zero sightings must NOT be flagged as a change on every run (bug found in
# self-review: calculate_tx_recommendation() correctly returns current_tx
# unchanged when current_tx == max_tx, but the original print function always
# called flag_change() and printed "raised to radio maximum" regardless).
# ==============================================================================
test_print_rec_tx_zero_sightings_no_flag_when_already_at_max() {
  has_changes=false
  local output_file
  output_file=$(mktemp)
  print_rec_tx_zero_sightings 23 custom 23 >"$output_file"
  local output
  output=$(cat "$output_file")
  rm -f "$output_file"
  assert_eq "false" "$has_changes" "an AP already at max TX with zero sightings must not be flagged as a pending change every run"
  assert_contains "$output" "already at radio maximum" "message must reflect that TX is already at the ceiling, not imply an action just happened"
  assert_not_contains "$output" "raised to radio maximum" "must not claim TX was raised when it was already at max"
}

# ==============================================================================
# Test: prepare_site_tx_checks() -- an AP with zero sightings against a
# configured peer counts as a pending TX change.
# ==============================================================================
test_prepare_site_tx_checks_counts_zero_sightings() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"
  # AP1 has zero 5g sightings of AP2 -- no fixture_peer_5g_sighting for AP2
  # seeing AP1's mac. AP2 sees AP1 fine and is in-corridor (no pending change).
  # 2.4g is fixtured in-corridor for both APs so only the 5g band is exercised.
  fixture_radio "$site" AP1 11 6 23 6 6 23
  fixture_radio "$site" AP2 11 6 23 19 6 23
  fixture_peer_2g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 1)" -73
  fixture_peer_2g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 1)" -73
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -73

  prepare_site_tx_checks "$site"

  local pending
  pending=$(cat "$(tx_pending_count_path "$site")")
  assert_eq "1" "$pending" "exactly one AP/band (AP1's 5g, zero sightings) should count as pending"

  teardown_fixture
}

# ==============================================================================
# Test: prepare_site_tx_checks() -- no pending changes when every AP/band is
# already at its in-corridor recommended value.
# ==============================================================================
test_prepare_site_tx_checks_zero_when_all_ok() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"
  fixture_radio "$site" AP1 19 6 23 19 6 23
  fixture_radio "$site" AP2 19 6 23 19 6 23
  fixture_peer_2g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 1)" -73
  fixture_peer_2g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 1)" -73
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -73
  fixture_peer_5g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -73

  prepare_site_tx_checks "$site"

  local pending
  pending=$(cat "$(tx_pending_count_path "$site")")
  assert_eq "0" "$pending" "no pending TX changes expected when every band is already in-corridor"

  teardown_fixture
}

# ==============================================================================
# Integration test: the "fix TX first" hint appears alongside an incomplete
# Roaming Assistant verdict when tx_pending_count > 0.
# ==============================================================================
test_tx_pending_note_appears_when_incomplete_and_pending() {
  setup_fixture
  local site=default

  printf '5\n' >"$(tx_pending_count_path "$site")"

  : >"$(roaming_wlan_tsv_path "$site")"
  printf '%s%s%sincomplete%s%s\n' "Corp" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "AP1: neighbor AP2 not sighted" >>"$(roaming_wlan_tsv_path "$site")"
  : >"$(roaming_detail_tsv_path "$site")"

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "true" "-67" "5g" "true")

  assert_contains "$output" "Incomplete" "sanity: the incomplete verdict itself must still be printed"
  assert_contains "$output" "pending TX power recommendation" "fix-TX-first hint must appear when tx_pending_count > 0 and the verdict is incomplete"

  teardown_fixture
}

# ==============================================================================
# Counter-test: the hint must NOT appear when there is no pending TX change,
# even though the verdict is still incomplete.
# ==============================================================================
test_tx_pending_note_absent_when_no_pending() {
  setup_fixture
  local site=default

  printf '0\n' >"$(tx_pending_count_path "$site")"

  : >"$(roaming_wlan_tsv_path "$site")"
  printf '%s%s%sincomplete%s%s\n' "Corp" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "AP1: neighbor AP2 not sighted" >>"$(roaming_wlan_tsv_path "$site")"
  : >"$(roaming_detail_tsv_path "$site")"

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "true" "-67" "5g" "true")

  assert_contains "$output" "Incomplete" "sanity: the incomplete verdict itself must still be printed"
  assert_not_contains "$output" "pending TX power recommendation" "fix-TX-first hint must NOT appear when tx_pending_count is 0"

  teardown_fixture
}

# ==============================================================================
# Counter-test: the hint must NOT appear on a normal ✓/✗ verdict (only on
# incomplete/not_evaluable), even with pending TX changes present.
# ==============================================================================
test_tx_pending_note_absent_on_normal_verdict() {
  setup_fixture
  local site=default

  printf '3\n' >"$(tx_pending_count_path "$site")"

  : >"$(roaming_wlan_tsv_path "$site")"
  printf '%s%s%s%s%s%s\n' "Corp" "$WLAN_FIELD_SEP" "-73" "$WLAN_FIELD_SEP" "ok" "$WLAN_FIELD_SEP" >>"$(roaming_wlan_tsv_path "$site")"
  : >"$(roaming_detail_tsv_path "$site")"

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "true" "-73" "5g" "true")

  assert_not_contains "$output" "pending TX power recommendation" "fix-TX-first hint must not appear on a normal ok verdict, even with pending TX changes elsewhere"

  teardown_fixture
}

# ==============================================================================
# Test: print_general_check_roaming_assistant() -- a profile that expects
# Roaming Assistant disabled, and the WLAN matches (na_enabled=false), must
# report a clean ✓ without touching roaming_wlan.tsv or flagging a change.
# ==============================================================================
test_expected_disabled_and_actually_disabled_is_ok() {
  setup_fixture
  local site=default
  has_changes=false

  : >"$(roaming_wlan_tsv_path "$site")"
  printf '%s%s-73%sok%s\n' "Corp" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" >>"$(roaming_wlan_tsv_path "$site")"

  # has_changes must be observed outside any $(...) subshell -- see the note
  # in test_expected_disabled_but_actually_enabled_is_flagged below.
  local output_file
  output_file=$(mktemp)
  print_general_check_roaming_assistant "$site" "Corp" "false" "" "5g" "false" >"$output_file"
  local output
  output=$(cat "$output_file")
  rm -f "$output_file"

  assert_contains "$output" "Disabled" "verdict must state the disabled state"
  assert_eq "false" "$has_changes" "profile expecting disabled, WLAN actually disabled, must not flag a change"

  teardown_fixture
}

# ==============================================================================
# Test: print_general_check_roaming_assistant() -- a profile that expects
# Roaming Assistant disabled, but the WLAN has it enabled anyway, must be
# flagged as a deviation (✗), consistent with every other profile check.
# ==============================================================================
test_expected_disabled_but_actually_enabled_is_flagged() {
  setup_fixture
  local site=default
  has_changes=false

  : >"$(roaming_wlan_tsv_path "$site")"
  printf '%s%s-70%sok%s\n' "Corp" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" >>"$(roaming_wlan_tsv_path "$site")"

  # has_changes is set via flag_change() -- must not run inside a $(...)
  # subshell (its exit would lose the assignment), so output is captured via
  # a temp file instead, same pattern as the print_rec_tx_zero_sightings
  # tests above.
  local output_file
  output_file=$(mktemp)
  print_general_check_roaming_assistant "$site" "Corp" "true" "-70" "5g" "false" >"$output_file"
  local output
  output=$(cat "$output_file")
  rm -f "$output_file"

  assert_contains "$output" "expects disabled" "verdict must explain that the profile expects Roaming Assistant disabled"
  assert_eq "true" "$has_changes" "profile expecting disabled, WLAN actually enabled, must flag a change"

  teardown_fixture
}

# ==============================================================================
# Test: the "expected disabled" branch ignores the RF-corridor aggregation
# result entirely -- even when roaming_wlan.tsv reports "incomplete" (which
# would normally produce a "? Incomplete: ..." verdict for expected=true),
# expected=false must still resolve to a plain Disabled/Enabled verdict based
# only on na_enabled, since the aggregated RSSI target is irrelevant when the
# profile says Roaming Assistant should be off.
# ==============================================================================
test_expected_disabled_ignores_incomplete_aggregation() {
  setup_fixture
  local site=default

  : >"$(roaming_wlan_tsv_path "$site")"
  printf '%s%s%sincomplete%s%s\n' "Corp" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "$WLAN_FIELD_SEP" "AP1: neighbor AP2 not sighted" >>"$(roaming_wlan_tsv_path "$site")"

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "false" "" "5g" "false")

  assert_contains "$output" "Disabled" "expected=false must resolve to a plain disabled verdict even when the aggregation is incomplete"
  assert_not_contains "$output" "Incomplete" "expected=false must not surface the RF-corridor incomplete verdict at all"

  teardown_fixture
}

# ==============================================================================
# Counter-test: both N/A short-circuits (5 GHz not broadcast; older API
# without roaming_assistant_na_*) must fire before the expected_roaming_assistant
# branch is even reached -- verified with expected=false, where the N/A text
# must still appear (not the "Disabled (per profile)" text).
# ==============================================================================
test_na_band_not_broadcast_ignores_expected_false() {
  setup_fixture
  local site=default

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "true" "-67" "2g" "false")

  assert_contains "$output" "N/A (5 GHz not broadcast)" "band N/A must fire regardless of expected_roaming_assistant"
  assert_not_contains "$output" "Disabled (per profile)" "band N/A must win over the expected=false short-circuit"

  teardown_fixture
}

test_na_older_api_ignores_expected_false() {
  setup_fixture
  local site=default
  : >"$(roaming_wlan_tsv_path "$site")"

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "true" "-67" "5g" "false")

  assert_contains "$output" "N/A (older API" "older-API N/A must fire regardless of expected_roaming_assistant"
  assert_not_contains "$output" "Disabled (per profile)" "older-API N/A must win over the expected=false short-circuit"

  teardown_fixture
}

# ==============================================================================
# Counter-test: same as above, but with expected=true, confirming the N/A
# short-circuits are unconditional (not merely "false OR true both happen to
# produce N/A by coincidence" -- both explicit values are exercised).
# ==============================================================================
test_na_band_not_broadcast_ignores_expected_true() {
  setup_fixture
  local site=default

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "true" "-67" "2g" "true")

  assert_contains "$output" "N/A (5 GHz not broadcast)" "band N/A must fire regardless of expected_roaming_assistant"

  teardown_fixture
}

test_na_older_api_ignores_expected_true() {
  setup_fixture
  local site=default
  : >"$(roaming_wlan_tsv_path "$site")"

  local output
  output=$(print_general_check_roaming_assistant "$site" "Corp" "true" "-67" "5g" "true")

  assert_contains "$output" "N/A (older API" "older-API N/A must fire regardless of expected_roaming_assistant"

  teardown_fixture
}

# ==============================================================================
# Runner
# ==============================================================================
test_zero_sightings_with_peer_goes_to_max
test_zero_sightings_no_peer_unchanged
test_in_corridor_unchanged
test_partial_missing_peer_nudge_preserved
test_print_rec_tx_zero_sightings_flags_real_change
test_print_rec_tx_zero_sightings_no_flag_when_already_at_max
test_prepare_site_tx_checks_counts_zero_sightings
test_prepare_site_tx_checks_zero_when_all_ok
test_tx_pending_note_appears_when_incomplete_and_pending
test_tx_pending_note_absent_when_no_pending
test_tx_pending_note_absent_on_normal_verdict
test_expected_disabled_and_actually_disabled_is_ok
test_expected_disabled_but_actually_enabled_is_flagged
test_expected_disabled_ignores_incomplete_aggregation
test_na_band_not_broadcast_ignores_expected_false
test_na_older_api_ignores_expected_false
test_na_band_not_broadcast_ignores_expected_true
test_na_older_api_ignores_expected_true

printf 'tx_test.sh: %d passed, %d failed\n' "$pass_count" "$fail_count"
((fail_count == 0))

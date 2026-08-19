#!/usr/bin/env bash
# Fixture tests for the Roaming Assistant SSID-level aggregation
# (ALGORITHM.md §7). Sources unifiwifioptimizer directly -- the source guard
# at the end of the file means main() does not run, so scan-loop/API side
# effects never happen here. Each test builds its own tmpdir with the TSV
# fixtures the aggregation functions read, then calls them directly.
#
# shellcheck disable=SC2034,SC2154
# SC2034: several globals set here (ENV_FILE, SITES_FILE, TX_HI,
#   ROAM_OFFSET_DB, ...) are read by the sourced functions in
#   unifiwifioptimizer, not referenced directly in this file.
# SC2154: _result/_roam_warn/_roam_raw_cap are set by
#   calculate_roaming_recommendation() in the sourced script.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${TEST_DIR}/../unifiwifioptimizer"

# shellcheck source=/dev/null
source "$TOOL"
# shellcheck source=./test_helpers.sh
source "${TEST_DIR}/test_helpers.sh"

# Sets up a fresh tmpdir with the global path variables main() would
# normally set, plus a fixed site-aware TX_LO (Residential, n=2.8, matching
# ALGORITHM.md's documented -73 dBm).
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

# Writes one AP row into APS_FILE (site\tap\tmac\tip\tmodel).
fixture_ap() {
  local site=$1 ap=$2 mac=$3
  printf '%s\t%s\t%s\t10.0.0.1\tTestModel\n' "$site" "$ap" "$mac" >>"$APS_FILE"
}

fixture_neighbors() {
  local site=$1 ap=$2 peers=$3
  printf '%s\t%s\t%s\n' "$site" "$ap" "$peers" >>"$NEIGHBORS_FILE"
}

# Writes a WLAN -> profile mapping row into WLANS_FILE (config.yaml wlans:).
fixture_wlan_mapping() {
  local site=$1 wlan=$2 profile=${3:-Standard}
  printf '%s\t%s\t%s\n' "$site" "$wlan" "$profile" >>"$WLANS_FILE"
}

# Writes an apgroups.tsv row (group_id <SEP> mac1|mac2|...).
fixture_apgroup() {
  local site=$1 group_id=$2 macs=$3
  printf '%s%s%s\n' "$group_id" "$WLAN_FIELD_SEP" "$macs" >>"$(site_apgroups_tsv_path "$site")"
}

# Writes a wlanconf row into site_wlans_tsv_path, matching the field order
# fetch_site_wlan_info() writes (name, enabled, bss_transition,
# fast_roaming, minrate_mode, minrate24_en, minrate24, minrate5_en,
# minrate5, bc_filter, mcast_enhance, proxy_arp, wlan_band, wlan_bands,
# mlo, security, wpa_mode, wpa3_support, wpa3_transition, pmf, hide_ssid,
# l2_isolation, sae_anti_clogging, sae_sync, uapsd, dtim_mode, dtim24,
# dtim5, dtim6, group_rekey, ap_name_in_beacon, roaming_assistant_na_enabled,
# roaming_assistant_na_rssi, ap_group_mode, ap_group_ids).
fixture_wlanconf() {
  local site=$1 wlan=$2 wlan_bands=$3 na_enabled=$4 na_rssi=$5 group_mode=$6 group_ids=$7
  local sep="$WLAN_FIELD_SEP"
  {
    printf '%s' "$wlan"
    printf '%s' "$sep"
    printf 'true' # enabled
    printf '%s' "$sep"
    printf 'true' # bss_transition
    printf '%s' "$sep"
    printf 'false' # fast_roaming
    printf '%s' "$sep"
    printf 'auto' # minrate_mode
    printf '%s' "$sep"
    printf 'false' # minrate24_en
    printf '%s' "$sep"
    printf '0' # minrate24
    printf '%s' "$sep"
    printf 'false' # minrate5_en
    printf '%s' "$sep"
    printf '0' # minrate5
    printf '%s' "$sep"
    printf 'false' # bc_filter
    printf '%s' "$sep"
    printf 'false' # mcast_enhance
    printf '%s' "$sep"
    printf 'false' # proxy_arp
    printf '%s' "$sep"
    printf '' # wlan_band
    printf '%s' "$sep"
    printf '%s' "$wlan_bands" # wlan_bands
    printf '%s' "$sep"
    printf 'false' # mlo
    printf '%s' "$sep"
    printf 'wpapsk' # security
    printf '%s' "$sep"
    printf 'wpa2' # wpa_mode
    printf '%s' "$sep"
    printf 'false' # wpa3_support
    printf '%s' "$sep"
    printf 'false' # wpa3_transition
    printf '%s' "$sep"
    printf 'disabled' # pmf
    printf '%s' "$sep"
    printf 'false' # hide_ssid
    printf '%s' "$sep"
    printf 'false' # l2_isolation
    printf '%s' "$sep"
    printf '5' # sae_anti_clogging
    printf '%s' "$sep"
    printf '5' # sae_sync
    printf '%s' "$sep"
    printf 'false' # uapsd
    printf '%s' "$sep"
    printf 'default' # dtim_mode
    printf '%s' "$sep"
    printf '0' # dtim24
    printf '%s' "$sep"
    printf '0' # dtim5
    printf '%s' "$sep"
    printf '0' # dtim6
    printf '%s' "$sep"
    printf '0' # group_rekey
    printf '%s' "$sep"
    printf 'false' # ap_name_in_beacon
    printf '%s' "$sep"
    printf '%s' "$na_enabled" # roaming_assistant_na_enabled
    printf '%s' "$sep"
    printf '%s' "$na_rssi" # roaming_assistant_na_rssi
    printf '%s' "$sep"
    printf '%s' "$group_mode" # ap_group_mode
    printf '%s' "$sep"
    printf '%s' "$group_ids" # ap_group_ids
    printf '\n'
  } >>"$(site_wlans_tsv_path "$site")"
}

# Writes a 5 GHz RSSI cache entry for a peer's scan: mac<TAB>rssi.
fixture_peer_5g_sighting() {
  local site=$1 peer=$2 mac5g=$3 rssi=$4
  local prefix
  prefix=$(ap_scan_prefix "$site" "$peer")
  printf '%s\t%s\n' "$mac5g" "$rssi" >>"$(scan_rssi_cache_path "${prefix}.5g")"
}

# ==============================================================================
# Test: SSID_peers filtering -- an RF neighbor that does not broadcast the
# WLAN must not limit that WLAN's aggregated value.
# ==============================================================================
test_ssid_peer_filtering() {
  setup_fixture
  local site=default

  # AP1, AP2 broadcast "Guest"; AP3 is an RF neighbor of AP1 but does not.
  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_ap "$site" AP3 1c:0b:8b:ba:ce:dc
  fixture_neighbors "$site" AP1 "AP2,AP3"
  fixture_neighbors "$site" AP2 "AP1"
  fixture_neighbors "$site" AP3 "AP1"

  fixture_wlan_mapping "$site" Guest
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  fixture_wlanconf "$site" Guest "5g" "true" "-67" "all" "grp1"

  # AP3 is a much weaker sighting than AP2; if it were wrongly included,
  # the aggregated value would be pulled down by a non-broadcasting peer.
  fixture_peer_5g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -70
  fixture_peer_5g_sighting "$site" AP3 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -95
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -70

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Guest" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "${WLAN_FIELD_SEP}-73${WLAN_FIELD_SEP}ok${WLAN_FIELD_SEP}" "SSID-filtered aggregation should ignore AP3's weak (-95) sighting and use -73 (default, no cap)"

  teardown_fixture
}

# ==============================================================================
# Test: asymmetric RSSI measurement direction. The value used for AP A must
# come from *B's* scan cache (A's signal as seen at B), not the reverse.
# ==============================================================================
test_asymmetric_direction() {
  setup_fixture
  local site=default

  fixture_ap "$site" A f4:92:bf:aa:66:ac
  fixture_ap "$site" B f4:92:bf:aa:77:e0
  fixture_neighbors "$site" A "B"
  fixture_neighbors "$site" B "A"

  fixture_wlan_mapping "$site" Corp
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "grp1"

  # A's signal as seen at B: -70 dBm (in-corridor, no cap for A).
  fixture_peer_5g_sighting "$site" B "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -70
  # B's signal as seen at A: -82 dBm (deep below TX_LO, would cap B hard).
  fixture_peer_5g_sighting "$site" A "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -82

  prepare_site_roaming_checks "$site"

  # B is the limiting AP (capped by its weak sighting at A); A is not.
  local detail
  detail=$(cat "$(roaming_detail_tsv_path "$site")")
  assert_contains "$detail" $'B\tA\t-82' "limiting AP B's weakest peer must be A with -82 dBm (B's signal as seen at A), not A's own -70 sighting"

  teardown_fixture
}

# ==============================================================================
# Test: multiple limiting APs tied at the same minimum (floor clamp) are all
# reported, not just one.
# ==============================================================================
test_tie_handling_floor_clamp() {
  setup_fixture
  local site=default

  fixture_ap "$site" A f4:92:bf:aa:66:ac
  fixture_ap "$site" B f4:92:bf:aa:77:e0
  fixture_ap "$site" C 1c:0b:8b:ba:ce:dc
  fixture_neighbors "$site" A "C"
  fixture_neighbors "$site" B "C"
  fixture_neighbors "$site" C "A,B"

  fixture_wlan_mapping "$site" Corp
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0|1c:0b:8b:ba:ce:dc"
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "grp1"

  # Both A and B see extremely weak signals from C, driving both to ROAM_FLOOR.
  fixture_peer_5g_sighting "$site" C "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -95
  fixture_peer_5g_sighting "$site" C "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -95
  fixture_peer_5g_sighting "$site" A "$(mac_with_offset 1c:0b:8b:ba:ce:dc 2)" -70
  fixture_peer_5g_sighting "$site" B "$(mac_with_offset 1c:0b:8b:ba:ce:dc 2)" -70

  prepare_site_roaming_checks "$site"

  local limiting_aps
  limiting_aps=$(awk -F '\t' '$1 == "Corp" { print $2 }' "$(roaming_detail_tsv_path "$site")" | sort | tr '\n' ',')
  assert_eq "A,B," "$limiting_aps" "both A and B should be reported as limiting APs when tied at ROAM_FLOOR"

  teardown_fixture
}

# ==============================================================================
# Test: a broadcasting AP with no RF neighbor on this SSID makes the WLAN
# incomplete, not silently excluded from the min().
# ==============================================================================
test_incomplete_no_relevant_neighbor() {
  setup_fixture
  local site=default

  # AP1, AP2 are RF neighbors of each other and both broadcast Guest; AP3
  # also broadcasts Guest but its only configured RF neighbor is AP4, which
  # does not broadcast Guest -- so AP3's SSID_peers intersection is empty.
  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_ap "$site" AP3 1c:0b:8b:ba:ce:dc
  fixture_ap "$site" AP4 1c:0b:8b:be:b9:7c
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"
  fixture_neighbors "$site" AP3 "AP4"
  fixture_neighbors "$site" AP4 "AP3"

  fixture_wlan_mapping "$site" Guest
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0|1c:0b:8b:ba:ce:dc"
  fixture_wlanconf "$site" Guest "5g" "true" "-67" "all" "grp1"

  fixture_peer_5g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -70
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -70

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Guest" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "incomplete" "WLAN with a broadcasting AP lacking any SSID-relevant RF neighbor must be marked incomplete"
  assert_contains "$row" "AP3 has no configured RF neighbor broadcasting this SSID" "incomplete reason must name the affected AP"

  teardown_fixture
}

# ==============================================================================
# Test: a missing sighting for a relevant peer marks the WLAN incomplete
# rather than silently dropping that peer from the min().
# ==============================================================================
test_incomplete_missing_sighting() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" Guest
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  fixture_wlanconf "$site" Guest "5g" "true" "-67" "all" "grp1"

  # AP1's signal at AP2 is never sighted (no fixture_peer_5g_sighting for
  # AP2 seeing AP1); AP2's signal at AP1 is sighted fine.
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -70

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Guest" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "incomplete" "missing sighting for a relevant peer must mark the WLAN incomplete"
  assert_contains "$row" "AP1: neighbor AP2 not sighted" "incomplete reason must name the AP and the unsighted peer"

  teardown_fixture
}

# ==============================================================================
# Test: 2.4-GHz-only WLAN (actual config, regardless of profile) is N/A.
# ==============================================================================
test_na_2g_only_wlan() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" IoT
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  fixture_wlanconf "$site" IoT "2g" "" "" "all" "grp1"

  prepare_site_roaming_checks "$site"

  local wlan_tsv_content
  wlan_tsv_content=$(cat "$(roaming_wlan_tsv_path "$site")")
  assert_eq "" "$wlan_tsv_content" "a 2.4-GHz-only WLAN must not produce a roaming_wlan.tsv row (band applicability skips it before aggregation)"

  teardown_fixture
}

# ==============================================================================
# Test: single-AP WLAN has no handoff target -> N/A.
# ==============================================================================
test_na_single_ap_wlan() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_neighbors "$site" AP1 "AP1" # placeholder; single-AP WLANs have no real peers anyway

  fixture_wlan_mapping "$site" Solo
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac"
  fixture_wlanconf "$site" Solo "5g" "true" "-67" "specific" "grp1"

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Solo" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "na" "single-AP WLAN must be reported as na (no handoff target)"
  assert_contains "$row" "only one AP broadcasts this SSID" "reason must explain the single-AP case"

  teardown_fixture
}

# ==============================================================================
# Test: missing roaming_assistant_na_* fields (older API) skip aggregation
# for that WLAN entirely -- no row is written, and the presence flag stays
# absent, which is what the caller uses to decide the site-wide fallback to
# the old per-radio path.
# ==============================================================================
test_missing_new_field_no_row() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" Corp
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  # Both na_enabled and na_rssi empty, as an older controller would return.
  fixture_wlanconf "$site" Corp "5g" "" "" "all" "grp1"

  prepare_site_roaming_checks "$site"

  local wlan_tsv_content
  wlan_tsv_content=$(cat "$(roaming_wlan_tsv_path "$site")")
  assert_eq "" "$wlan_tsv_content" "a WLAN without roaming_assistant_na_* must not produce a row, enabling the site-wide fallback"
  if [[ -f "$(roaming_field_present_flag_path "$site")" ]]; then
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n' "presence flag must not exist when no WLAN exposes roaming_assistant_na_*" >&2
  else
    pass_count=$((pass_count + 1))
  fi

  teardown_fixture
}

# ==============================================================================
# Test (review fix, P1): a partially missing peer sighting must mark the AP
# incomplete even when at least one other SSID-relevant peer WAS sighted --
# a partial data set must not silently produce a value as if complete.
# ==============================================================================
test_incomplete_partial_missing_sighting() {
  setup_fixture
  local site=default

  # AP1 has two SSID-relevant peers: AP2 (sighted) and AP3 (not sighted).
  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_ap "$site" AP3 1c:0b:8b:ba:ce:dc
  fixture_neighbors "$site" AP1 "AP2,AP3"
  fixture_neighbors "$site" AP2 "AP1"
  fixture_neighbors "$site" AP3 "AP1"

  fixture_wlan_mapping "$site" Corp
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0|1c:0b:8b:ba:ce:dc"
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "grp1"

  # AP2 sees AP1 fine; AP3 never sights AP1 (no fixture_peer_5g_sighting
  # for AP3 seeing AP1's 5g mac). AP1 also needs to be seen by its peers.
  fixture_peer_5g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -70
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -70
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset 1c:0b:8b:ba:ce:dc 2)" -70

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Corp" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "incomplete" "AP1 with one sighted (AP2) and one missing (AP3) peer must still be incomplete, not ok"
  assert_contains "$row" "AP1: neighbor AP3 not sighted" "incomplete reason must name the specific missing peer even though AP2 was sighted"

  teardown_fixture
}

# ==============================================================================
# Test (review fix, P1): a broadcasting AP whose MAC is in the UniFi AP
# group but not configured under config.yaml's neighbors: must not silently
# disappear from the aggregation -- the WLAN must be incomplete instead.
# ==============================================================================
test_incomplete_unconfigured_broadcasting_ap() {
  setup_fixture
  local site=default

  # AP1, AP2 are configured (in APS_FILE via fixture_ap); the group also
  # references a third MAC that has no fixture_ap / no matching row in
  # devices.json -- fully unresolvable, simulating a device this site's
  # config.yaml doesn't know about at all.
  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" Corp
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0|de:ad:be:ef:00:01"
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "grp1"

  # A devices.json with no entry for de:ad:be:ef:00:01 either -- the
  # fallback name lookup also fails, so the MAC stays fully unresolved.
  printf '{"data":[]}' >"$(site_devices_json_path "$site")"

  fixture_peer_5g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -70
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -70

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Corp" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "incomplete" "a WLAN with an unconfigured/unresolvable broadcasting AP must be incomplete, not ok"
  assert_contains "$row" "de:ad:be:ef:00:01" "incomplete reason must name the unresolved MAC"

  teardown_fixture
}

# ==============================================================================
# Test (review fix, P2): a 2.4-GHz-only site must NOT trigger the legacy
# per-radio fallback, even though roaming_wlan.tsv ends up with zero rows
# (band not applicable) -- the presence flag must still be set because the
# API field itself was present.
# ==============================================================================
test_2g_only_site_no_fallback_trigger() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" IoT
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  # roaming_assistant_na_* IS present (current controller), but the WLAN is
  # 2.4-GHz-only, so no aggregation row is produced.
  fixture_wlanconf "$site" IoT "2g" "true" "-67" "all" "grp1"

  prepare_site_roaming_checks "$site"

  local wlan_tsv_content
  wlan_tsv_content=$(cat "$(roaming_wlan_tsv_path "$site")")
  assert_eq "" "$wlan_tsv_content" "a 2.4-GHz-only WLAN must still produce zero aggregation rows"

  if [[ -f "$(roaming_field_present_flag_path "$site")" ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n' "presence flag must be set (field was present on the 2.4-GHz-only WLAN) even though no row was produced -- this is what prevents a false fallback trigger" >&2
  fi

  teardown_fixture
}

# ==============================================================================
# Test: calculate_roaming_recommendation() regression -- the pure
# calculation function itself, independent of aggregation, still behaves as
# documented in ALGORITHM.md §7 (default, margin cap, floor clamp).
# ==============================================================================
test_calculate_roaming_recommendation_default() {
  TX_LO=-73
  ROAM_OFFSET_DB=0
  ROAM_MARGIN_DB=5
  ROAM_FLOOR=-78
  ROAM_CEILING=-67
  calculate_roaming_recommendation ""
  assert_eq "-73" "$_result" "no neighbor data: default threshold = TX_LO + ROAM_OFFSET_DB"
  assert_eq "" "$_roam_warn" "no neighbor data: no cap warning"
}

test_calculate_roaming_recommendation_margin_cap() {
  TX_LO=-73
  ROAM_OFFSET_DB=0
  ROAM_MARGIN_DB=5
  ROAM_FLOOR=-78
  ROAM_CEILING=-67
  calculate_roaming_recommendation "-76"
  assert_eq "-78" "$_result" "weakest neighbor -76 (below TX_LO -73) minus 5 dB margin = -81, clamped to ROAM_FLOOR -78"
  assert_eq "capped_by_floor" "$_roam_warn" "margin cap that goes below floor reports capped_by_floor"
}

# ==============================================================================
# Test (review fix round 2, P1): overlapping ap_group_ids referencing the
# same device_mac must not duplicate an AP in the aggregation -- a real
# single-AP WLAN whose ap_group_ids happens to list both "All APs" and a
# specific group containing only that same AP must still be reported as N/A
# (single AP), not as if two APs broadcast it.
# ==============================================================================
test_overlapping_groups_deduplicated() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac

  fixture_wlan_mapping "$site" Solo
  # Two groups, both containing only AP1's MAC -- simulates a WLAN whose
  # ap_group_ids references "All APs" and a specific single-AP group that
  # is a subset of it.
  fixture_apgroup "$site" grp_all "f4:92:bf:aa:66:ac"
  fixture_apgroup "$site" grp_specific "f4:92:bf:aa:66:ac"
  fixture_wlanconf "$site" Solo "5g" "true" "-67" "all" "grp_all|grp_specific"

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Solo" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "na" "overlapping groups resolving to the same single AP must still report na (no handoff target), not a spurious multi-AP aggregation"

  teardown_fixture
}

# ==============================================================================
# Test (review fix round 2, P1): an ap_group_id with no matching row in
# apgroups.tsv (unknown/unresolvable group) must not vanish silently --
# it forces the WLAN incomplete and is named in the reason.
# ==============================================================================
test_incomplete_unknown_group_id() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" Corp
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  # ap_group_ids references grp1 (resolvable) AND missing-group (not present
  # in apgroups.tsv at all).
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "grp1|missing-group"

  fixture_peer_5g_sighting "$site" AP2 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -70
  fixture_peer_5g_sighting "$site" AP1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -70

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Corp" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "incomplete" "an unresolvable ap_group_id must force the WLAN incomplete, not ok"
  assert_contains "$row" "missing-group" "incomplete reason must name the unresolved group id"

  teardown_fixture
}

# ==============================================================================
# Test (review fix round 2, P2): fetch_site_apgroups() must not abort the
# run when the v2 apgroups endpoint is unreachable (older controller) --
# under set -e, an unguarded fetch_api_json failure would kill the script
# before the site-wide fallback decision is ever made.
# ==============================================================================
test_fetch_site_apgroups_survives_unreachable_endpoint() {
  setup_fixture
  local site=default

  # Point at an address that refuses connections immediately, forcing
  # fetch_api_json's curl call to fail fast rather than time out.
  UNIFI_URL="http://127.0.0.1:1"
  UNIFI_API_KEY="test"

  local rc=0
  fetch_site_apgroups "$site" || rc=$?

  assert_eq "0" "$rc" "fetch_site_apgroups must return success (0) even when the endpoint is unreachable, so the caller can proceed to the fallback decision"

  if [[ -f "$(site_apgroups_tsv_path "$site")" ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n' "site_apgroups_tsv_path must exist (empty) after a failed fetch, not be left unset" >&2
  fi

  teardown_fixture
}

# ==============================================================================
# Test (review fix round 2): a real site-wide fallback scenario -- one WLAN
# has the new field, verifying the presence flag ends up set even when
# other WLANs on the same site are on the old model (mixed within one API
# response, e.g. mid-migration). This exercises the actual flag-setting
# path end-to-end rather than just checking its absence/presence directly.
# ==============================================================================
test_site_wide_fallback_flag_set_when_any_wlan_has_field() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  # Two WLANs mapped in config.yaml; only the second is fed through
  # fixture_wlanconf with the new field to simulate a mixed API response
  # (the first WLAN's row is deliberately absent from site_wlans_tsv_path,
  # as would happen if get_site_wlan_row() can't find it).
  fixture_wlan_mapping "$site" Guest
  fixture_wlan_mapping "$site" Corp
  fixture_apgroup "$site" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "grp1"

  prepare_site_roaming_checks "$site"

  if [[ -f "$(roaming_field_present_flag_path "$site")" ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n' "presence flag must be set site-wide as soon as ANY WLAN in the API response exposes the field, even if config.yaml maps other WLANs too" >&2
  fi

  teardown_fixture
}

# ==============================================================================
# Test (review fix round 2): TX_LO differs across sites -- the aggregated
# Roaming Assistant target for site B must use site B's own TX_LO, not a
# value left over from processing site A first. Regression guard for the
# control-flow requirement that prepare_site_roaming_checks() runs inside
# the per-site loop, after that site's TX_LO is computed.
# ==============================================================================
test_multi_site_tx_lo_isolation() {
  setup_fixture
  local site_a=alpha
  local site_b=beta

  fixture_ap "$site_a" A1 f4:92:bf:aa:66:ac
  fixture_ap "$site_a" A2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site_a" A1 "A2"
  fixture_neighbors "$site_a" A2 "A1"
  fixture_wlan_mapping "$site_a" Corp
  fixture_apgroup "$site_a" grp1 "f4:92:bf:aa:66:ac|f4:92:bf:aa:77:e0"
  fixture_wlanconf "$site_a" Corp "5g" "true" "-67" "all" "grp1"
  fixture_peer_5g_sighting "$site_a" A2 "$(mac_with_offset f4:92:bf:aa:66:ac 2)" -60
  fixture_peer_5g_sighting "$site_a" A1 "$(mac_with_offset f4:92:bf:aa:77:e0 2)" -60

  fixture_ap "$site_b" B1 1c:0b:8b:ba:ce:dc
  fixture_ap "$site_b" B2 1c:0b:8b:be:b9:7c
  fixture_neighbors "$site_b" B1 "B2"
  fixture_neighbors "$site_b" B2 "B1"
  fixture_wlan_mapping "$site_b" Corp
  fixture_apgroup "$site_b" grp1 "1c:0b:8b:ba:ce:dc|1c:0b:8b:be:b9:7c"
  fixture_wlanconf "$site_b" Corp "5g" "true" "-67" "all" "grp1"
  fixture_peer_5g_sighting "$site_b" B2 "$(mac_with_offset 1c:0b:8b:ba:ce:dc 2)" -60
  fixture_peer_5g_sighting "$site_b" B1 "$(mac_with_offset 1c:0b:8b:be:b9:7c 2)" -60

  # Site A: Open environment (TX_LO=-72, per ALGORITHM.md's documented table).
  TX_LO=-72
  prepare_site_roaming_checks "$site_a"
  local row_a
  row_a=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Corp" { print }' "$(roaming_wlan_tsv_path "$site_a")")
  assert_contains "$row_a" "${WLAN_FIELD_SEP}-72${WLAN_FIELD_SEP}" "site A (TX_LO=-72) must aggregate to -72, not a value from a different site"

  # Site B: Obstructed environment (TX_LO=-76). Same sighting (-60 dBm,
  # in-corridor for both) but a different default threshold.
  TX_LO=-76
  prepare_site_roaming_checks "$site_b"
  local row_b
  row_b=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Corp" { print }' "$(roaming_wlan_tsv_path "$site_b")")
  assert_contains "$row_b" "${WLAN_FIELD_SEP}-76${WLAN_FIELD_SEP}" "site B (TX_LO=-76) must aggregate to -76, independent of site A's TX_LO processed earlier"

  teardown_fixture
}

# ==============================================================================
# Test (review fix round 3, P1): the API-model detection (presence flag)
# and the AP-group data being available are independent. A site where the
# new field IS present but the AP-groups fetch produced nothing (empty
# apgroups.tsv -- e.g. the v2 endpoint returned an empty list, not a
# failure) must still produce a roaming_wlan.tsv row for the field-bearing
# WLAN ("not_evaluable"), never silently no row at all -- a missing row
# reads downstream as "older API", which would be wrong since the field
# was in fact seen.
# ==============================================================================
test_field_present_but_apgroups_empty_still_produces_row() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" Corp
  # Deliberately no fixture_apgroup call: site_apgroups_tsv_path() stays
  # empty, simulating fetch_site_apgroups() returning zero groups (endpoint
  # reachable, parsed fine, but genuinely has no group data yet).
  : >"$(site_apgroups_tsv_path "$site")"
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "grp1"

  prepare_site_roaming_checks "$site"

  # The presence flag must be set (the field was on the WLAN).
  if [[ -f "$(roaming_field_present_flag_path "$site")" ]]; then
    pass_count=$((pass_count + 1))
  else
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n' "presence flag must be set even though apgroups data is empty" >&2
  fi

  # And the WLAN must still get a row (not_evaluable), not be silently
  # absent from roaming_wlan.tsv (which the output layer would misread as
  # "older API without roaming_assistant_na_*").
  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Corp" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "not_evaluable" "a field-bearing WLAN with no resolvable AP-group data must still get a not_evaluable row, not be silently absent"

  teardown_fixture
}

# ==============================================================================
# Test (review fix round 3, P2): when EVERY ap_group_id on a WLAN is
# unresolvable (not just some), the specific unresolved group IDs must
# still be named in the reason, not just the generic
# "no broadcasting APs resolved" text.
# ==============================================================================
test_incomplete_all_group_ids_unknown() {
  setup_fixture
  local site=default

  fixture_ap "$site" AP1 f4:92:bf:aa:66:ac
  fixture_ap "$site" AP2 f4:92:bf:aa:77:e0
  fixture_neighbors "$site" AP1 "AP2"
  fixture_neighbors "$site" AP2 "AP1"

  fixture_wlan_mapping "$site" Corp
  # No fixture_apgroup call for either ID -- both references are dangling.
  : >"$(site_apgroups_tsv_path "$site")"
  fixture_wlanconf "$site" Corp "5g" "true" "-67" "all" "missing-a|missing-b"

  prepare_site_roaming_checks "$site"

  local row
  row=$(awk -F "$WLAN_FIELD_SEP" '$1 == "Corp" { print }' "$(roaming_wlan_tsv_path "$site")")
  assert_contains "$row" "not_evaluable" "a WLAN whose every ap_group_id is unresolvable must be not_evaluable"
  assert_contains "$row" "missing-a" "reason must name the first unresolvable group id even when ALL groups are unresolvable"
  assert_contains "$row" "missing-b" "reason must name the second unresolvable group id even when ALL groups are unresolvable"

  teardown_fixture
}

# ==============================================================================
# Test (review fix round 3, P2): a malformed/unexpected apgroups API
# response (valid HTTP, invalid/unexpected JSON body -- e.g. schema drift)
# must not abort the run. This exercises the exact code path
# fetch_site_apgroups() uses (its embedded python parser via a real curl
# fetch against a local HTTP server that returns a 200 with a broken body),
# not just its curl-failure branch, which
# test_fetch_site_apgroups_survives_unreachable_endpoint() already covers.
# ==============================================================================
test_fetch_site_apgroups_survives_malformed_response() {
  setup_fixture
  local site=default

  # A minimal local HTTP server that returns 200 with a non-JSON body,
  # reachable long enough for fetch_api_json's curl call to succeed at the
  # transport level while the embedded python parser then fails on it --
  # exercising fetch_site_apgroups()'s "python3 ... else" branch specifically,
  # not the curl-failure branch already covered elsewhere.
  local server_log="${tmpdir}/httpd.log"
  python3 -c '
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b"this is not valid json{{{")
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
print(srv.server_port)
sys.stdout.flush()
srv.handle_request()
' >"$server_log" 2>/dev/null &
  local server_pid=$!

  local port=""
  local _wait_i=0
  while [[ -z "$port" && $_wait_i -lt 50 ]]; do
    port=$(head -1 "$server_log" 2>/dev/null)
    [[ -z "$port" ]] && sleep 0.1
    _wait_i=$((_wait_i + 1))
  done

  if [[ -z "$port" ]]; then
    fail_count=$((fail_count + 1))
    printf 'FAIL: %s\n' "test setup: local HTTP server for malformed-response test never started" >&2
    # `kill` returns non-zero if the child has already exited (bind race,
    # sigpipe on server_log write). Under `set -e` that aborts the whole
    # test script, skipping teardown, every subsequent test, and the final
    # pass/fail summary. Swallow the exit status with `|| true`.
    kill "$server_pid" 2>/dev/null || true
    teardown_fixture
    return
  fi

  UNIFI_URL="http://127.0.0.1:${port}"
  UNIFI_API_KEY="test"

  local rc=0
  fetch_site_apgroups "$site" || rc=$?
  assert_eq "0" "$rc" "fetch_site_apgroups must survive a malformed (invalid JSON) response body, not just a connection failure"

  # `wait` propagates the child's exit status; a non-zero exit from the
  # python HTTP subprocess (unhandled handler exception, sigpipe on
  # stdout, Python 3.13+ stricter close semantics) aborts the script
  # under `set -e` before teardown_fixture runs, hiding the whole
  # roaming_test.sh summary line. Same guard shape as the fetch_* call
  # three lines up.
  local _srv_rc=0
  wait "$server_pid" 2>/dev/null || _srv_rc=$?

  teardown_fixture
}

# ==============================================================================
# Runner
# ==============================================================================
test_ssid_peer_filtering
test_asymmetric_direction
test_tie_handling_floor_clamp
test_incomplete_no_relevant_neighbor
test_incomplete_missing_sighting
test_na_2g_only_wlan
test_na_single_ap_wlan
test_missing_new_field_no_row
test_incomplete_partial_missing_sighting
test_incomplete_unconfigured_broadcasting_ap
test_2g_only_site_no_fallback_trigger
test_calculate_roaming_recommendation_default
test_calculate_roaming_recommendation_margin_cap
test_overlapping_groups_deduplicated
test_incomplete_unknown_group_id
test_fetch_site_apgroups_survives_unreachable_endpoint
test_site_wide_fallback_flag_set_when_any_wlan_has_field
test_multi_site_tx_lo_isolation
test_field_present_but_apgroups_empty_still_produces_row
test_incomplete_all_group_ids_unknown
test_fetch_site_apgroups_survives_malformed_response

printf 'roaming_test.sh: %d passed, %d failed\n' "$pass_count" "$fail_count"
((fail_count == 0))

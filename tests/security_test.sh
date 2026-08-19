#!/usr/bin/env bash
# Fixture tests for WLAN security-protocol classification and its dependent
# advisories: security_protocol_state(), security_protocol_uses_sae(),
# security_protocol_uses_wpa3(), and print_wpa3_pmf_required_advisory().
# Sources unifiwifioptimizer directly -- the source guard at the end of the
# file means main() does not run, so scan-loop/API side effects never happen
# here. No fixture files needed: these functions take plain string args.
set -euo pipefail

TEST_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOOL="${TEST_DIR}/../unifiwifioptimizer"

# shellcheck source=/dev/null
source "$TOOL"
# shellcheck source=./test_helpers.sh
source "${TEST_DIR}/test_helpers.sh"

# ==============================================================================
# security_protocol_state(): WPA3 Enterprise must be distinguished from
# WPA3 Personal (SAE) -- they authenticate differently (802.1X/EAP vs. SAE
# handshake).
# ==============================================================================
test_state_wpa3_enterprise() {
  assert_eq "WPA3 Enterprise" \
    "$(security_protocol_state wpaeap "" true false)" \
    "enterprise + wpa3_support + no transition -> WPA3 Enterprise"
}

test_state_wpa2_wpa3_enterprise() {
  assert_eq "WPA2/WPA3 Enterprise" \
    "$(security_protocol_state wpaeap "" true true)" \
    "enterprise + wpa3_support + transition -> WPA2/WPA3 Enterprise"
}

test_state_wpa3_personal() {
  assert_eq "WPA3" \
    "$(security_protocol_state wpapsk "" true false)" \
    "personal + wpa3_support + no transition -> WPA3"
}

test_state_wpa2_wpa3_personal() {
  assert_eq "WPA2/WPA3" \
    "$(security_protocol_state wpapsk "" true true)" \
    "personal + wpa3_support + transition -> WPA2/WPA3"
}

test_state_owe() {
  assert_eq "Enhanced Open (OWE)" \
    "$(security_protocol_state open "" true false)" \
    "open + wpa3_support -> Enhanced Open (OWE)"
}

test_state_owe_transition() {
  assert_eq "Enhanced Open with Transition" \
    "$(security_protocol_state open "" true true)" \
    "open + wpa3_support + transition -> Enhanced Open with Transition"
}

# ==============================================================================
# security_protocol_uses_sae(): true SAE (WPA3-Personal) only. Enterprise
# variants must NOT match -- they have no SAE Anti-clogging/Sync Time
# settings to check.
# ==============================================================================
test_sae_matches_wpa3_personal() {
  assert_success security_protocol_uses_sae "WPA3" "WPA3 (Personal) must use SAE"
}

test_sae_matches_wpa2_wpa3_personal() {
  assert_success security_protocol_uses_sae "WPA2/WPA3" "WPA2/WPA3 (Personal transition) must use SAE"
}

test_sae_rejects_wpa3_enterprise() {
  assert_failure security_protocol_uses_sae "WPA3 Enterprise" \
    "WPA3 Enterprise must NOT be treated as SAE (802.1X/EAP, not the SAE handshake)"
}

test_sae_rejects_wpa2_wpa3_enterprise() {
  assert_failure security_protocol_uses_sae "WPA2/WPA3 Enterprise" \
    "WPA2/WPA3 Enterprise must NOT be treated as SAE"
}

test_sae_rejects_owe() {
  assert_failure security_protocol_uses_sae "Enhanced Open (OWE)" "OWE must NOT be treated as SAE"
}

# ==============================================================================
# security_protocol_uses_wpa3(): any WPA3 variant, Personal or Enterprise.
# Used by the MLO advisory, which applies regardless of Personal/Enterprise.
# ==============================================================================
test_wpa3_matches_all_four_variants() {
  assert_success security_protocol_uses_wpa3 "WPA3" "WPA3 must count as WPA3-capable"
  assert_success security_protocol_uses_wpa3 "WPA2/WPA3" "WPA2/WPA3 must count as WPA3-capable"
  assert_success security_protocol_uses_wpa3 "WPA3 Enterprise" "WPA3 Enterprise must count as WPA3-capable"
  assert_success security_protocol_uses_wpa3 "WPA2/WPA3 Enterprise" "WPA2/WPA3 Enterprise must count as WPA3-capable"
}

test_wpa3_rejects_wpa2_and_owe() {
  assert_failure security_protocol_uses_wpa3 "WPA2" "plain WPA2 must not count as WPA3-capable"
  assert_failure security_protocol_uses_wpa3 "Enhanced Open (OWE)" "OWE must not count as WPA3-capable (it's not WPA3)"
}

# ==============================================================================
# print_wpa3_pmf_required_advisory(): fires only for MLO, using the WPA3-any
# predicate (so Enterprise satisfies it) -- never fires for 6 GHz, since the
# WLAN-level fields this tool reads can't distinguish UniFi's legitimate
# default 6 GHz config (WPA2/WPA3 + PMF Optional at WLAN level, WPA3-only +
# PMF Required enforced internally on the 6 GHz radio) from a real violation.
# ==============================================================================
test_mlo_advisory_silent_when_compliant() {
  local output
  output=$(print_wpa3_pmf_required_advisory "true" "WPA3" "Required")
  assert_empty "$output" "MLO + WPA3 + PMF Required must not trigger the advisory"
}

test_mlo_advisory_silent_when_wpa3_enterprise_and_required() {
  local output
  output=$(print_wpa3_pmf_required_advisory "true" "WPA3 Enterprise" "Required")
  assert_empty "$output" "MLO + WPA3 Enterprise + PMF Required must not trigger the advisory (Enterprise satisfies MLO's WPA3 requirement)"
}

test_mlo_advisory_fires_on_wpa2_only() {
  local output
  output=$(print_wpa3_pmf_required_advisory "true" "WPA2" "Required")
  assert_contains "$output" "MLO requires WPA3 + PMF Required" "MLO + plain WPA2 must trigger the advisory"
}

test_mlo_advisory_fires_on_pmf_optional() {
  local output
  output=$(print_wpa3_pmf_required_advisory "true" "WPA3" "Optional")
  assert_contains "$output" "MLO requires WPA3 + PMF Required" "MLO + WPA3 + PMF Optional must trigger the advisory"
}

test_mlo_advisory_silent_when_mlo_disabled() {
  local output
  output=$(print_wpa3_pmf_required_advisory "false" "WPA2" "Disabled")
  assert_empty "$output" "advisory must not fire at all when MLO is disabled, regardless of security/PMF"
}

test_mlo_advisory_silent_for_6ghz_default_config() {
  # UniFi's own default when 6 GHz is enabled on a multiband SSID: WLAN-level
  # WPA2/WPA3 (transition mode) + PMF Optional, even though the 6 GHz radio
  # itself enforces WPA3-only + PMF Required internally. This must stay
  # silent since there's no MLO involved and no per-band field to check.
  local output
  output=$(print_wpa3_pmf_required_advisory "false" "WPA2/WPA3" "Optional")
  assert_empty "$output" "non-MLO WLAN must never trigger this advisory, even with transition-mode security/PMF Optional"
}

# ==============================================================================
# Runner
# ==============================================================================
test_state_wpa3_enterprise
test_state_wpa2_wpa3_enterprise
test_state_wpa3_personal
test_state_wpa2_wpa3_personal
test_state_owe
test_state_owe_transition
test_sae_matches_wpa3_personal
test_sae_matches_wpa2_wpa3_personal
test_sae_rejects_wpa3_enterprise
test_sae_rejects_wpa2_wpa3_enterprise
test_sae_rejects_owe
test_wpa3_matches_all_four_variants
test_wpa3_rejects_wpa2_and_owe
test_mlo_advisory_silent_when_compliant
test_mlo_advisory_silent_when_wpa3_enterprise_and_required
test_mlo_advisory_fires_on_wpa2_only
test_mlo_advisory_fires_on_pmf_optional
test_mlo_advisory_silent_when_mlo_disabled
test_mlo_advisory_silent_for_6ghz_default_config

printf 'security_test.sh: %d passed, %d failed\n' "$pass_count" "$fail_count"
((fail_count == 0))

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased 0.5.0]

<!--
Focus statement: to be copied verbatim from this Version's OpenProject
description field once set (sw_dev_handbook v0.10.5,
documentation.md#version-focus-statement — one to two sentences naming
the version's goal, not a status recap or an approach detail).
-->

### Added
- `Handoff Suggestions (802.11v)` terminology note in `docs/ALGORITHM.md` §7 — UniFi renamed the controller UI label in Network Application 10.4.57; the API field name and this tool's terminology are unchanged.
- TX power recommendation for AP/band pairs with a configured neighbor but zero sightings in the current scan: jumps straight to the radio's maximum TX power instead of leaving it unchanged, to maximize the chance of achieving a sighting on the next run. Once already at the radio maximum with no sighting, this is reported as a distinct informational state instead of a repeated "raised to maximum" change on every run. See `docs/ALGORITHM.md` §4 "Zero-sighting recovery" for the rationale and its deliberate departure from vendor TX-spread guidance.
- "Fix TX power first" note next to an `Incomplete`/`Not evaluable` Roaming Assistant verdict when the site still has pending TX power recommendations — a missing sighting is often caused by TX power being too low to reach the neighbor.
- `roaming_assistant` profile field: whether Roaming Assistant / "Handoff Suggestions (802.11v)" should be enabled at all for a WLAN, distinct from `fast_roaming` (802.11r) and `bss_transition` (802.11v protocol support itself). Only the on/off expectation is profile-driven — the RSSI threshold stays computed from the site's RF model. Shipped defaults: disabled for `Standard`/`IoT`/`Hotspot`, enabled for `Throughput`/`Latency`. A deviation is flagged (✗) the same way any other profile check is. See `docs/ALGORITHM.md` §7 "Enable/disable expectation".
- `band_steering` profile field (controller field `no2ghz_oui`, live-verified against a real controller): whether dual-band clients should be steered away from 2.4 GHz. Shipped defaults: enabled for `Standard`/`Throughput`/`Latency` (a deliberate best-practice recommendation, not a UDM baseline snapshot), disabled for `IoT` (many clients are 2.4-GHz-only) and `Hotspot` (compatibility over optimization). Previously this field was out of scope with a "configure manually" note in `docs/PROFILES.md`; the other five fields considered for this cycle (Individual/Broadcast TWT, OWE Transition, SAE H2E-only, Transition Disable) were not added — none of them exist on the live-verified `wlanconf` controller schema.
- `tests/roaming_test.sh`, `tests/tx_test.sh`, run automatically by `./dev ci`.
- `.github/dependabot.yml` (github-actions weekly). Note: Dependabot reads the config only from the default branch, so it becomes active after this release branch is fast-forward-promoted to `main`.
- Doc-comments on every Top-Level Bash function in `unifiwifioptimizer` and `scripts/install.sh` (sw_dev_handbook v0.9.1).
- Advisory line when a WLAN's 2.4 GHz minimum data rate is below 12 Mbps. 11 Mbps and lower are the true 802.11b DSSS rates (1/2/5.5/11) and keep the 802.11b protection overhead active for every OFDM frame on the SSID; 6/9 Mbps are 802.11a/g OFDM rates still below the recommendation but don't themselves admit 802.11b clients, so the wording differs between the two cases. Independent of the profile-vs-actual comparison; also fires when no profile is matched.
- Advisory line when 802.11r Fast Transition is enabled on a WLAN whose matched profile is `IoT`. 802.11r is known to break specific IoT client classes (ESP32, older printers, Sonos gen1); the tool now points at splitting IoT off to its own SSID with 11r disabled, or relying on 802.11v alone.
- Advisory line when a WLAN has MLO enabled or broadcasts on the 6 GHz band but doesn't meet the corresponding security requirement — MLO requires WPA3 (PSK or Enterprise) + PMF Required; the 6 GHz band requires PMF Required with either WPA3 or OWE (Enhanced Open), since 6 GHz permits open-but-encrypted networks via OWE. Checked against the WLAN's actual controller configuration, not its matched profile.
- Advisory line when 802.11r Fast Transition is enabled but 802.11v (BSS Transition) is disabled — 802.11r's fast handoff depends on it being available. Checked against the WLAN's actual controller configuration, not its matched profile. An earlier version of this advisory also covered 802.11k (Radio Resource Management, backed by the controller's `rrm_enabled` field), but UniFi exposes no UI control for 802.11k on any level (WLAN, AP, or network-wide, live-verified 2026-08-08), so that half of the advisory wasn't actionable and was dropped.
- Security Protocol recognition for `Enhanced Open (OWE)` and `Enhanced Open with Transition` (UniFi Network 10.2+, live-verified against a real controller) — previously any WLAN with `security: open` was reported as plain `Open` regardless of its actual OWE encryption state.
- A `→` line under every ✗ compliance check and TX/roaming/channel recommendation, naming exactly where in the UniFi UI to make the change (e.g. "WLAN edit → Advanced → Security → PMF"). Live-verified against a real controller across WLAN, AP, and site-level settings screens this session; silent for the handful of checks with no confirmed UI location rather than guessing. The MLO hint additionally notes that toggling MLO in the UniFi UI silently changes PMF/WPA3-transition/Fast-Roaming as a side effect, discovered while verifying this feature.
- Scope statement at the end of every run: this tool works from controller configuration and AP-to-AP neighbor scans, and cannot see non-WiFi RF interference, per-client MCS or retry statistics, real roaming timing, or packet captures. Prevents the tool from being oversold as a spectrum-analysis or client-telemetry equivalent.

### Changed
- `sw_dev_handbook` pin bumped from v0.10.4 to v0.10.5.
- `dev` wrapper header pin bumped from a stale `v0.10.0` label to `v0.10.5`.
- `scripts/handbook-check.sh` refreshed from the v0.10.5 template — adds `copied_script_drift` check (WARN-only, compares this project's copies of `handbook-check.sh`/`github-security-settings.sh` against their upstream templates and expects `.divergence-reason` sidecars) and a `--whats-new [<target-tag>]` mode that prints the handbook's own `CHANGELOG.md` sections between this project's currently-pinned tag and a target tag.

### Fixed
- The `lo_unfixable`/Coverage-gap escalation check in `analyze_band()` now runs for every neighbor below `TX_LO`, not only when the TX recommendation itself was capped at the radio's TX limit. Because `calculate_tx_recommendation()` derives its shift from the *averaged* RSSI across all neighbors, a shift that resolves the average (or gets suppressed by hysteresis, leaving `rec_tx == current_tx`) could previously leave an individual neighbor still below `TX_LO` while only showing the softer `°` "Below corridor" marker instead of the correct `*` Coverage gap warning — silently understating a real coverage problem. The "Below corridor" note's claim that the recommendation resolves the neighbor is now actually guaranteed, since any neighbor it doesn't resolve is escalated to Coverage gap instead.
- `print_ui_path_hint()` gained the missing `"DTIM Period 6 GHz"` case arm — a non-compliant 6 GHz DTIM period was flagged red but silently printed no UI-path hint, unlike its 2.4/5 GHz siblings.
- `print_fast_roaming_iot_advisory()` now implements the 2.4-GHz-only-Standard-profile heuristic its doc-comment already described but the code never checked — a WLAN matched to `Standard` (or a future `Standard`-family profile) broadcasting only on 2.4 GHz with Fast Roaming enabled now gets the same IoT-client-breakage advisory as an `IoT`-profile WLAN.
- Removed a dead call to `print_min_rate_dsss_advisory` in `print_general_check_rate()`'s disabled-rate branch — the advisory's own guard clause (`is_true "$current_enabled" || return 0`) made that call a permanent no-op; the unconditional call later in the function already covers both branches.
- `docs/ALGORITHM.md` §6 corrected: it still documented `recommended_min_rssi = TX_LO`, but the actual formula (`f71ba13`, part of this same cycle) is `TX_LO - MIN_RSSI_OFFSET_DB`. Also corrected two stale constant values in the Design Constants table (`ROAM_FLOOR` was documented as -78 dBm, actual default is -75; `ROAM_CEILING` was documented as -67 dBm, actual default is -65) and added the missing `MIN_RSSI_OFFSET_DB` row.
- `Standard` and `Hotspot` profile baselines corrected against live-verified UniFi presets (2026-08-08, freshly created `Standard/Auto` and `Hotspot/Auto` WLANs on a real controller): `Standard`'s `band_steering: true` comment previously described it as a deliberate deviation from the UDM default -- it's actually the UDM default itself. `Hotspot`'s `multicast_broadcast_blocker`, `proxy_arp`, and `band_steering` were set to values that didn't match the live preset (`true`/`true`/`false` in the profile vs. `false`/`false`/`true` on the controller); corrected to `false`/`false`/`true` to match.
- `./dev handbook-check` now passes command-line flags through to `scripts/handbook-check.sh` — previously `--migrate` and `--whats-new` were silently dropped because the wrapper called the script bare.
- `.github/dependabot.yml` no longer declares a `pip` ecosystem — this repo has no Python manifest for Dependabot's pip updater to parse; the one pinned Python dependency (semgrep, inline in `ci.yml`'s `pip install` step) is not readable to Dependabot regardless.
- Reference-link definitions at the bottom of this `CHANGELOG.md` now match the actual `[Unreleased 0.5.0]` and `[Unreleased 0.4.1]` headings introduced by the v0.10.5 parallel-unreleased model — previously they referred to a `[Unreleased]` heading that no longer exists, so GitHub rendered the new headings as literal bracketed text.
- Site-level pending TX-power count no longer inflates on APs whose 5 GHz radio is inactive (===NO_RADIO===, empty API fields) — `prepare_site_tx_checks` now skips a band the same way `analyze_band` does, and matches its per-band TX default (11 dBm 2.4 GHz, 20 dBm 5 GHz) instead of always defaulting to 11.
- Roaming Assistant compliance line no longer reports a red ✗ deviation when the UniFi API returns `na_enabled=true` but `na_rssi=""` — a blank `na_rssi` was being coerced by bash arithmetic to 0 and compared against the site's aggregated_rssi, producing a phantom deviation with no visible cause.
- `tests/roaming_test.sh` malformed-response test no longer aborts the whole test script (skipping every subsequent test and the summary line) when the local HTTP subprocess fails to start or exits non-zero — `kill`/`wait` under `set -e` are now guarded with `|| true`/`|| rc=$?` the same way the primary `fetch_*` call already was.
- `prepare_site_tx_checks`, `prepare_site_roaming_checks`, and `check_general_settings` no longer leak `current_site` (and `_ip_col`/`_model_col` in the first) into caller scope — the missing `local` declarations were masked in the production AP loop but active leaks in the test suite.
- `scripts/install.sh` EXIT/INT/TERM trap now restores terminal echo before removing the tmpdir — a Ctrl-C between the SSH-password prompt's `stty -echo` and `stty echo` would otherwise leave the user's shell silently accepting input.
- `for gid in ${ap_group_ids_field//|/ }` (and the nested `for mac`) no longer subject each token to shell pathname expansion — a UniFi id or MAC containing a glob metachar would have silently iterated over local filenames instead of the id list. Now uses `IFS='|' read -r -a` into a properly-quoted array.
- Doc-comment above `print_tx_pending_note` no longer describes `print_general_check_roaming_assistant` — the two comments were swapped during the v0.10.5 doc-comment mass-adoption commit.
- `Throughput` and `Latency` profiles: `minrate_24_kbps` bumped from 11000 to 12000. 11 Mbps is an 802.11b DSSS rate; setting it as the minimum kept 802.11b clients allowed to associate and preserved the 802.11b protection overhead. 12 Mbps is the lowest OFDM rate. Matches Cisco/Aruba/Ubiquiti "kill 802.11b" guidance.
- `ROAM_FLOOR` bumped from -78 to -75 dBm and `ROAM_CEILING` from -67 to -65 dBm to match Apple's published BTM triggers (iOS/iPad -70 dBm, macOS -75 dBm). A floor below -75 lets BTM fire only after a macOS client has already fallen. The legacy fixed -67 dBm behavior can still be reproduced with `ROAM_CEILING=-67 ROAM_OFFSET_DB=<+7..+9>` (site-environment dependent).
- Minimum RSSI recommendation now sits `MIN_RSSI_OFFSET_DB` (default 5 dB) below TX_LO instead of at TX_LO itself. Vendor consensus is that the hard-disconnect threshold must sit 5-8 dB below the BTM (soft-roam) trigger; equal values give clients no roaming window and produce disconnect loops on 802.11v-capable clients.

## [Unreleased 0.4.1]

<!--
Verbatim-synced copy of `release/0.4.1`'s own [Unreleased 0.4.1] section.
Edits to any bullet below must happen on `release/0.4.1` first and be
copied here in a separate, immediately-following commit on
`release/0.5.0` before the underlying `release/0.4.1` work is considered
done (sw_dev_handbook v0.10.5,
documentation.md#parallel-unreleased-release-branches).
-->

### Fixed
- Roaming Assistant recommendations silently stopped working: Ubiquiti removed the per-radio API fields (`radio_table[].assisted_roaming_enabled`/`assisted_roaming_rssi`) at some point after v0.4.0, and the tool was falling back to defaults without any indication. Confirmed against a live controller (Network Application, AP firmware 6.7.54 and 8.7.11).
- `roaming_wlan.tsv` used a plain tab as field separator while its `aggregated_rssi` field is legitimately empty for `na`/`not_evaluable`/`incomplete` rows; `IFS=$'\t' read` collapses adjacent tabs (tab is IFS whitespace), silently shifting every field after the empty one and, in the worst case, aborting under `set -u`. Migrated to the existing `WLAN_FIELD_SEP` (`\037`) convention already used elsewhere for TSV rows with optional empty fields.
- Roaming Assistant compliance line no longer reports a red ✗ deviation when the UniFi API returns `na_enabled=true` but `na_rssi=""` — a blank `na_rssi` was being coerced by bash arithmetic to 0 and compared against the site's aggregated_rssi, producing a phantom deviation with no visible cause.
- `prepare_site_roaming_checks` and `check_general_settings` no longer leak `current_site` into caller scope — the missing `local` declarations were masked in the production AP loop but active leaks under any refactor that stopped shadowing them.
- `scripts/install.sh` EXIT/INT/TERM trap now restores terminal echo before removing the tmpdir — a Ctrl-C between the SSH-password prompt's `stty -echo` and `stty echo` would otherwise leave the user's shell silently accepting input.
- `for gid in ${ap_group_ids_field//|/ }` (and the nested `for mac`) no longer subject each token to shell pathname expansion — a UniFi id or MAC containing a glob metachar would have silently iterated over local filenames instead of the id list. Now uses `IFS='|' read -r -a` into a properly-quoted array.
- `Throughput` and `Latency` profiles: `minrate_24_kbps` bumped from 11000 to 12000. 11 Mbps is an 802.11b DSSS rate; setting it as the minimum kept 802.11b clients allowed to associate and preserved the 802.11b protection overhead. 12 Mbps is the lowest OFDM rate. Matches Cisco/Aruba/Ubiquiti "kill 802.11b" guidance.
- `ROAM_FLOOR` bumped from -78 to -75 dBm and `ROAM_CEILING` from -67 to -65 dBm to match Apple's published BTM triggers (iOS/iPad -70 dBm, macOS -75 dBm). A floor below -75 lets BTM fire only after a macOS client has already fallen. The legacy fixed -67 dBm behavior can still be reproduced with `ROAM_CEILING=-67 ROAM_OFFSET_DB=<+7..+9>` (site-environment dependent).
- Minimum RSSI recommendation now sits `MIN_RSSI_OFFSET_DB` (default 5 dB) below TX_LO instead of at TX_LO itself. Vendor consensus is that the hard-disconnect threshold must sit 5-8 dB below the BTM (soft-roam) trigger; equal values give clients no roaming window and produce disconnect loops on 802.11v-capable clients.
- `security_protocol_uses_sae()` now recognizes `WPA3 Enterprise`/`WPA2/WPA3 Enterprise`, not just `WPA3`/`WPA2/WPA3` — WLANs with Enterprise security were silently skipping the SAE Anti-clogging/Sync Time compliance checks.
- `scripts/install.sh` now creates `config.yaml` with `chmod 600` and preserves permissions on backup copies via `cp -p`, instead of relying on the caller's `umask` — the file holds an API key and optionally an SSH password.
- `SECURITY.md` corrected to match actual behavior — it previously claimed SSH host-key verification followed `~/.ssh/known_hosts` and TLS trust followed the system trust store, but both are actually disabled (`curl -k`, `StrictHostKeyChecking=no`), a deliberate tradeoff for a tool targeting a trusted local network.
- Semgrep CI config: `p/bash` removed (the ruleset no longer exists in the Semgrep registry, 404), version bumped from 1.140.0 to 1.172.0.
- The `lo_unfixable`/Coverage-gap escalation check in `analyze_band()` now runs for every neighbor below `TX_LO`, not only when the TX recommendation itself was capped at the radio's TX limit. Because `calculate_tx_recommendation()` derives its shift from the *averaged* RSSI across all neighbors, a shift that resolves the average (or gets suppressed by hysteresis, leaving `rec_tx == current_tx`) could previously leave an individual neighbor still below `TX_LO` while only showing the softer `°` "Below corridor" marker instead of the correct `*` Coverage gap warning — silently understating a real coverage problem. The "Below corridor" note's claim that the recommendation resolves the neighbor is now actually guaranteed, since any neighbor it doesn't resolve is escalated to Coverage gap instead.

### Changed
- Roaming Assistant migrated from a per-AP RF-tuning recommendation to a per-WLAN compliance check next to Fast Roaming, matching UniFi's move of the setting from radio level (`radio_table`) to WLAN level (`wlanconf.roaming_assistant_na_*`). The target threshold is still computed from the same site-aware corridor as before, aggregated (as a conservative minimum) across the APs that broadcast each WLAN, restricted to each AP's configured RF neighbors that also broadcast that SSID.
- WLANs whose broadcasting APs have incomplete data (a broadcasting AP with no SSID-relevant RF neighbor, or a missing neighbor sighting) are reported `Incomplete` with the specific reason, instead of a ✓/✗ verdict computed from a partial data set.
- On older controllers where no WLAN exposes the new field, the tool falls back site-wide to the previous per-AP behavior.

## [0.4.0] - 2026-05-06

Per-AP Roaming Assistant computed from the site-aware corridor instead of a
fixed -67 dBm, plus split coverage diagnostics.

### Added
- Per-AP Roaming Assistant threshold: default `TX_LO + ROAM_OFFSET_DB`, capped
  against the weakest neighbor when that neighbor falls below the corridor,
  then clamped to `[ROAM_FLOOR, ROAM_CEILING]`.
- Two distinct cap warnings with explicit reasons: `Roaming Assistant lowered
  to X dBm` (margin cap) and `Roaming Assistant clamped to ROAM_FLOOR` (floor
  cap).
- Softer coverage marker `°` **Below corridor before TX adjustment** for
  neighbors whose raw RSSI is below `TX_LO` but where the TX recommendation
  may still bring them back into the corridor.
- Environment variables `ROAM_OFFSET_DB`, `ROAM_MARGIN_DB`, `ROAM_FLOOR`,
  `ROAM_CEILING` for tuning the per-AP threshold. All four are validated
  early (integer + plausible range).

### Changed
- Site header no longer shows a single global Roaming Assistant value; the
  per-AP value lives in the AP's *Recommendations* block.
- `*` **Coverage gap** is now reserved for unfixable cases only: TX is at the
  radio limit and the projected RSSI is still below `TX_LO`.
- `docs/ALGORITHM.md` and `README.md` updated for the new algorithm, the
  three-way coverage diagnosis, and the explicit note that WLAN profiles are
  SSID-layer and do not influence Roaming Assistant or Minimum RSSI.

### Fixed
- `print_neighbor_row` no longer hard-codes the `*` marker; the caller-passed
  marker is rendered as-is.

## [0.3.0] - 2026-04-09

Scan reliability and adjacency group diagnostics.

### Added
- Adjacency group diagnostics in the scan output.
- `--help` in the CLI usage output.
- Note printed when the UniFi API is unavailable.
- Adjacency Groups section in `README.md`.

### Changed
- Multi-pass scan reliability improved and hysteresis tightened.
- TX power recommendations refined.
- Internal cleanup: simplified `iw` scanning logic.

## [0.2.0] - 2026-03-23

U7 support, installer, and documentation overhaul.

### Added
- U7 family SSH neighbor scan via `SET_SCAN_DWELL` (Qualcomm AP interfaces).
- Active band detection — inactive bands are skipped in scan and evaluation.
- DFS CAC warning when neighbor data is missing on a DFS channel.
- TX power limits read from UniFi API (`max_txpower`).
- Interactive install/uninstall scripts (`scripts/install.sh`,
  `scripts/uninstall.sh`).
- Restructured documentation: `docs/ALGORITHM.md`, `docs/PROFILES.md`,
  `docs/WALKTHROUGH.md`.

### Changed
- Executable renamed to `unifiwifioptimizer`.

## [0.1.0] - 2026-03-20

First public release.

### Added
- RF optimization engine based on ITU-R P.1238 path loss model.
- AP-to-AP neighbor scan via SSH (U6 family, MediaTek).
- WLAN profile validation against five shipped baselines (Standard, IoT,
  Hotspot, Throughput, Latency).
- TX Power, Roaming Assistant, and Minimum RSSI recommendations.
- UniFi Network API integration (read-only).
- Multi-site support.

[Unreleased 0.5.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.4.0...release/0.5.0
[Unreleased 0.4.1]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.4.0...release/0.4.1
[0.4.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jtauschl/unifiwifioptimizer/releases/tag/v0.1.0

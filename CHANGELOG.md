# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.1] - Unreleased

<!--
Since sw_dev_handbook v0.10.5 there are two open release lines
(release/0.4.1 hotfix and release/0.5.0 next-release), so this branch's
own in-progress content lives under its own version heading rather than
a plain [Unreleased] — release/0.5.0's CHANGELOG.md carries a verbatim
copy of this section, kept in sync per documentation.md#parallel-
unreleased-release-branches: an edit to any bullet here must land as a
separate, immediately-following commit on release/0.5.0 before the
underlying work here is considered done.
-->

### Fixed
- Roaming Assistant recommendations silently stopped working on current UniFi firmware.
- Fixed a rare crash or incorrect Roaming Assistant compliance result for a WLAN whose aggregated signal value was empty.
- Roaming Assistant compliance no longer reports a false deviation for a WLAN with Roaming Assistant enabled but no RSSI threshold set yet.
- A Ctrl-C during the installer's SSH password prompt no longer leaves the terminal not echoing typed input afterward.
- A UniFi AP group ID or MAC address containing special shell characters no longer causes incorrect behavior during analysis.
- `Throughput` and `Latency` profiles: minimum 2.4 GHz data rate raised from 11 Mbps to 12 Mbps, dropping legacy 802.11b compatibility in favor of Cisco/Aruba/Ubiquiti's "kill 802.11b" guidance.
- Roaming Assistant and Minimum RSSI defaults recalibrated to match Apple's published roaming triggers, reducing premature disconnects on iOS/macOS clients.
- Minimum RSSI recommendation is now set with a safety margin below the roaming trigger instead of equal to it, preventing disconnect loops on 802.11v-capable clients.
- WLANs using WPA3 Enterprise / WPA2/WPA3 Enterprise no longer silently skip SAE Anti-clogging/Sync Time compliance checks.
- The installer now creates `config.yaml` (and its backups) with restrictive file permissions, since it holds an API key and optionally an SSH password.
- `SECURITY.md` corrected: SSH host-key verification and TLS certificate trust are disabled by design for this tool, not enforced as previously documented.
- Coverage-gap warnings are now shown for every neighbor still below the target signal corridor, instead of only when TX power itself hit its hardware limit — a real coverage problem could previously be understated.

### Changed
- Roaming Assistant is now evaluated per WLAN instead of per AP, matching UniFi's own configuration model. WLANs with incomplete scan data are reported as `Incomplete` with a reason instead of a computed verdict.
- On older controllers without per-WLAN Roaming Assistant support, the tool falls back to the previous per-AP behavior.

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

[0.4.1]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jtauschl/unifiwifioptimizer/releases/tag/v0.1.0

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- Roaming Assistant recommendations silently stopped working: Ubiquiti removed the per-radio API fields (`radio_table[].assisted_roaming_enabled`/`assisted_roaming_rssi`) at some point after v0.4.0, and the tool was falling back to defaults without any indication. Confirmed against a live controller (Network Application, AP firmware 6.7.54 and 8.7.11).
- `roaming_wlan.tsv` used a plain tab as field separator while its `aggregated_rssi` field is legitimately empty for `na`/`not_evaluable`/`incomplete` rows; `IFS=$'\t' read` collapses adjacent tabs (tab is IFS whitespace), silently shifting every field after the empty one and, in the worst case, aborting under `set -u`. Migrated to the existing `WLAN_FIELD_SEP` (`\037`) convention already used elsewhere for TSV rows with optional empty fields.

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

[Unreleased]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.4.0...HEAD
[0.4.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/jtauschl/unifiwifioptimizer/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/jtauschl/unifiwifioptimizer/releases/tag/v0.1.0

# Algorithm

This document describes the RF model used by `UniFi WiFi Optimizer`.
It explains the practical design target behind the calculations, the mathematical derivation of the RF corridor, and how the script turns AP-to-AP neighbor RSSI into concrete recommendations for transmit power, roaming assistance, and minimum RSSI.

The model targets the long-established practical design goal of about 20% cell overlap at `-67 dBm`, adjusted for the configured RF environment such as open space, office, or obstructed layouts.

WLAN profile checks provide supporting best-practice guidance alongside the RF calculation described here.

## 1. Design Goal

The script uses AP-to-AP neighbor RSSI as a proxy for cell overlap:

- **TX Power** targets the center of a corridor derived from the RF environment
- **Roaming Assistant** is per AP: default = `TX_LO + ROAM_OFFSET_DB`, capped against the weakest neighbor when that neighbor is below the target corridor, then clamped to `[ROAM_FLOOR, ROAM_CEILING]`
- **Minimum RSSI** is derived from the lower corridor bound (`TX_LO`) and can be enabled selectively

The script implements this by comparing measured neighbor RSSI against a derived target corridor and converting the delta into per-radio recommendations.

## 2. Data Sources

1. **UniFi API** — radio settings: channel, TX power, TX limits, TX mode, Minimum RSSI, Roaming Assistant
2. **SSH** — AP-to-AP neighbor BSS scans on 2.4 and 5 GHz

The script detects scan-capable interfaces automatically via `iface_can_scan()`: on MediaTek-based APs (U6 family) it uses the dedicated managed interfaces (`apcli0`/`apclii0`); on Qualcomm-based APs (U7 family) it uses AP interfaces that advertise the `SET_SCAN_DWELL` PHY capability. Only active bands are scanned. Target BSSIDs are derived from the AP base MAC via offsets `+1` and `+2`.

Each AP is scanned serially. Per band, the script can repeat `iw scan` multiple times (`SCAN_ATTEMPTS`, default `2`) and merges the results by keeping the strongest RSSI per BSSID.

### Multi-Pass Scanning

The `scan_passes` config option (per site, default `1`) controls how many full round-robin scan cycles are performed before analysis. Each pass scans every AP in sequence, so the measurements are spread over time rather than taken in a single burst.

When `scan_passes >= 3`, a **trimmed mean** is applied per BSSID: the highest and lowest measurements across passes are discarded, and the remaining values are averaged. This removes single-measurement outliers (e.g. a spike caused by a temporary obstruction or a DFS channel change mid-run) without requiring an odd number of passes.

Additionally, the channel (frequency) seen per BSSID is tracked across passes. If the channel changes between passes — as happens with DFS automatic channel selection — measurements from different channels are not averaged together. Instead, only the measurements from the most common channel are used, discarding the cross-channel readings as physically incomparable.

For `scan_passes` of 1 or 2, the original behavior applies: the strongest RSSI per BSSID is kept.

**Recommended usage:**
- `scan_passes: 1` — initial setup, fast convergence
- `scan_passes: 3` — fine-tuning, noise-filtered stable measurements

## 3. Neighbor Evaluation

For each neighbor relationship, the script collects:

- **RSSI @ Neighbor**: signal from the *current AP* measured at the *neighbor AP*

This is the only direction affected by the current AP's TX power. From all values per band, the script derives `avg_neighbor_rssi`.

## 4. TX Power Heuristic

### Calculation

```text
corridor_center = TX_LO + CORRIDOR_WIDTH / 2
shift           = corridor_center - avg_neighbor_rssi

if avg_neighbor_rssi is already within [TX_LO, TX_HI]:
    recommended_tx = current_tx          # already in corridor, no change
else:
    recommended_tx = clamp(current_tx + shift, radio_min_tx, radio_max_tx)
```

The in-corridor check takes priority: if the average neighbor RSSI already falls within the target corridor, no recommendation is made regardless of the shift value. This prevents unnecessary changes when the signal is at a corridor boundary.

The derived TX shift uses **ceiling rounding** before the clamp is applied. Half steps therefore prefer the next higher whole-dBm recommendation instead of rounding down.

### TX Power Hysteresis

The hysteresis is asymmetric:

- increases are applied from `+1 dBm`
- reductions are suppressed until at least `-3 dBm`
- hardware limits still win immediately

In simplified form:

```text
if delta_tx > 0 and delta_tx < 1 and recommended_tx != radio_max_tx:
    recommended_tx = current_tx

if delta_tx < 0 and |delta_tx| < 3:
    recommended_tx = current_tx
```

The asymmetry reflects the cost difference: insufficient TX power causes coverage gaps and dropped connections, while slightly excessive TX power only creates mild cell overlap. The reduction threshold of 3 dBm is chosen to exceed the typical `iw scan` measurement noise of ±2–3 dBm, so that a reduction is only recommended when the signal is genuinely above the corridor.

Minimum RSSI is a fixed value — no hysteresis. Roaming Assistant is per AP (see §7) but does not use hysteresis either: the recommendation is computed from the latest scan, the same way `TX_LO` is derived.

### Coverage warnings

Two distinct diagnoses are emitted per neighbor:

- `*` **Coverage gap** — emitted when even at the radio's TX limit the projected RSSI stays below `TX_LO` (`tx_uncapped > radio_max_tx` and projected RSSI < `TX_LO`). This means TX adjustment cannot fix the situation; the AP placement, antenna orientation, or an additional AP needs to be considered.
- `*` **Excess overlap** — emitted when even at the radio's TX minimum the projected RSSI stays above `TX_HI` (`tx_uncapped < radio_min_tx` and projected RSSI > `TX_HI`). Symmetric counterpart of the coverage gap.
- `°` **Below corridor before TX adjustment** — emitted when the *raw* measured RSSI is below `TX_LO`, regardless of whether the TX recommendation can correct it. This is informational: the recommended TX shift may or may not lift the projected signal back into the corridor, and the Roaming Assistant cap (§7) reflects this neighbor as an input.

The `°` marker is suppressed for a neighbor that is already flagged with `*`, since the harder coverage-gap statement supersedes it.

## 5. TX Corridor Derivation

The corridor is derived from a common voice-oriented WLAN design rule of thumb: target about **20% cell overlap at −67 dBm**. At 60% of the AP-to-AP distance, the received signal must be at least −67 dBm.

The additional path loss from the 60% point to the full distance depends on the **path loss exponent n**:

```text
ΔdB   = 10 · n · log₁₀(100 / 60)
TX_LO = ROAM_TARGET − ΔdB
TX_HI = TX_LO + CORRIDOR_WIDTH
```

### Design constants

| Constant | Value | Source |
|----------|-------|--------|
| `ROAM_TARGET` | −67 dBm | Cisco VoWLAN cell-edge anchor for the path-loss model (not the per-AP threshold) |
| `OVERLAP_DIST` | 60% | ~20% cell area overlap → 60% of AP-to-AP distance |
| `CORRIDOR_WIDTH` | 6 dB | Symmetric tolerance around corridor center |
| `ROAM_OFFSET_DB` | 0 | Per-AP Roaming Assistant offset relative to `TX_LO` (set to 9 to reproduce the legacy −67 dBm value at Obstructed) |
| `ROAM_MARGIN_DB` | 5 | Safety margin between weakest neighbor RSSI and the capped threshold |
| `ROAM_FLOOR` | −78 dBm | Stability floor — below this, Roaming Assistant becomes pointless |
| `ROAM_CEILING` | −67 dBm | Hard ceiling for the Roaming Assistant recommendation |

`CORRIDOR_WIDTH` is a practical tolerance around the target overlap corridor. The current value of `6 dB` provides enough margin for normal variation and asymmetry without making the target corridor too loose to be useful.

`ROAM_FLOOR` and `ROAM_CEILING` are expert knobs (allowed range −95..−50 dBm). `ROAM_FLOOR` should normally stay at or below `TX_LO` for the configured environment; raising it (e.g. `ROAM_FLOOR=-60` on a `Residential` site with `TX_LO=-73`) clamps the site-aware default upward and turns the floor into an active, more aggressive trigger.

### Environment Presets

Path loss exponent `n` is set per site in `config.yaml` via `environment:`. The script uses the usual path loss exponent form, while ITU-R P.1238 Table 2 lists the corresponding distance loss coefficient `N` in the form `L = L(d0) + N*log10(d/d0) + Lf`. In other words, `N = 10*n`, so the implementation uses `2.8` where ITU lists `28`, `3.0` where ITU lists `30`, and so on.

| Preset | n | ΔdB | TX_LO | TX_HI | ITU-R P.1238 category |
|--------|---|-----|-------|-------|-----------------------|
| `Open` | 2.2 | 4.88 | −72 | −66 | Commercial (large open spaces, retail) |
| `Residential` | 2.8 | 6.21 | −73 | −67 | Residential *(default)* |
| `Office` | 3.0 | 6.65 | −74 | −68 | Office |
| `Obstructed` | 4.0 | 8.87 | −76 | −70 | Obstructed (concrete, brick, multi-wall) |
| `<number>` | x | — | — | — | Custom n |

The same TX_LO/TX_HI apply to all bands.

## 6. Minimum RSSI

```text
recommended_min_rssi = TX_LO
```

Fixed value from the corridor, not from measurements. Acts as a hard disconnect threshold — the AP stops serving a client when its signal drops below `TX_LO`.

### Relationship to Roaming Assistant

**With `ROAM_OFFSET_DB=0`, Roaming Assistant and Minimum RSSI sit at the same level (`TX_LO`). If you enable Minimum RSSI and want a soft-roam (BTM) lead time before the hard disconnect, set a positive `ROAM_OFFSET_DB` (for example `3`).**

The default targets SOHO deployments where voice-style roaming is rare and Minimum RSSI is typically left disabled. Voice or realtime use cases that need a deliberate BTM lead time should set `ROAM_OFFSET_DB` explicitly.

For the default environment presets (`Open`, `Residential`, `Office`, `Obstructed`), `TX_LO` is between −72 and −76 dBm and `ROAM_FLOOR` is `−78`, so on APs where the coverage-gap cap engages, Roaming Assistant can drop below `TX_LO`. In that case the BTM request would be issued *after* Minimum RSSI would already have disconnected the client, so enabling Minimum RSSI on coverage-gap APs is not recommended. With a custom path-loss exponent that produces `TX_LO ≤ ROAM_FLOOR`, the cap cannot push Roaming Assistant below `TX_LO` at all.

The recommendation is always derived, but whether you enable it is a deployment choice. It is most useful when cells are planned, overlap exists, and sticky clients need to be reduced.

### Why WLAN profiles do not influence Roaming Assistant or Minimum RSSI

The shipped WLAN profiles (Standard, IoT, Hotspot, Throughput, Latency) control SSID-level settings: authentication, DTIM, UAPSD, fast-roaming toggle, minimum data rate, multicast handling. Roaming Assistant and Minimum RSSI are radio-level settings — one value per radio, regardless of how many SSIDs the radio carries. Because a single radio typically serves SSIDs from multiple profiles at the same time, a per-profile Roaming/Min-RSSI value cannot be applied cleanly. The decision stays explicit (via `ROAM_OFFSET_DB`) instead of being inferred from profile assignments.

## 7. Roaming Assistant

Recommended only on 5 GHz. The threshold is computed per AP from `TX_LO` and the weakest neighbor RSSI:

```text
default = TX_LO + ROAM_OFFSET_DB

if min(neighbor_rssi) < TX_LO:                # weakest neighbor below corridor
    cap = min(neighbor_rssi) - ROAM_MARGIN_DB
    threshold = min(default, cap)
else:
    threshold = default

threshold = clamp(threshold, ROAM_FLOOR, ROAM_CEILING)
```

`ROAM_OFFSET_DB=0` keeps the threshold at the lower corridor edge, which matches the published roaming triggers of common clients (Apple iPhone/iPad ~−70 dBm, Mac ~−75 dBm; Aruba ClientMatch sticky-min default −70 dBm). The legacy fixed value of −67 dBm can be reproduced by setting `ROAM_OFFSET_DB=9` at Obstructed.

The cap only triggers when the weakest neighbor is below `TX_LO`. APs whose worst neighbor is still inside the corridor keep the default — measurement noise around `TX_LO` does not pull the threshold down.

When the cap engages, the AP report shows one of two warnings depending on which mechanism set the final value:

- **`Roaming Assistant lowered to X dBm`** — the weakest neighbor is below `TX_LO`, so `min(neighbor) − ROAM_MARGIN_DB` is used (and is still above `ROAM_FLOOR`). The threshold tracks coverage but stays in usable territory.
- **`Roaming Assistant clamped to ROAM_FLOOR (X dBm)`** — `min(neighbor) − ROAM_MARGIN_DB` would fall below `ROAM_FLOOR` and is clamped. This is a stability floor, not a quality target: it prevents aggressive BTM requests at APs that have no reachable roaming neighbor, but it does not fix the underlying coverage problem.

The Roaming Assistant sends an 802.11v BSS Transition Management (BTM) request when a client's signal drops to the threshold. BTM is advisory — the client may ignore it.

| Recommendation | Value | Enabled by default? |
|----------------|-------|---------------------|
| Roaming Assistant | per AP, default `TX_LO + ROAM_OFFSET_DB`, clamped to `[ROAM_FLOOR, ROAM_CEILING]` | Yes (5 GHz only) |
| Minimum RSSI | `TX_LO` | Use selectively |

WLAN profiles do not influence this recommendation; see §6 for the rationale.

## 8. Channel Width Planning

The optimizer does not currently compute a target channel width.

Instead, it uses the configured adjacency graph only for two hard checks:

- **2.4 GHz overcrowding**: more than three adjacent APs share only the clean channels `1 / 6 / 11`
- **local width budget exceeded**: the currently configured widths of an AP and its direct neighbors no longer fit into the clean spectrum budget

Current local spectrum budgets:

- **2.4 GHz**: `60 MHz` (`3 x 20 MHz`)
- **5 GHz**: `320 MHz` (`2 x 160 MHz`, equivalently `4 x 80 MHz`)

These checks are informational guardrails. The script warns when the current layout is structurally too wide, but it does not derive a hard replacement width from that alone.

## 9. Channel Overlap Check

The optimizer also checks whether adjacent APs overlap spectrally even when the configured channel width itself is acceptable.

- **5 GHz** uses channel center frequency plus configured width to detect overlapping occupied spectrum
- **2.4 GHz** uses the same approach, with a small guard band so that the normal clean reuse pattern `1 / 6 / 11` stays non-overlapping while closer channels are flagged

This is evaluated against the explicitly configured adjacency list, using the controller-reported channel and width of the peer APs. As a result, channel overlap warnings are independent of whether a live neighbor scan happened to return data in that run.

## 10. Model Limits

- uses AP-to-AP RSSI as a proxy for cell overlap
- evaluates explicitly configured neighbor relationships

## References

- **ITU-R P.1238-10**: [Propagation data and prediction methods for the planning of indoor radiocommunication systems and radio local area networks in the frequency range 300 MHz to 450 GHz](https://www.itu.int/dms_pubrec/itu-r/rec/p/R-REC-P.1238-10-201908-S!!PDF-E.pdf)
- **Cisco**: [Site Survey Guidelines for WLAN Deployment](https://www.cisco.com/c/en/us/support/docs/wireless/5500-series-wireless-controllers/116057-site-survey-guidelines-wlan-00.html) — voice cell edge at −67 dBm, 20% overlap
- **Ubiquiti**: [Understanding and Implementing Minimum RSSI](https://help.ui.com/hc/en-us/articles/221321728-Understanding-and-Implementing-Minimum-RSSI)

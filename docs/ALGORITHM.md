# Algorithm

This document describes the RF model used by `UniFi WiFi Optimizer`.
It explains the practical design target behind the calculations, the mathematical derivation of the RF corridor, and how the script turns AP-to-AP neighbor RSSI into concrete recommendations for transmit power, roaming assistance, and minimum RSSI.

The model targets the long-established practical design goal of about 20% cell overlap at `-67 dBm`, adjusted for the configured RF environment such as open space, office, or obstructed layouts.

WLAN profile checks provide supporting best-practice guidance alongside the RF calculation described here.

## 1. Design Goal

The script uses AP-to-AP neighbor RSSI as a proxy for cell overlap:

- **TX Power** targets the center of a corridor derived from the RF environment
- **Roaming Assistant** is fixed at the design overlap point (`ROAM_TARGET` = −67 dBm)
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

Roaming Assistant and Minimum RSSI are fixed values — no hysteresis.

### Coverage warnings

Warnings appear only when the uncapped TX recommendation **exceeds a hardware limit** and neighbors are still outside the corridor:

- `tx_uncapped > radio_max_tx` and projected RSSI < `TX_LO` → **coverage gap**
- `tx_uncapped < radio_min_tx` and projected RSSI > `TX_HI` → **excess overlap**

Affected neighbors are flagged with `*`. This typically indicates uneven AP spacing or obstacles.

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
| `ROAM_TARGET` | −67 dBm | Cisco VoWLAN design guideline: −67 dBm cell edge |
| `OVERLAP_DIST` | 60% | ~20% cell area overlap → 60% of AP-to-AP distance |
| `CORRIDOR_WIDTH` | 6 dB | Symmetric tolerance around corridor center |

`CORRIDOR_WIDTH` is a practical tolerance around the target overlap corridor. The current value of `6 dB` provides enough margin for normal variation and asymmetry without making the target corridor too loose to be useful.

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

Fixed value from the corridor, not from measurements. Acts as a hard disconnect threshold — the AP stops serving a client when its signal drops below `TX_LO`. This gives a `CORRIDOR_WIDTH` (6 dB) margin below the roaming threshold.

The recommendation is always derived, but whether you enable it is a deployment choice. It is most useful when cells are planned, overlap exists, and sticky clients need to be reduced.

## 7. Roaming Assistant

```text
roaming_assistant = ROAM_TARGET = −67 dBm
```

Fixed, independent of environment or band. Sends an 802.11v BSS Transition Management (BTM) request when a client's signal drops to `ROAM_TARGET`. BTM is advisory — the client may ignore it. If the client turns around, signal improves and no roaming is triggered.

The asymmetric 60%/40% overlap design reduces ping-pong risk:

- current AP sees client at −67 dBm → sends BTM
- client is already closer to neighbor → neighbor receives client above −67 dBm
- after roaming, client is well above threshold on new AP → no immediate BTM

| Recommendation | Value | Enabled by default? |
|----------------|-------|---------------------|
| Roaming Assistant | −67 dBm | Yes |
| Minimum RSSI | `TX_LO` | Use selectively |

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

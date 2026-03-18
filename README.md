# UniFi WiFi Optimizer

> RF tuning and WLAN baseline review for UniFi access points — transmit power, roaming, and minimum RSSI recommendations derived from AP-to-AP neighbor scans.

<p align="center">
  <img src="docs/img/UniFiWiFiOptimizer.png" alt="UniFi WiFi Optimizer – RF tuning tool for UniFi access points" width="600">
</p>

`UniFiWiFiOptimizer` is a Bash tool for post-placement UniFi WLAN review and RF tuning.
It reads radio configuration and WLAN settings from the UniFi Network API, compares them against shipped WLAN profiles, collects AP-to-AP neighbor scan data via SSH, and generates recommendations for:

- profile-based WLAN best practices for Standard, IoT, Hotspot, Throughput, and Latency profiles
- access point settings: `Transmit Power`, `Roaming Assistant`, `Minimum RSSI`

The shipped profiles map either to current UniFi defaults (`Standard`, `IoT`) or to optimized presets for specific use cases such as public hotspots, throughput-focused WLANs, and low-latency WLANs.

AP recommendations are derived from AP-to-AP neighbor scan RSSI and target the long-established practical design goal of about 20% cell overlap at -67 dBm, adjusted for the configured RF environment such as open space, office, or obstructed layouts.

It does not write changes back to the controller — all recommendations must be applied manually. The SSH neighbor scan uses dedicated scan interfaces, so normal client WiFi service remains unaffected on supported UniFi APs and firmware.

For the full RF derivation, see [docs/ALGORITHM.md](docs/ALGORITHM.md).

## Requirements

- UniFi Network Application `10.0.162` or later
- UniFi AP firmware `6.7.x` or later for the SSH neighbor scan
- UniFi access points managed by that application, with `Device SSH Authentication` enabled
- Runtime dependencies: `bash`, `curl`, `python3`, `ruby`, `ssh`, and optional `sshpass` for password-based SSH login

## Workflow

For a complete step-by-step example, see [docs/WALKTHROUGH.md](docs/WALKTHROUGH.md).

1. In the UniFi Network Application (web UI), enable `Device SSH Authentication` and create a UniFi Network API key.
2. Copy `config.minimal.yaml` to `config.yaml` and fill only the controller connection:

```bash
cp config.minimal.yaml config.yaml
```

3. Discover the available site IDs:

```bash
./UniFiWiFiOptimizer --sites
```

4. Verify that you selected the correct site:

```bash
./UniFiWiFiOptimizer --site <siteid>
```

5. Generate a site skeleton:

```bash
./UniFiWiFiOptimizer --config <siteid> >> config.yaml
```

6. Complete `environment`, `wlans`, and `neighbors`, then run `./UniFiWiFiOptimizer`.
7. If you want a controller baseline first, let UniFi handle channel planning (for example Channel AI).
8. Fix per-WLAN profile deviations first.
9. Apply the per-AP RF recommendations that make sense for your site.
10. Re-test with real clients.

## Output

Each site report provides the values you use as the basis for your UniFi WLAN and access point configuration:

- **Environment**: the site-wide RF target corridor derived from the configured environment
- **WLAN**: per-SSID profile checks that show which settings already match and which should be corrected
- **Access Points**: neighbor RSSI, overlap or coverage issues, and per-radio recommendations for transmit power, roaming, and minimum RSSI

Apply the relevant changes in UniFi Network, run the tool again, and use the updated output to iteratively converge on a better result.

## Configuration

Site configuration lives in `config.yaml`. Reusable WLAN baselines live in `profiles.yaml`.

Starter files:

- `config.minimal.yaml`: controller-only starter config
- `config.example.yaml`: complete example config

`config.yaml`:

```yaml
controller:
  url: https://unifi.example.local
  api_key: ...

sites:
  default:
    ssh:
      user: ubnt
      password: ...

    environment: Residential

    wlans:
      Main: Throughput
      IoT: IoT
      Guest: Hotspot

    neighbors:
      AP1: [AP2, AP4]
      AP2: [AP1, AP3, AP4, AP5]
      AP3: [AP2, AP5]
      AP4: [AP1, AP2, AP5]
      AP5: [AP2, AP3, AP4]
```

Key settings:

| Key | Description |
|---|---|
| `controller.url` | Base URL of the UniFi Network application |
| `controller.api_key` | API key for all read-only controller requests |
| `sites.<site>.ssh.user` | SSH username from `Device SSH Authentication` for that site |
| `sites.<site>.ssh.password` | SSH password for password-based login for that site; omit to use key/agent auth |
| `sites.<site>.environment` | RF environment preset or custom path loss exponent used to derive the TX corridor |
| `sites.<site>.wlans` | Maps UniFi WLAN names to profile names |
| `sites.<site>.neighbors` | AP-to-AP neighbor model; names must match UniFi device names exactly (case-sensitive) |

Notes:

- Use the UniFi site ID as the key under `sites:` in `config.yaml`.
- `--sites` lists the available site IDs from the UniFi controller.
- `--site <siteid>` shows WLANs and access points for exactly that site ID.
- `--config <siteid>` prints a config skeleton for exactly that site ID.

Environment presets:

- `Open`: large open spaces, retail, low attenuation
- `Residential`: homes and apartments
- `Office`: typical office floorplans
- `Obstructed`: concrete, brick, multi-wall layouts
- custom value: typical practical values are around `2.0` to `4.0`

For environment details, see [docs/ALGORITHM.md](docs/ALGORITHM.md).

Profile presets:

- `Standard`
- `IoT`
- `Hotspot`
- `Throughput`
- `Latency`

For profile details, see [docs/PROFILES.md](docs/PROFILES.md).

`Band Steering` is not part of these profiles and should be set manually in UniFi Network.

`config.yaml` contains the API key and optionally the SSH password — protect it accordingly:

```bash
chmod 600 config.yaml
```

## Scope and Limits

Designed for homelabs, homes, apartments, and small to medium offices with manually managed UniFi deployments and known AP neighbor relationships.

Does not replace AP placement, channel planning, site surveys, capacity planning, or client-side validation.

## References

- Ubiquiti: [UniFi WiFi SSID and AP Settings Overview](https://help.ui.com/hc/en-us/articles/32065480092951-UniFi-WiFi-SSID-level-Settings-Overview)

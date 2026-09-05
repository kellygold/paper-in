# Wi-Fi setup

The DS-940DW can join your router's network (infrastructure mode) or create its own network (Wireless Direct). Infrastructure mode lets the Mac keep its normal internet connection for AI filing.

## Join your home network using a phone

1. Power on the scanner and put its mode switch in Wi-Fi mode.
2. On your phone, join the scanner's `DIRECT-…DS-940DW…` network. Its Network Key is printed on the scanner.
3. Open `https://192.168.118.1` in the phone's browser. Log in using the separate password labelled **Pwd** on the scanner.
4. Open **Network → Wireless → Wireless (Setup Wizard) → Start Wizard**, select your home network, and enter that network's password directly into the scanner's page.
5. Let the scanner apply the settings. If the phone disconnects from Wireless Direct, reconnect it to your normal Wi-Fi.
6. In Paper In, choose **Options → Connection → Wi-Fi**, click **Connect**, and allow Local Network access if macOS asks. Once connected, insert a sheet and click **Scan**.

The scanner supports 2.4 GHz Wi-Fi. Your Mac can use another band on the same router, provided the router allows devices to communicate across those networks. A guest network with client isolation will prevent discovery.

Source: [Brother DS-940DW User's Guide](https://support.brother.com/g/s/id/htmldoc/ads/cv_ds640/uke/PDF/PDF.pdf), “Configure Wi-Fi Settings in Infrastructure Mode.”

## If it does not connect

- Confirm the scanner is in Wi-Fi mode and has finished joining your router.
- Check **System Settings → Privacy & Security → Local Network** for Paper In's permission.
- Check that AirPrint Scanning is enabled in the scanner's **Network → Protocol** settings.
- Close other scanning applications and click **Connect** again. Paper In does not continually reconnect or automatically repeat a scan job.
- If the device has a fault light or reports an empty feeder, inspect the paper path and follow Brother's jam instructions. Connecting successfully is separate from successfully feeding a page.

Switching USB/Wi-Fi is disabled during capture. Switching while idle disconnects the old transport and preserves the current draft; click **Connect** for the new transport.

## Implementation and current evidence

USB discovers Apple's local `_ippusb._tcp` proxy. Wi-Fi discovers the scanner's `_uscan._tcp` service and uses its advertised port and `rs` path. Both use the same eSCL job lifecycle, image validation and durable draft callbacks. The model is checked again using scanner capabilities.

Wi-Fi image transfer currently uses HTTP on the local network. Use a trusted network. HTTPS-only (`_uscans._tcp`) devices and certificate enrollment are not implemented; no certificate validation is disabled. No Wi-Fi or scanner-admin password is stored by Paper In.

On the development DS-940DW, live Wi-Fi discovery, capability checks and a physical duplex capture succeeded through the production backend and draft store while the Mac retained its normal network route. Both images produced a two-page PDF. The device initially reported a jam even after its fault light went out; a power reboot cleared that state. The app did not override the jam report or automatically retry the scan.

Physical single-sided capture, interruption, sleep/wake and unplug/replug remain hardware validation steps. See [validation](validation.md).

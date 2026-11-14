# Troubleshooting: the Lumo Hub will not join Wi-Fi

The hub only connects to 2.4 GHz networks. If your router broadcasts one network name for both 2.4 GHz and 5 GHz bands, turn on the router's "separate bands" option during setup, or create a guest network on 2.4 GHz.

WPA3-only networks are not supported. Set the router to WPA2 or WPA2/WPA3 mixed mode.

## What the ring light means
- Slow blue pulse: ready for setup.
- Fast blue blink: connecting to Wi-Fi.
- Solid red: the Wi-Fi password was wrong. Restart setup from the app.
- Red blink: the hub joined Wi-Fi but cannot reach the Lumo cloud. Check whether the router blocks outbound port 8883.

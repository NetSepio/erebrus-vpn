#!/usr/bin/env bash
# Quick VPN leak check on a USB-connected Android device.
set -euo pipefail

PKG=com.erebrus.vpn

echo "=== ADB devices ==="
adb devices

ip_check() {
  adb shell "curl -s --max-time 12 https://api.ipify.org 2>/dev/null" \
    || adb shell "wget -qO- https://api.ipify.org 2>/dev/null" \
    || echo "(curl/wget unavailable in adb shell)"
}

echo ""
echo "=== Public IP (adb shell — other apps / system) ==="
ip_check

echo ""
echo "=== VPN active? ==="
adb shell dumpsys connectivity 2>/dev/null | grep -i "VPN\|tun" | head -5 || true

echo ""
echo "=== Erebrus logcat (last 30 lines) ==="
adb logcat -d -s erebrus-singbox:* 2>/dev/null | tail -30 || true

echo ""
echo "Tip: connect VPN in the app, then re-run: ip_check"
echo "In-app browser + egress IP readout use the app UID and should match VPN after fix."
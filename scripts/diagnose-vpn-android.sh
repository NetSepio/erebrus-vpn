#!/usr/bin/env bash
# Quick VPN leak check on a USB-connected Android device.
set -euo pipefail

PKG=com.erebrus.vpn

echo "=== ADB devices ==="
adb devices

ip_check() {
  # IP-literal endpoint first: it answers even when DNS through a stalled
  # tunnel is dead (the common "connected but no internet" state).
  adb shell "curl -s --max-time 8 https://1.1.1.1/cdn-cgi/trace 2>/dev/null" | grep '^ip=' \
    || adb shell "curl -s --max-time 12 https://api.ipify.org 2>/dev/null" \
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
echo "=== Erebrus logcat: engine + Dart [VPN]/[Auth] (last 40 lines) ==="
adb logcat -d 2>/dev/null \
  | grep -E 'erebrus-singbox|flutter.*\[VPN\]|flutter.*\[Auth\]' \
  | tail -40 || true

echo ""
echo "Tip: connect VPN in the app, then re-run: ip_check"
echo "In-app browser + egress IP readout use the app UID and should match VPN after fix."
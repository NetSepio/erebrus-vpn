# android/app/libs

Drop `libbox.aar` here — the gomobile build of sing-box's mobile core that
`ErebrusVpnService` links against (`io.nekohasekai.libbox.*`).

Build it from the repo root:

```bash
./scripts/build-libbox.sh        # pins SING_BOX_VERSION (default v1.11.15)
```

This is intentionally **not committed** (it's a large, reproducible binary).
CI should run the script and cache the artifact. Keep `SING_BOX_VERSION` in sync
with the node's sing-box so the REALITY/Hysteria2 client matches the server.

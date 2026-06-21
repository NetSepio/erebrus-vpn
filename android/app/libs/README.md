# android/app/libs

Drop `libbox.aar` here — the gomobile build of sing-box's mobile core that
`ErebrusVpnService` links against (`io.nekohasekai.libbox.*`).

Build it from the repo root:

```bash
./scripts/build-libbox.sh
```

The script pins **source** by git commit (default sing-box `v1.11.15` →
`bc35aca01704497c179da1a03e45ad8e32f1a51b`) and a fixed gomobile version.
The resulting `libbox.aar` hash may still differ between rebuilds — we verify
inputs, not the binary SHA.

This is intentionally **not committed** (it's a large, reproducible binary).
CI should run the script and cache the artifact. Bump `SING_BOX_COMMIT` when
the node's sing-box version changes.

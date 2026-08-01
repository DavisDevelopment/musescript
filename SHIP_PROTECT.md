# Ship protect (MuseScript engines)

Minify + obfuscate Haxe→JS engines for desktop / mobile / hub **ship** channels.

```bash
npm install
haxe build-runtime.hxml && haxe build-pine-web.hxml
npm run ship-js    # → build/ship/{medium,heavy}/
npm run ship-ab    # → LOCKED_PRESET + ab-report.json (parity stays on build/js/)
```

Sync:

```powershell
pwsh tools/sync-mobile-runtime.ps1          # raw → mobile (dev)
pwsh tools/sync-mobile-runtime.ps1 -Ship    # locked preset
pwsh tools/sync-web-runtime.ps1 -Ship       # mederos-web hashed public/
```

See `kalshai/mobile/SHIP_PROTECT.md` for app allowlist + Vite ship mode.

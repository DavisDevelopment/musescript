# MuseScript I/O surface (`muse.re` / `muse.fs` / `muse.http` / grants)

**Status:** M2 landed (`muse.http` + fixture replay/record). Ingest tier (`runIngest` / `--ingest`) closes HTTP→CSV→offline fitness. `muse.db` = M3.  
**Related:** `docs/PLUGIN_KINDS.md`, `musescript/io/IoGrant.hx`, IO plan §2–5.
## Tier doctrine

| Surface | Fitness / evo | Plugins | Studio/CLI ingest |
|---|---|---|---|
| `muse.str` / `muse.path` / `muse.re` | yes (pure) | yes (compute) | yes |
| `muse.fs` | **no** (`opts.grants` null → `IoDenied`) | **always deny** `io_fs` | yes with `FsGrant` roots |
| `muse.http` | **no** live; replay fixtures only if NetGrant | **always deny** `io_net` | replay / record / strict |
| `muse.db` | no (M3) | deny `io_fs` | planned |

**Backtest must never silent-live.** Default HTTP mode is **replay**; a missing fixture is a hard `IoDenied`, not a spontaneous network call.

## `muse.re` (portable subset)

```
pat = muse.re.compile(pattern, flags?)   // flags: i m s only
muse.re.test(pat, s) -> bool
muse.re.match(pat, s) -> null | { matched, start, end, groups }
muse.re.find_all(pat, s, limit?)
muse.re.replace(pat, s, repl, limit?)    // $0 $1..$9 $$ in repl
muse.re.split(pat, s, limit?)
```

Flats: `re_compile` / `re_test` / `re_match` / `re_find_all` / `re_replace` / `re_split`.

- **Engines:** JS `RegExp`, JVM `java.util.regex.Pattern`.
- **Rejected:** flag `u`, `\p{…}`, named groups `(?<…)`, nested-quantifier bombs (`(a+)+`).
- **Budgets:** pattern ≤ 256 chars; input ≤ 1e6 chars; find_all/split capped.
- **Goldens:** `tools/re_golden/fixtures/*.json` — JS Node gate today; JVM rows should match the same files.

## `muse.fs` (grant sandboxed, sync)

```
muse.fs.read_text(path) / exists / list / is_file / is_dir
muse.fs.write_text / append_text / mkdir   // require root write:true
```

Path forms:

- relative → first readable/writable grant root
- `rootName:rel/path` → named root
- absolute Muse path → must stay under some root's `abs`

`..` escape after normalize → `IoDenied`.

### FS grant shape

```js
opts.grants = {
  fs: {
    roots: [{ name: "workspace", abs: "/abs/path", read: true, write: false }],
    mode: "sync"
  }
}
```

## `muse.http` (NetGrant + fixtures)

```
resp = muse.http.request({
  method: "GET"|"POST"|…,
  url: string,
  headers?: dict,
  body?: string,
  timeout_ms?: int,          // default 10_000 (or NetGrant.timeout_ms)
  redirect?: "error"|"follow" // default "error"
})
// resp = { status, headers, body_text, url_final }

muse.http.get(url, opts?)
muse.http.post(url, bodyOrOpts?, opts?)
```

No WebSocket, cookie jar, or streaming bodies. Sync Muse API.

### NetGrant

```js
opts.grants = {
  net: {
    allow_hosts: ["api.example.com", "*.github.com"],
    allow_schemes: ["https"],          // default if omitted
    timeout_ms: 10000,
    max_bytes: 8 * 1024 * 1024,
    max_requests_per_run: 32,
    fixture_mode: "replay",            // replay | record | strict
    fixture_dir: "/abs/path/fixtures"
  }
}
```

CLI override: `opts.http = "replay"|"record"|"strict"|"off"` (mutates `fixture_mode`; `off` clears net).

| Mode | Behavior |
|---|---|
| **replay** (default) | Lookup `(method, url, body_hash)` on disk; **miss → hard error** |
| **record** | Live fetch + write fixture (CLI/ingest; refused when `isFitness`) |
| **strict** | Live only; refused when `isBacktest` / `isFitness` |

Transport: Node `fetch` (sync Worker bridge) / JVM `HttpURLConnection`. Tests may inject `HttpTransport.testLive`.

## Runtime hooks

```js
MuseRuntime.run(src, bars, { grants, http: "replay", fitness: true })
MuseRuntime.applyIoGrants(harness, opts)  // sets isFitness / isBacktest / http mode
MuseRuntime.runIngest(src, { grants, http: "replay"|"record", kind: "ingest"|"cli" })
```

Default / fitness: omit `grants` → any `fs_*` / `http_*` throws `IoDenied`.
`fitness:true` **strips** `opts.grants` even if present (fitness law: io always null).

## Ingest program kind (`runIngest` / `--ingest`)

First-class **Studio / CLI** tier that closes the IO loop for fitness:

```
muse.http (replay|record)  →  muse.fs.write_text / pd_read_csv
        →  PIT CSV under FsGrant root
        →  offline MuseRuntime.run / runPanel / GeneRunner --tape  (grants null)
```

Ingest sources are strategies **without** `@on(bar)` / `onBar` — body runs
**linearly once** in source order (so `var resp = http.get(...); write(resp…)`
works). See `examples/ingest/http_to_csv.ms`.

| API | Role |
|---|---|
| `MuseRuntime.runIngest(source, opts)` | Interp-only; requires `opts.grants`; refuses `fitness:true` |
| `opts.kind` | `"ingest"` (default) or `"cli"` — defaults `isBacktest=false` |
| `MuseInterp.executeIngest` | Linear strategy body once; **refuses** `@on(bar)` |
| GeneRunner / PanelRunner `--ingest` | Same loop from CLI |

CLI flags (GeneRunner / PanelRunner):

```
--ingest
--fs-root <abs|rel>          # writable workspace root
--fixture-dir <path>         # HTTP FixtureStore directory
--allow-hosts a,b,*.c.com
--http replay|record|strict|off
--grants <grants.json>       # optional full IoGrant JSON
```

Grants are built by `musescript.io.CliIoGrants.fromOpts`. Never default-enabled
on TruthReport / evo fitness — those keep `ioGrants = null`.

Example: `examples/ingest/http_to_csv.ms` → `examples/ingest/smoke_strategy.ms`.

**Not a plugin kind.** Plugins still deny `io_fs` / `io_net` at audit time.
## M3 next

SQLite `muse.db` behind grants; write hardening.

# MuseScript NdArray + Most-of-Numpy — Engineering Plan

**Status:** research-backed plan only (no implementation).  
**Workspace:** `muse-script` (Haxe 5.0.0-preview.1).  
**Governing doctrine (read first, obey forever):** `musescript/evo/nma/JIT_AUTHORING_GUIDE.md`, `RingBuffer.hx` / `GrowableVec.hx` / `FloatSeries.hx` headers, `indicators/PORTING.md`, `SPEC_BYTECODE_VM.md` (DetMath parity), `Palette.hx` evo boundary, `MuseHost.hx` + HostABI escape discipline.

---

## Research findings (compress)

### Haxe authorship guidelines in this repo
There is no separate STYLE.md / CONTRIBUTING. The **binding** guide is:

| Source | What it mandates for numeric work |
|---|---|
| `JIT_AUTHORING_GUIDE.md` | `@:multiType` or GTFO for unboxed buffers; indexed loops (not `for..in`); monomorphic JVM switches; TypedArrays on JS; no `Null<Float>` / `Dynamic` on hot edges; Engine/Context reuse on Graal |
| `RingBuffer` / `GrowableVec` / `FloatSeries` | Hand-written Float/Int/… impls; `#if js Float64Array` else `Vector<Float>` → `double[]`; document index conventions obsessively |
| `PORTING.md` | One-file / macro-collected registration; fixtures > “feels done”; run the suite |
| `SPEC_BYTECODE_VM.md` | Transcendentals via `DetMath`; bitwise-identical `+−×/` OK; `&&`/`\|\|` both-sides-eval |
| `Palette.hx` | Host stdlib ≠ genome palette; aux only when tape-present; no live I/O in strategy runtime |

### Existing numeric / ML surfaces (compose, don’t duplicate)

| Surface | Role | Relation to NdArray |
|---|---|---|
| `MlBuiltins` | Tiny `Array<Float>` + **`Dynamic`-shaped** `{rows,cols,data}` matrices | **Supersede** matrix payload; keep flat names as compatibility shims |
| `StatsBuiltins` / `sci_*` | mean/var/zscore/cumsum/diff/normalize | Reimplement as ndarray reductions/ufuncs; shims call NdArray |
| `RingBuffer` / `GrowableVec` / `FloatSeries` | Hot-path 1-D unboxed series | **Views / adapters** (`asNdArray`, zero-copy where dtype+contig match) |
| NMA columns (`GrowableVec<Float>`, `NmaBarColumns`, `NmaFeatureHost`) | Columnar tape eval | Bridge: column ↔ `NdArray` 1-D view |
| WASM feature tape / HostABI | Packed f64 slots after OHLCV; `host_eval` escapes | Feature columns as ndarray views over linear memory / host buffers |
| VM unboxed stack + `IND_*` / `CALL_BUILTIN` | Oracle subset | Extend with typed ND ops carefully; Dynamic matrix ops stay unsupported/escape |
| `muse.*` host (`MuseHost`) | Namespaced stdlib + Strat `this` lowering | **Primary author surface:** `muse.np` / `muse.ndarray` |
| PanelLoader / PanelFeed | Multi-symbol bars + `Bar.data` | Aux columns → ndarray views for cross-section / feature matrices |

**Today’s gap:** `ml_matrix*` is already Dynamic-poisoned; WASM throws `EmitUnsupported` for matrix/ridge; vector producers often only via special emit paths; no broadcasting, strides, dtype lattice, or deep language type beyond `TVector`/`TMatrix`.

### Targets Muse actually ships
| Target | How it shows up | NdArray stance |
|---|---|---|
| **JS / Node** (`build.hxml`, `run.ps1 test`) | Primary CI / examples | TypedArray backends; parity golden |
| **JVM / Graal** (`build-*-jvm.hxml`, CorpusEvoRun) | Evo oracle, GraalWasm host | `double[]` / `float[]` / `int[]` via `@:multiType` |
| **WASM** (StrategyWasm emit + GraalWasm / wasmtime) | Fitness hot subset | Packed f64 linear memory; host_eval / native split |
| **Python** (`build-py.hxml`, numba benches) | Emitter / cross-runtime stress | Golden fixture generation host; optional consume, not core backend |
| **HL / C++ / Eval** | Not a current ship gate | Design backends so they can plug; don’t block M-gates |

---

## Part A — Sprint retrospective context (build on this)

- **`muse.*` host + Strat/`this` lowering** is the proven pattern for deep stdlib exposure without new language syntax; NdArray must ride that rail (`muse.np`), not a shallow `ml_*` pile-on.
- **Panel WASM / panel evo + PanelLoader** already packs features and literal-of portfolio ops onto HostABI — NdArray must treat feature tapes and aux columns as first-class views, not orphan libraries.
- **Author holes + OOS / DSR-PBO** demand serializable genomes and deterministic fills; ndarray ops that touch fitness must be palette-gated and DetMath-honest.
- **Projections / CCEA** already co-evolve host projection graphs against tapes; ndarray is the natural substrate for projection feature matrices — keep causal/PIT seams intact.
- **Bytecode VM (unboxed stack) + CALL_BUILTIN/IND** is the attribution-oracle path; NdArray Muse ops need an explicit eligibility matrix (native / CALL_BUILTIN / escape) from day one, not as an afterthought.

---

## Part B — NdArray core (the product) + engine exposure

### B.0 North-star product contract

1. **Haxe library** with a sexy, nearly numpy-interchangeable API, **zero Dynamic on the typed API**.
2. **Same ops deeply exposed to MuseScript** on **all engines that claim support**, with documented native vs host_eval vs unsupported boundaries.
3. **Fitness-visible paths** stay float64-default, DetMath for transcendantals, PIT-safe, memo-key stable.
4. Compose with `GrowableVec` / `FloatSeries` / feature tapes; **supersede** `MlBuiltins` matrix Dynamic blobs.

---

### B.1 Type architecture (Haxe)

**Recommended: compile-time dtype via `@:multiType` abstracts + parallel concrete buffers** (RingBuffer pattern), *not* a single runtime-`DType`-tagged heap object as the primary API.

```haxe
// Sketch only — illustrative
@:multiType(@:followWithAbstracts T)
abstract NdArray<T>(INdArray<T>) {
  public var shape(get, never):Shape;
  public var strides(get, never):Strides;
  public var ndim(get, never):Int;
  @:arrayAccess public function getAt(i:Int):T;
  // ...
  @:to static function toF64(...):NdArrayF64Impl;
  @:to static function toF32(...):NdArrayF32Impl;
  @:to static function toI32(...):NdArrayI32Impl;
  @:to static function toBool(...):NdArrayBoolImpl;
}

/** Array-like that unifies scalar / list / ndarray without Dynamic */
@:multiType
abstract ArrayLike<T>(...) {
  @:from static function fromScalar(x:T):ArrayLike<T>;
  @:from static function fromArray(a:Array<T>):ArrayLike<T>;
  @:from static function fromNd(a:NdArray<T>):ArrayLike<T>;
}
```

| Dtype | M0–M2 | Later | Never (Muse fitness) |
|---|---|---|---|
| Float64 | **default** | — | — |
| Float32 | Backend + explicit cast | Accel / WASM SIMD experiments | Silent use on Sharpe / equity paths |
| Int32 | Index arrays, boolean→int | — | — |
| Bool | Masks | — | — |
| Int64 | Optional JVM/`haxe.Int64` | Cross-target only if CI covers | Rely without parity tests |
| Complex64/128 | After real stack | FFT gate | Blocking M0 |

**Why not primary `NdArray` + runtime `DType` enum?** Enum dispatch on every element load is megamorphic on JVM/V8; this repo’s doctrine forbids that on hot paths. A *cold* `AnyNdArray` existential (enum of concrete arrays) is fine for Muse runtime boxing of opaque values — see B.8.

**Overloads / abstracts vs enums (static targets):**
- Prefer **`@:overload` static methods** + **`ArrayLike<T>` / `Axis` / `Slice` abstracts** for `np.mean(a)`, `np.mean(a, 0)`, `np.mean(a, axis=[0,1])`.
- Prefer **`@:from`/`@:to`** for scalars and 0-d arrays over `Dynamic`.
- Use **enums only for cold metadata** (`Order.C`, `CastMode`, Muse opaque tags) — not for per-element dtype.

**JS vs JVM difference:** JS TypedArrays are already monomorphic per constructor; JVM needs separately authored `NdArrayF64Impl` with `Vector`/`double[]`. Same abstract surface; `#if` only inside impl storage.

---

### B.2 Memory model

| Concept | M0–M1 | M2+ |
|---|---|---|
| Layout | Contiguous **C (row-major)** owned buffers | Full strides: views, transpose as stride permute, reshape-as-view when contiguous |
| Views | `slice`/`reshape`/`T` may copy if not contiguous yet | True views sharing buffer + offset + strides |
| Broadcasting | NumPy rules (right-align, size 1 or equal) | Same; document divergence (none intended) |
| Copy vs view | Explicit `.copy()`; mutate-through-view tests | Advanced indexing may force copy (numpy-compatible) |
| Ownership | Owned vs aliased (FloatSeries pattern) | Bridge from GrowableVec/tape aliases |

**Broadcasting semantics:** implement a single `Broadcast.plan(shapes) → (outShape, iters)` used by all ufuncs — golden against numpy.

**Indexing roadmap:** basic slicing `a[i]`, `a[i:j]`, `a[..., k]` (via Slice abstracts) → boolean masks → integer array indexing → (later) `np.ix_`.

---

### B.3 API surface v1 (numpy-feel)

**Creation:** `zeros`, `ones`, `full`, `empty`, `arange`, `linspace`, `eye`, `identity`, `asarray`, `array`, `frombuffer` (target buffers).  
**Shape:** `reshape`, `ravel`/`flatten`, `transpose`/`T`, `swapaxes`, `expand_dims`, `squeeze`, `broadcast_to`, `copy`.  
**Ufuncs (elemwise):** `+ − * /`, `neg`, `abs`, `sqrt`, `exp`, `log`, `minimum`/`maximum`, `clip`, `where`, comparisons → Bool arrays.  
**Reductions:** `sum`, `prod`, `mean`, `min`, `max`, `argmin`/`argmax`, `any`/`all`, `std`/`var` — all with `axis` / `keepdims`.  
**Linear algebra kernel:** `matmul`/`@`/`dot` (1–2D first), `inner`, `outer`.  
**Dtype:** `astype`, promotion matrix aligned with numpy (with Muse float64-default policy for strategies).  
**Boolean indexing:** `a[mask] = …` / compress — M2.  
**`np.where`:** ternary form M1.

Expressive sugar: operator overloads where Haxe allows (`+`, `*`, comparison → Bool NdArray), `Shape`/`Axis` abstracts accepting `Int` or `Array<Int>`, optional **named axes** only after shape core is stable (don’t block M1).

---

### B.4 Target-specific backends

| Backend | Buffer | Notes |
|---|---|---|
| JS | `Float64Array` / `Float32Array` / `Int32Array` / `Uint8Array`(bool) | Prefer views over `ArrayBuffer`; SharedArrayBuffer later for worker evo only |
| JVM | `haxe.ds.Vector` / raw `java.NativeArray` / optional `ByteBuffer` for packed interchange | Keep `@:multiType` concrete classes; never `Array<Float>` on hot kernels |
| WASM guest | Linear memory regions + offset/length | Muse feature slots as 1-D f64 views; grow → reacquire views (existing WASM discipline) |
| HL/C++ | Native arrays when targeted | Same abstract; not a ship gate |
| Pure fallback | Owned growable buffer | Eval / debug |

**Accel hooks (not M0):** JVM BLAS JNI / Panama optional behind `#if`; JS stays pure Haxe; WASM SIMD later behind feature flag. Fitness default path = pure Haxe f64 unless an opt-in accel proves DetMath/parity.

---

### B.5 Zero-Dynamic / macros

- **Kernels:** macro or build-time generator emitting dtype-specialized loops (`NdUfuncGen`) — one source of broadcasting truth.
- **Public API:** no `Dynamic` parameters; Muse opaque handle uses **`AnyNdArray` enum** or sealed interface, converted explicitly at builtins boundary.
- **Kill list:** rewrite `MlBuiltins.matrix*` off `Dynamic` as soon as NdArrayF64 lands (compat shim OK for one milestone).

---

### B.6 File / module layout (repo conventions)

```
musescript/ndarray/           # Haxe core library
  NdArray.hx                  # @:multiType abstract
  NdArrayF64.hx / F32 / I32 / Bool
  Shape.hx, Strides.hx, Axis.hx, Slice.hx, ArrayLike.hx, DType.hx (cold)
  Broadcast.hx
  Ufuncs.hx / Reductions.hx / Linalg.hx
  backend/JsTyped.hx, JvmVector.hx, WasmLinear.hx (internal)
  bridge/GrowableVecView.hx, FloatSeriesView.hx, FeatureTapeView.hx
  Np.hx                       # static np.* facade for Haxe callers

musescript/builtins/
  NpBuiltins.hx               # Muse install surface (flat + muse.np)
  (MlBuiltins → thin shims)

musescript/types/
  MuseType.hx                 # add TNdArray (and maybe TNdArrayBool) or enrich TMatrix/TVector
  BuiltinSigs.hx              # muse.np / np_* signatures

musescript/compile/
  MuseHost (+ FLAT/OBJECT_NS), MuseHostLower, ClassStrategyLower
  JsBackend / JsEmitter       # dispatch + arity tables
  StrategyWasmEmitter/Backend # native vs host_eval matrix
  MuseBytecodeCompiler / Op   # ND eligibility

tools/ndarray_golden/
  gen_fixtures.py             # numpy → JSON fixtures (already have numpy in venv)

musescript/tests/
  TestNdArray*.hx             # excessive suite
  TestNpMuseParity.hx         # engine matrix
```

---

## Part B+ — Deep MuseScript / engine integration (FIRST-CLASS)

This is not “Phase optional.” **M-gates fail if Haxe NdArray ships without Muse exposure gates.**

### 1. Strategy author surface

**Primary UX (matches `muse.*` doctrine):**

```muse
// Preferred
w = muse.np.array([[1,2],[3,4]])
z = muse.np.matmul(w, muse.np.transpose(w))
s = muse.np.mean(muse.np.astype(close_window, "f64"), axis=0)

// Flat aliases for Expand/evo simplicity + ml_* compatibility
np_matmul(a, b)
ml_dot(x, y)   // shim → muse.np.dot
```

| Mechanism | Role |
|---|---|
| `MuseHost` namespace `np` (and optional alias `ndarray`) | Author-facing; Strat `this.np.*` via existing ClassStrategyLower/`OBJECT_NS` or flat resolve |
| `BuiltinSigs` | Every exposed op typed; introduce **`TNdArray`** (prefer over overloading meaningless `TMatrix` Dynamic blobs). Keep `TVector` = 1-D ndarray / packed vector for back-compat |
| Checker | Reject wrong arity/dtype early; promote scalar↔0-d with documented rules |
| `MuseHostLower` | Rewrite `muse.np.foo` → flat `np_foo` / existing shim **so JS/WASM keep HostABI / fast tables** |
| Parity with Haxe | Muse surface ⊆ Haxe `Np` facade; document Muse gaps as `UNSUPPORTED` list, never silent fallbacks |

**Language reality check:** MuseScript won’t get full Haxe overload resolution. Emulate numpy expressiveness with:
- fixed arities + optional trailing args (`axis`, `keepdims`) in BuiltinSigs `minArgs`,
- dedicated names where overloads collide (`np_sum` vs `np_sum_axis`),
- later sugar in parser only if needed (prefer builtins first — language changes are expensive across emitters).

**Strat / `this`:** same as `muse.math` / `muse.chart` — lower to flat builtins before emit.

---

### 2. All engines — eligibility matrix

For every Muse-visible op, tag one of: **N** native, **B** CALL_BUILTIN/host lib, **H** host_eval, **U** unsupported (whole-module fallback or compile error).

| Engine | NdArray ops (M1 scalar/vec reduce, matmul≤NxN) | Full broadcast ufuncs | Random | FFT |
|---|---|---|---|---|
| **Interp** (`TradeBuiltins` / `NpBuiltins.install`) | **N** (calls Haxe NdArray) | **N** | Deterministic seed API or **U** on fitness | Later / **U** fitness |
| **JS backend** | **B** via arity fast tables → `NpBuiltins` | **B** | Same | Same |
| **Bytecode VM** | Start **B** `CALL_BUILTIN`; promote small IND-like ops only after unboxed ABI design | Mostly **U** → Expand→interp until TNdArray stack slots | **U** | **U** |
| **WASM HostABI** | Literal-small / packed vec ops **N** (extend wat kernels like `vec_dot`); general ndarray **H** or **U** | **H**/ **U** until packed-buffer ABI | **U** | **U** |
| **NMA columnar** | Prefer bridge: columns already `GrowableVec` — ndarray optional for projection feature packs | Column kernels stay GrowableVec; don’t force NdArray into NmaEval hot switch | — | — |
| **Graal workers** | Same Haxe/JVM NdArray as host; WASM guest still HostABI-bound | Share Engine; no Dynamic memos | DetRng only | — |

**Determinism / fitness constraints:**
- Default dtype **f64**; casting to f32 on fitness paths requires explicit opt-in + parity exemption doc.
- `exp`/`log`/`pow` → **`DetMath`** on any cross-target fitness path (SPEC_BYTECODE_VM).
- Memo keys: canonicalize `(op, shape, dtype, seed, axis, tapeEpoch)` — no object identity of buffers.
- PIT: ndarray views over `Bar.data` / funds only see pre-joined aux; no I/O builtins.

**VM unboxed stack:** Do **not** stuff Dynamic matrices onto the unboxed stack. Options (decision D5): (a) keep ND results as heap handles in const/local pool with boxed ref opcode; (b) restrict VM-eligible ND to scalar outputs from ND kernels (mean of window → f64); (c) defer ND entirely from `--vm` until handle ABI exists. Recommendation: **(b) for M1–M2, design (a) in M3**.

---

### 3. Data bridge (zero-copy goals)

```
Bar / PanelFeed
  OHLCV + Bar.data aux
       │
       ├─► FloatSeries / GrowableVec (NMA, indicators) ──view──► NdArrayF64 (1-D, alias)
       ├─► WASM feature tape (sid≥7, field@SYM) ──view──► NdArray over linear memory / host mirror
       └─► Panel cross-section at bar t ──copy or strided view──► NdArray (n_sym × n_feat)
```

| Bridge | Zero-copy when | Copy barrier |
|---|---|---|
| GrowableVec → NdArray | Contiguous f64, full length or prefix | dtype change; non-1D reshape needing contiguous |
| FloatSeries alias | Owned TypedArray / Vector prefix | Growing ownership transfer |
| Feature tape | Slot is contiguous f64 run | After `memory.grow` / host mirror refresh |
| `ml_matrix` JSON blob | Never (legacy) | Always import via `asarray` copy |
| Boolean masks | Pack to Bool buffer | From Muse arrays of 0/1 floats |

**Explicit API:** `NdBridge.fromGrowable`, `fromFeatureSlot`, `panelFeatureMatrix(feed, fields, t)` with PIT docs.

---

### 4. Evo / honesty

| Question | Plan answer |
|---|---|
| Can genomes grow arbitrary `muse.np` graphs? | **No** for open numpy. **Closed palette** — `KNp` via `Variation.configureForNp` (`mean`/`dot`/`sum`, size-capped windows). Default off. Further ops (`NP_ZSCORE` / matmul) only with Expand+WASM tests |
| Host-authored strategies? | Full `muse.np` within engine eligibility; honesty via DSR/PBO still counts trials |
| Holes? | Holes fill with Scalar/Bool/Series as today; ndarray-typed holes are **out** until type lattice + Expand know `TNdArray` |
| Panel fitness | Cross-sectional ndarray ok on host/interp/JS; WASM remains literal/native subset; NMA stays `nma-unsupported` for panels |
| Serialization | Genomes remain MuseScript AST / NMA nodes — not pickled buffers. Any ND constants in Expand must be literal-small or feature refs |

**Anti-pattern:** evolving huge learned weight matrices inside genomes without size caps / ridge-style bounds (already `MAX_FIT_FEATURES` spirit).

---

### 5. Excessive tests — including engine matrix

**Layers:**
1. **Haxe unit / property** — shapes, strides, broadcast corners, view aliasing, promotion matrix, op-vs-numpy goldens.
2. **Python fixture gen** — `tools/ndarray_golden/gen_fixtures.py` using repo venv numpy; commit JSON; regenerate on demand.
3. **Muse parity** — same `.ms` snippet through interp / compile-js / (claimed) WASM / VM; bit-identical where DetMath domain, else documented ulp tolerance **only** for transcendentals.
4. **Fitness regression** — flagship / panel smoke: Sharpe unchanged when shimming `ml_*` → `np_*`.
5. **CI matrix** — Node `run.ps1 test`; JVM jar slice for NdArray+DetMath; WASM emit “no surprise host_eval” assertions like `TestMuseHost`.

**Acceptance example:** `TestNpMuseParity` runs `muse.np.dot` / `mean` / `matmul` corpus; WASM WAT for supported ops contains **no** unexpected `host_eval`; unsupported ops fail closed.

---

### B.7 Phased milestones (M-gates include engines)

#### M0 — Foundations (Haxe + Muse spine)
**Deliver:** F64 contiguous NdArray; shape/reshape/transpose-copy; creation; `asarray`; basic slice; `Broadcast.plan`; `Np` facade; **`NpBuiltins` + `muse.np` install + BuiltinSigs stubs**; `MlBuiltins.matrix` shimmed onto NdArray under the hood (kill Dynamic payload).  
**Tests:** creation/reshape goldens; RingBuffer-style indexing docs; Muse interp can call `muse.np.zeros` / `asarray` / `shape` getters.  
**Accept:** No Dynamic on NdArray public API; `node` tests green; MuseHostLower resolves `muse.np.*`.

#### M1 — Ufuncs + reductions + engine path A
**Deliver:** Broadcast ufuncs; reductions + axis; `where`; matmul/dot 1–2D; DetMath wired for exp/log; JS TypedArray backend; **JsBackend arity-table dispatch**; WASM: keep/extend **vec_*** path for 1-D; matrix/general broadcast = documented H/U.  
**Tests:** numpy golden suite ≥ N fixtures; Muse parity interp↔JS for scalar/1-D; DetParityDump touch if transcendentals used.  
**Accept:** `ml_dot`/`stat_mean`/`sci_*` shims call NdArray; bit-identical on arithmetic.

#### M2 — Views/strides + bridges + VM policy
**Deliver:** Real strides/views; boolean indexing; GrowableVec/FloatSeries/feature-tape bridges; Panel cross-section helper; **VM: scalar-returning ND CALL_BUILTIN** (or explicit U with Expand fallback).  
**Tests:** view aliasing mutation; tape zero-copy where claimed; panel feature matrix PIT test.  
**Accept:** NMA can optionally consume bridge without changing kind-switch hot path.

#### M3 — Muse “deep” surface + opacity hygiene + legacy purge
**Deliver:** Rich `muse.np` catalog (≥ numpy everyday 40–60 ops); `TNdArray` in checker; AnyNdArray sealed runtime tag; WASM packed-buffer ABI sketch for contiguous f64 ND (or firm U list); **`ml_matrix*` Dynamic gone**; optional evo palette NP_* gated nodes.  
**Tests:** engine matrix table CI job; WASM native-vs-escape snapshots; evo genome with NP_* (if enabled) DSR-safe.  
**Accept:** Author docs: “supported on {interp,js,vm?,wasm?}”.

#### M4 — Most-of-numpy layer cake + accel opt-in
**Deliver:** linalg (beyond matmul), stats/`nan*`, random (DetRng), polynomials subset; optional JVM BLAS; coverage matrix from Part C.  
**Accept:** Ranked “must” column green on Haxe+Muse interp/JS; WASM/VM per-op matrix published.

---

### B.8 Anti-goals
- No Dynamic soup on API or fitness memo paths.  
- No pretending full numpy in M0–M1.  
- No silent float32/64 drift on Sharpe/equity.  
- No open-world evolving of arbitrary np graphs.  
- No shipping Haxe-only NdArray claiming Muse ready.  
- No BLAS as default before parity harness exists.  
- No megamorphic virtual `execute()` trees for ufuncs on JVM (kind/op switch or monomorphic specialized kernels).

---

## Part C — Most-of-numpy (library on top)

### Layer cake

| Layer | Contents | Muse exposure | Muse fitness |
|---|---|---|---|
| L0 NdArray core | memory, ufuncs, reduce, index | `muse.np` core | f64 + DetMath |
| L1 scipy-lite stats | `nanmean`, percentiles, cov, corr → replace `stat_*` | flat + muse.np | yes |
| L2 linalg | solve, inv, svd/qr/eigh (sized), lstsq → supersede ridge/matrix | capped N | yes with caps |
| L3 random | Generator API on DetRng | seeded only | yes if DetRng |
| L4 polynomials | polyfit/val small degree | optional | caution |
| L5 fft | rfft/fft | defer | **never default fitness** |
| L6 einsum | subset path compiler | later | size-gated |
| L7 BLAS/SIMD | opt-in backends | transparent | only with parity gate |

### Ranked coverage (“most of numpy” for Muse)

| Tier | Examples | Muse? |
|---|---|---|
| **Must** | array/zeros/arange, reshape/T, broadcast ufuncs ±*/, reductions+axis, where, boolean mask, matmul/dot, astype, mean/std/sum, clip, concatenate/stack | Deep |
| **Should** | nan*, cov/corr, solve/inv (capped), lstsq/ridge, take/gather, unique (1-D), sort/argsort, DetRng random | Deep / caps |
| **Later** | einsum (common paths), svd/eigh, polynomials, histogram, gradient, trapz | Host-first |
| **Never (Muse product)** | full `numpy.polynomial`, sparse, ma as default, dtype=object, pickle protocol, endian toys, CUDA | Haxe-only curiosity at most |

### Preventing API rot
- Single `Np` facade owns names; `stat_*`/`sci_*`/`ml_*` become deprecated aliases.  
- Muse BuiltinSigs generated or checked against a table shared with Haxe (`NpCatalog.hx`).  
- Versioned “numpy emulation level” constant for docs/CI.

### Sequencing / staffing (solo / small team)
- **One person, serious:** M0–M1 ~ several weeks; M2–M3 longer (emitters dominate).  
- **Order:** Haxe F64 core → Muse install/sigs → JsBackend → goldens → bridges → WASM policy → VM scalars → L2 linalg → palette.  
- Parallelizable: fixture generator + WASM eligibility spreadsheet + docs.  
- Do **not** start einsum/FFT before M2 bridges and Muse parity.

---

## Part D — Decision points (pro/con)

### D1 — Dtype design

| | Compile-time `@:multiType` NdArray\<T\> (recommended) | Runtime DType enum + one class |
|---|---|---|
| **Pro** | Matches RingBuffer doctrine; JVM unboxed; V8 monomorphic buffers | Simple Muse boxing; one dispatch table |
| **Con** | More impl classes; Muse needs AnyNdArray existential | Hot-path megamorphic; fights JIT guide |
| **Verdict** | **Primary API = multiType; Muse opaque = closed enum of concretes** |

### D2 — Memory

| | Contiguous C-only first | Full strides from day one |
|---|---|---|
| **Pro** | Faster M0; fewer bugs | True numpy feel earlier |
| **Con** | Transpose/slice may copy | Harder goldens/views |
| **Verdict** | **C-contig M0–M1; strides M2** with API that doesn’t paint into a corner (`flags.c_contiguous`) |

### D3 — BLAS

| | Pure Haxe default | Bind JVM BLAS / WASM SIMD |
|---|---|---|
| **Pro** | Parity trivial; all targets | Speed on big matmul |
| **Con** | Slow large N | Parity + packaging hell |
| **Verdict** | **Pure default; BLAS opt-in behind parity gate, never silent** |

### D4 — Golden fixtures

| | Python numpy generator (recommended) | Hand fixtures only |
|---|---|---|
| **Pro** | Exhaustive broadcast/edge coverage; venv already has numpy | No Python in loop |
| **Con** | Tooling dependency | Won’t scale |
| **Verdict** | **Gen in CI optionally; commit goldens for hermetic Node/JVM tests** |

### D5 — Muse runtime representation of ND values

| | Sealed `AnyNdArray` handle (enum of F64/F32/…) | Stay on `{rows,cols,data}` Dynamic / Array |
|---|---|---|
| **Pro** | Type-safe; migrates checker to TNdArray | Zero engine work short-term |
| **Con** | Touch interp/JS/WASM/VM | Perpetuates Dynamic; WASM already rejects |
| **Verdict** | **AnyNdArray; shred Dynamic matrices by M3** |

### D6 — Genome growth of np ops

| | Closed palette NP_* only (recommended) | Open muse.np in Expand |
|---|---|---|
| **Pro** | Honesty, WASM-ability, memoability | Max novelty |
| **Con** | Author strategies richer than genomes | Undebugable search, host_eval explosion, PBO lies |
| **Verdict** | **Palette-gated; full muse.np for authored code** |

### D7 — Engine-binding depth for WASM

| | host_eval for ND until ABI | Early packed ND HostABI |
|---|---|---|
| **Pro** | Correctness first; ships M1 | Fitness speed |
| **Con** | Slow / escaped genomes | Large emitter surface |
| **Verdict** | **1-D vec native now; general ND host_eval/U until M3 ABI** |

### D8 — Namespace naming

| | `muse.np` (recommended) | Only flat `np_*` / keep `ml_*` |
|---|---|---|
| **Pro** | Matches muse.* story; Strat sugar | Minimal host change |
| **Con** | Lowering + docs | Feels bolted on |
| **Verdict** | **`muse.np` + flat aliases; `ml_*` shims** |

---

## Executive sequencing (one slide)

```
M0  NdArrayF64 + muse.np spine + kill matrix Dynamic guts
M1  ufuncs/reduce/matmul + JsBackend + goldens + DetMath
M2  strides/views + GrowableVec/tape/panel bridges + VM scalar policy
M3  deep muse.np catalog + TNdArray + WASM ABI or closed U-list + optional NP_* palette
M4  most-of-numpy layers + optional BLAS + published engine coverage matrix
```

**Success looks like:** a Haxe author writes numpy-shaped code without Dynamic; a MuseScript author writes `muse.np.*` with checker help; interp/JS match; WASM/VM tell the truth about support; evo stays honest; panels and projections reuse the same buffers instead of a third vector type.

---

## Tiny signature sketches (non-normative)

```haxe
// Haxe
class Np {
  public static function matmul(a:NdArray<Float>, b:NdArray<Float>):NdArray<Float>;
  public static function mean(a:ArrayLike<Float>, ?axis:Axis, ?keepdims:Bool):ArrayLike<Float>;
}

// Muse BuiltinSigs direction
// fun("np_matmul", [TNdArray, TNdArray], TNdArray);
// fun("np_mean", [TNdArray, TScalar], TNdArray, 1); // axis optional
```

No code beyond sketches; no commit.
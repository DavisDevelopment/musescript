package musescript.compile;

/**
 * Shared WAT runtime for strategy modules with exported linear memory.
 * Ports TradeBuiltins indicator semantics exactly (windowed / full-history).
 *
 * Memory layout:
 *   [0, RISE_BASE) — crossover / crossunder slots
 *   [RISE_BASE, VEC_SCRATCH_BASE) — rising / falling history rings
 *   [VEC_SCRATCH_BASE, FRAME_BASE) — ephemeral vector scratch for (ptr,len) lowers
 *   [FRAME_BASE, HEAP_BASE) — F2 shared variable frame (one f64 slot per
 *     boundary-crossing local — see StrategyWasmEmitter's `framedNames`);
 *     both native WASM code and the host_eval interp thunk read/write here
 *     directly, so a name crossing the native/interp boundary never needs
 *     the whole producing/consuming statement escalated to interp (F1)
 *   [HEAP_BASE, STATE_BYTES) — P4 class-instance struct storage: ONLY
 *     construct-once instances (ast/ConstructOnce.hx) that got natively
 *     lowered live here — one f64 per declared field, contiguous, at a
 *     FIXED compile-time offset (no runtime allocator: the set of
 *     construct-once instances is fully known at compile time, so this is
 *     static offset assignment exactly like FRAME_BASE, not a bump heap)
 *   [STATE_BYTES, …) — streaming OHLCV series (7 contiguous f64 arrays) when reset() is used
 *
 * Series ids: 0=open 1=high 2=low 3=close 4=volume 5=time 6=index
 */
class StrategyWasmRuntimeWat {
	public static inline var CROSS_SLOTS = 64;
	public static inline var RISE_SLOTS = 32;
	public static inline var RISE_HIST = 64;
	/** Cross: 64 slots × 16 bytes = 1024. Rise region starts at 1024. */
	public static inline var RISE_BASE = 1024;
	/** Per rising/falling slot: i32 length + 64 f64 = 4 + 512 = 516, rounded to 544. */
	public static inline var RISE_STRIDE = 544;
	/** End of rise rings; start of vector scratch. */
	public static inline var VEC_SCRATCH_BASE = RISE_BASE + RISE_SLOTS * RISE_STRIDE;
	/** Scratch arena for spilled array / window operands (512 f64s). */
	public static inline var VEC_SCRATCH_BYTES = 4096;
	/** F2 variable frame: start + slot count/size. */
	public static inline var FRAME_BASE = VEC_SCRATCH_BASE + VEC_SCRATCH_BYTES;
	public static inline var FRAME_SLOTS = 64;
	public static inline var FRAME_BYTES = FRAME_SLOTS * 8;
	/** P4 class-instance heap: fixed-offset f64 field storage (see class doc above). */
	public static inline var HEAP_BASE = FRAME_BASE + FRAME_BYTES;
	public static inline var HEAP_BYTES = 4096;
	public static inline var STATE_BYTES = HEAP_BASE + HEAP_BYTES;

	/** Globals + core helpers + all internalized indicators / crosses. */
	public static function helpers(crossSlots:Int, riseSlots:Int):String {
		var cs = crossSlots < 0 ? 0 : (crossSlots > CROSS_SLOTS ? CROSS_SLOTS : crossSlots);
		var rs = riseSlots < 0 ? 0 : (riseSlots > RISE_SLOTS ? RISE_SLOTS : riseSlots);
		// Emitted as many small chunks joined at runtime: a single huge interpolated
		// string makes the Haxe Python backend generate string concatenation nested
		// too deeply for the Python parser.
		var parts:Array<String> = [];
		parts.push('
  (global $$bar_count (mut i32) (i32.const 0))
  (global $$capacity (mut i32) (i32.const 0))
  (global $$open_base (mut i32) (i32.const 0))
  (global $$high_base (mut i32) (i32.const 0))
  (global $$low_base (mut i32) (i32.const 0))
  (global $$close_base (mut i32) (i32.const 0))
  (global $$volume_base (mut i32) (i32.const 0))
  (global $$time_base (mut i32) (i32.const 0))
  (global $$index_base (mut i32) (i32.const 0))
  (global $$feature_base (mut i32) (i32.const 0))
  (global $$feature_count (mut i32) (i32.const 0))
  (global $$cur_open (mut f64) (f64.const 0))
  (global $$cur_high (mut f64) (f64.const 0))
  (global $$cur_low (mut f64) (f64.const 0))
  (global $$cur_close (mut f64) (f64.const 0))
  (global $$cur_volume (mut f64) (f64.const 0))
  (global $$cur_time (mut f64) (f64.const 0))
  (global $$cur_index (mut f64) (f64.const 0))

  (func $$ensure_capacity (param $$need_bytes i32)
    (local $$need_pages i32) (local $$cur i32) (local $$delta i32)
    (if (i32.eqz (local.get $$need_bytes)) (then (return)))
    (local.set $$need_pages
      (i32.add (i32.shr_u (i32.sub (local.get $$need_bytes) (i32.const 1)) (i32.const 16)) (i32.const 1)))
    (local.set $$cur (memory.size))
    (if (i32.gt_u (local.get $$need_pages) (local.get $$cur))
      (then
        (local.set $$delta (i32.sub (local.get $$need_pages) (local.get $$cur)))
        (if (i32.eq (memory.grow (local.get $$delta)) (i32.const -1)) (then (unreachable)))))
  )

  (func $$series_base (param $$sid i32) (result i32)
    (if (result i32) (i32.eq (local.get $$sid) (i32.const 0))
      (then (global.get $$open_base))
      (else (if (result i32) (i32.eq (local.get $$sid) (i32.const 1))
        (then (global.get $$high_base))
        (else (if (result i32) (i32.eq (local.get $$sid) (i32.const 2))
          (then (global.get $$low_base))
          (else (if (result i32) (i32.eq (local.get $$sid) (i32.const 3))
            (then (global.get $$close_base))
            (else (if (result i32) (i32.eq (local.get $$sid) (i32.const 4))
              (then (global.get $$volume_base))
              (else (if (result i32) (i32.eq (local.get $$sid) (i32.const 5))
                (then (global.get $$time_base))
                (else (global.get $$index_base)))))))))))))
  )

  (func $$series_at (param $$sid i32) (param $$idx i32) (result f64)
    (f64.load (i32.add (call $$series_base (local.get $$sid))
      (i32.shl (local.get $$idx) (i32.const 3))))
  )

  (func $$lookback_ohlcv (param $$sid i32) (param $$n i32) (result f64)
    (local $$idx i32)
    (local.set $$idx (i32.sub (i32.sub (global.get $$bar_count) (i32.const 1)) (local.get $$n)))
    (if (i32.lt_s (local.get $$idx) (i32.const 0)) (then (return (f64.const nan))))
    (call $$series_at (local.get $$sid) (local.get $$idx))
  )

  (func $$feature_at (param $$fid i32) (result f64)
    (local $$idx i32) (local $$addr i32)
    (if (i32.or
          (i32.lt_s (local.get $$fid) (i32.const 0))
          (i32.ge_s (local.get $$fid) (global.get $$feature_count)))
      (then (return (f64.const nan))))
    (local.set $$idx (i32.sub (global.get $$bar_count) (i32.const 1)))
    (if (i32.or
          (i32.lt_s (local.get $$idx) (i32.const 0))
          (i32.ge_s (local.get $$idx) (global.get $$capacity)))
      (then (return (f64.const nan))))
    (local.set $$addr
      (i32.add (global.get $$feature_base)
        (i32.shl
          (i32.add (i32.mul (local.get $$fid) (global.get $$capacity)) (local.get $$idx))
          (i32.const 3))))
    (f64.load (local.get $$addr))
  )
');
		parts.push('
  (func $$store_bar (param $$idx i32) (param $$o f64) (param $$h f64) (param $$l f64)
      (param $$c f64) (param $$v f64) (param $$t f64) (param $$i f64)
    (f64.store (i32.add (global.get $$open_base) (i32.shl (local.get $$idx) (i32.const 3))) (local.get $$o))
    (f64.store (i32.add (global.get $$high_base) (i32.shl (local.get $$idx) (i32.const 3))) (local.get $$h))
    (f64.store (i32.add (global.get $$low_base) (i32.shl (local.get $$idx) (i32.const 3))) (local.get $$l))
    (f64.store (i32.add (global.get $$close_base) (i32.shl (local.get $$idx) (i32.const 3))) (local.get $$c))
    (f64.store (i32.add (global.get $$volume_base) (i32.shl (local.get $$idx) (i32.const 3))) (local.get $$v))
    (f64.store (i32.add (global.get $$time_base) (i32.shl (local.get $$idx) (i32.const 3))) (local.get $$t))
    (f64.store (i32.add (global.get $$index_base) (i32.shl (local.get $$idx) (i32.const 3))) (local.get $$i))
  )

  (func $$set_curs (param $$o f64) (param $$h f64) (param $$l f64)
      (param $$c f64) (param $$v f64) (param $$t f64) (param $$i f64)
    (global.set $$cur_open (local.get $$o))
    (global.set $$cur_high (local.get $$h))
    (global.set $$cur_low (local.get $$l))
    (global.set $$cur_close (local.get $$c))
    (global.set $$cur_volume (local.get $$v))
    (global.set $$cur_time (local.get $$t))
    (global.set $$cur_index (local.get $$i))
  )
');
		parts.push('
  (func $$init_state
    (local $$slot i32) (local $$addr i32) (local $$j i32)
    ;; Zero the cross/rise/vec-scratch/F2-frame region -- STOPS at HEAP_BASE,
    ;; deliberately NOT sweeping through STATE_BYTES: [HEAP_BASE, STATE_BYTES)
    ;; is P4 construct-once instance heap, whose fields are fully
    ;; (re-)initialized by their own run-once construct_once_init -- that
    ;; call already happens once per run (right after instantiation, before
    ;; this function is called via reset / configure_tape), so sweeping over
    ;; it here would just wipe out work already done, not do anything useful.
    (local.set $$j (i32.const 0))
    (block $$zdone
      (loop $$zloop
        (br_if $$zdone (i32.ge_u (local.get $$j) (i32.const __HEAP_BASE__)))
        (i32.store8 (local.get $$j) (i32.const 0))
        (local.set $$j (i32.add (local.get $$j) (i32.const 1)))
        (br $$zloop)))
    ;; cross slots ← NaN sentinel
    (local.set $$slot (i32.const 0))
    (block $$cdone
      (loop $$cloop
        (br_if $$cdone (i32.ge_u (local.get $$slot) (i32.const __CS__)))
        (local.set $$addr (i32.shl (local.get $$slot) (i32.const 4)))
        (f64.store (local.get $$addr) (f64.const nan))
        (f64.store (i32.add (local.get $$addr) (i32.const 8)) (f64.const nan))
        (local.set $$slot (i32.add (local.get $$slot) (i32.const 1)))
        (br $$cloop)))
  )

  (func $$layout_streaming (param $$cap i32)
    (local $$base i32) (local $$bytes i32)
    (local.set $$base (i32.const __STATE_BYTES__))
    (global.set $$open_base (local.get $$base))
    (local.set $$base (i32.add (local.get $$base) (i32.shl (local.get $$cap) (i32.const 3))))
    (global.set $$high_base (local.get $$base))
    (local.set $$base (i32.add (local.get $$base) (i32.shl (local.get $$cap) (i32.const 3))))
    (global.set $$low_base (local.get $$base))
    (local.set $$base (i32.add (local.get $$base) (i32.shl (local.get $$cap) (i32.const 3))))
    (global.set $$close_base (local.get $$base))
    (local.set $$base (i32.add (local.get $$base) (i32.shl (local.get $$cap) (i32.const 3))))
    (global.set $$volume_base (local.get $$base))
    (local.set $$base (i32.add (local.get $$base) (i32.shl (local.get $$cap) (i32.const 3))))
    (global.set $$time_base (local.get $$base))
    (local.set $$base (i32.add (local.get $$base) (i32.shl (local.get $$cap) (i32.const 3))))
    (global.set $$index_base (local.get $$base))
    (local.set $$base (i32.add (local.get $$base) (i32.shl (local.get $$cap) (i32.const 3))))
    (local.set $$bytes (local.get $$base))
    (call $$ensure_capacity (local.get $$bytes))
    (global.set $$capacity (local.get $$cap))
  )

  (func $$reset (param $$cap i32)
    (global.set $$bar_count (i32.const 0))
    (call $$init_state)
    (if (i32.le_s (local.get $$cap) (i32.const 0))
      (then (local.set $$cap (i32.const 1))))
    (call $$layout_streaming (local.get $$cap))
  )
  (export "reset" (func $$reset))
  (export "ensure_capacity" (func $$ensure_capacity))

  (func $$configure_tape
      (param $$ob i32) (param $$hb i32) (param $$lb i32) (param $$cb i32)
      (param $$vb i32) (param $$tb i32) (param $$ib i32) (param $$len i32)
    (call $$init_state)
    (global.set $$open_base (local.get $$ob))
    (global.set $$high_base (local.get $$hb))
    (global.set $$low_base (local.get $$lb))
    (global.set $$close_base (local.get $$cb))
    (global.set $$volume_base (local.get $$vb))
    (global.set $$time_base (local.get $$tb))
    (global.set $$index_base (local.get $$ib))
    (global.set $$capacity (local.get $$len))
    (global.set $$bar_count (i32.const 0))
  )
  (export "configure_tape" (func $$configure_tape))

  (func $$configure_features (param $$base i32) (param $$count i32)
    (global.set $$feature_base (local.get $$base))
    (global.set $$feature_count (local.get $$count))
  )
  (export "configure_features" (func $$configure_features))
');
		parts.push('
  (func $$sma (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$start i32) (local $$sum f64)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.lt_s (global.get $$bar_count) (local.get $$len)))
      (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$len)))
    (local.set $$i (local.get $$start))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$sum (f64.add (local.get $$sum) (call $$series_at (local.get $$sid) (local.get $$i))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$len)))
  )

  (func $$highest (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$start i32) (local $$v f64)
    (if (i32.eqz (global.get $$bar_count)) (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$len)))
    (if (i32.lt_s (local.get $$start) (i32.const 0)) (then (local.set $$start (i32.const 0))))
    (local.set $$v (call $$series_at (local.get $$sid) (local.get $$start)))
    (local.set $$i (i32.add (local.get $$start) (i32.const 1)))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$v (f64.max (local.get $$v) (call $$series_at (local.get $$sid) (local.get $$i))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$v)
  )

  (func $$lowest (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$start i32) (local $$v f64)
    (if (i32.eqz (global.get $$bar_count)) (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$len)))
    (if (i32.lt_s (local.get $$start) (i32.const 0)) (then (local.set $$start (i32.const 0))))
    (local.set $$v (call $$series_at (local.get $$sid) (local.get $$start)))
    (local.set $$i (i32.add (local.get $$start) (i32.const 1)))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$v (f64.min (local.get $$v) (call $$series_at (local.get $$sid) (local.get $$i))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$v)
  )

  (func $$change (param $$sid i32) (param $$n i32) (result f64)
    (local $$last i32)
    (if (i32.le_s (global.get $$bar_count) (local.get $$n)) (then (return (f64.const nan))))
    (local.set $$last (i32.sub (global.get $$bar_count) (i32.const 1)))
    (f64.sub (call $$series_at (local.get $$sid) (local.get $$last))
      (call $$series_at (local.get $$sid) (i32.sub (local.get $$last) (local.get $$n))))
  )
  (func $$mom (param $$sid i32) (param $$n i32) (result f64)
    (call $$change (local.get $$sid) (local.get $$n)))

  (func $$pct_change (param $$sid i32) (param $$n i32) (result f64)
    (local $$last i32) (local $$cur f64) (local $$prev f64)
    (if (i32.le_s (global.get $$bar_count) (local.get $$n)) (then (return (f64.const nan))))
    (local.set $$last (i32.sub (global.get $$bar_count) (i32.const 1)))
    (local.set $$cur (call $$series_at (local.get $$sid) (local.get $$last)))
    (local.set $$prev (call $$series_at (local.get $$sid) (i32.sub (local.get $$last) (local.get $$n))))
    (if (f64.eq (local.get $$prev) (f64.const 0)) (then (return (f64.const nan))))
    (f64.div (f64.sub (local.get $$cur) (local.get $$prev)) (local.get $$prev))
  )
  (func $$roc (param $$sid i32) (param $$n i32) (result f64)
    (f64.mul (call $$pct_change (local.get $$sid) (local.get $$n)) (f64.const 100)))
');
		parts.push('
  (func $$stdev (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$start i32) (local $$sum f64) (local $$mean f64) (local $$var f64) (local $$d f64)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.lt_s (global.get $$bar_count) (local.get $$len)))
      (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$len)))
    (local.set $$i (local.get $$start))
    (block $$sdone (loop $$sloop
      (br_if $$sdone (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$sum (f64.add (local.get $$sum) (call $$series_at (local.get $$sid) (local.get $$i))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$sloop)))
    (local.set $$mean (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$len))))
    (local.set $$i (local.get $$start))
    (block $$vdone (loop $$vloop
      (br_if $$vdone (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$d (f64.sub (call $$series_at (local.get $$sid) (local.get $$i)) (local.get $$mean)))
      (local.set $$var (f64.add (local.get $$var) (f64.mul (local.get $$d) (local.get $$d))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$vloop)))
    (f64.sqrt (f64.div (local.get $$var) (f64.convert_i32_s (local.get $$len))))
  )
');
		// Window-stat helpers stay in small chunks so the Haxe Python target
		// does not choke on one giant dollar-interpolated string.
		parts.push('
  (func $$stat_window_mean (param $$sid i32) (param $$len i32) (result f64)
    (local $$n i32) (local $$i i32) (local $$start i32) (local $$sum f64)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.eqz (global.get $$bar_count)))
      (then (return (f64.const nan))))
    (local.set $$n (local.get $$len))
    (if (i32.gt_s (local.get $$n) (global.get $$bar_count))
      (then (local.set $$n (global.get $$bar_count))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$n)))
    (local.set $$i (local.get $$start))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$sum (f64.add (local.get $$sum) (call $$series_at (local.get $$sid) (local.get $$i))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$n)))
  )
');
		parts.push('
  (func $$stat_window_var (param $$sid i32) (param $$len i32) (param $$sample i32) (result f64)
    (local $$n i32) (local $$i i32) (local $$start i32)
    (local $$mean f64) (local $$m2 f64) (local $$x f64) (local $$d f64) (local $$k f64)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.eqz (global.get $$bar_count)))
      (then (return (f64.const nan))))
    (local.set $$n (local.get $$len))
    (if (i32.gt_s (local.get $$n) (global.get $$bar_count))
      (then (local.set $$n (global.get $$bar_count))))
    (if (i32.and (local.get $$sample) (i32.lt_s (local.get $$n) (i32.const 2)))
      (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$n)))
    (local.set $$i (local.get $$start))
    (local.set $$k (f64.const 0))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$k (f64.add (local.get $$k) (f64.const 1)))
      (local.set $$x (call $$series_at (local.get $$sid) (local.get $$i)))
      (local.set $$d (f64.sub (local.get $$x) (local.get $$mean)))
      (local.set $$mean (f64.add (local.get $$mean) (f64.div (local.get $$d) (local.get $$k))))
      (local.set $$m2 (f64.add (local.get $$m2)
        (f64.mul (local.get $$d) (f64.sub (local.get $$x) (local.get $$mean)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (if (result f64) (local.get $$sample)
      (then (f64.div (local.get $$m2) (f64.convert_i32_s (i32.sub (local.get $$n) (i32.const 1)))))
      (else (f64.div (local.get $$m2) (f64.convert_i32_s (local.get $$n)))))
  )
');
		parts.push('
  (func $$stat_window_stdev (param $$sid i32) (param $$len i32) (param $$sample i32) (result f64)
    (f64.sqrt (call $$stat_window_var (local.get $$sid) (local.get $$len) (local.get $$sample)))
  )
');
		parts.push('
  (func $$stat_window_cov (param $$sida i32) (param $$sidb i32) (param $$len i32) (result f64)
    (local $$n i32) (local $$i i32) (local $$start i32)
    (local $$meanA f64) (local $$meanB f64) (local $$co f64)
    (local $$xa f64) (local $$xb f64) (local $$da f64) (local $$k f64)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.eqz (global.get $$bar_count)))
      (then (return (f64.const nan))))
    (local.set $$n (local.get $$len))
    (if (i32.gt_s (local.get $$n) (global.get $$bar_count))
      (then (local.set $$n (global.get $$bar_count))))
    (if (i32.lt_s (local.get $$n) (i32.const 2)) (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$n)))
    (local.set $$i (local.get $$start))
    (local.set $$k (f64.const 0))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$k (f64.add (local.get $$k) (f64.const 1)))
      (local.set $$xa (call $$series_at (local.get $$sida) (local.get $$i)))
      (local.set $$xb (call $$series_at (local.get $$sidb) (local.get $$i)))
      (local.set $$da (f64.sub (local.get $$xa) (local.get $$meanA)))
      (local.set $$meanA (f64.add (local.get $$meanA) (f64.div (local.get $$da) (local.get $$k))))
      (local.set $$meanB (f64.add (local.get $$meanB)
        (f64.div (f64.sub (local.get $$xb) (local.get $$meanB)) (local.get $$k))))
      (local.set $$co (f64.add (local.get $$co)
        (f64.mul (local.get $$da) (f64.sub (local.get $$xb) (local.get $$meanB)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$co) (f64.convert_i32_s (i32.sub (local.get $$n) (i32.const 1))))
  )
');
		parts.push('
  (func $$window_to_scratch (param $$sid i32) (param $$len i32) (param $$dst i32) (result i32)
    (local $$n i32) (local $$i i32) (local $$start i32) (local $$j i32)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.eqz (global.get $$bar_count)))
      (then (return (i32.const 0))))
    (local.set $$n (local.get $$len))
    (if (i32.gt_s (local.get $$n) (global.get $$bar_count))
      (then (local.set $$n (global.get $$bar_count))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$n)))
    (local.set $$i (local.get $$start))
    (local.set $$j (i32.const 0))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$j) (i32.const 3)))
        (call $$series_at (local.get $$sid) (local.get $$i)))
      (local.set $$j (i32.add (local.get $$j) (i32.const 1)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$n)
  )
');
		parts.push('
  (func $$vec_dot (param $$ba i32) (param $$la i32) (param $$bb i32) (param $$lb i32) (result f64)
    (local $$i i32) (local $$sum f64) (local $$xa f64) (local $$xb f64)
    (if (i32.or (i32.le_s (local.get $$la) (i32.const 0)) (i32.ne (local.get $$la) (local.get $$lb)))
      (then (return (f64.const nan))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$la)))
      (local.set $$xa (f64.load (i32.add (local.get $$ba) (i32.shl (local.get $$i) (i32.const 3)))))
      (local.set $$xb (f64.load (i32.add (local.get $$bb) (i32.shl (local.get $$i) (i32.const 3)))))
      (if (i32.or (f64.ne (local.get $$xa) (local.get $$xa)) (f64.ne (local.get $$xb) (local.get $$xb)))
        (then (return (f64.const nan))))
      (local.set $$sum (f64.add (local.get $$sum) (f64.mul (local.get $$xa) (local.get $$xb))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$sum)
  )
');
		parts.push('
  (func $$vec_mse (param $$ba i32) (param $$la i32) (param $$bb i32) (param $$lb i32) (result f64)
    (local $$i i32) (local $$sum f64) (local $$xa f64) (local $$xb f64) (local $$d f64)
    (if (i32.or (i32.le_s (local.get $$la) (i32.const 0)) (i32.ne (local.get $$la) (local.get $$lb)))
      (then (return (f64.const nan))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$la)))
      (local.set $$xa (f64.load (i32.add (local.get $$ba) (i32.shl (local.get $$i) (i32.const 3)))))
      (local.set $$xb (f64.load (i32.add (local.get $$bb) (i32.shl (local.get $$i) (i32.const 3)))))
      (if (i32.or (f64.ne (local.get $$xa) (local.get $$xa)) (f64.ne (local.get $$xb) (local.get $$xb)))
        (then (return (f64.const nan))))
      (local.set $$d (f64.sub (local.get $$xa) (local.get $$xb)))
      (local.set $$sum (f64.add (local.get $$sum) (f64.mul (local.get $$d) (local.get $$d))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$la)))
  )
');
		parts.push('
  (func $$vec_mae (param $$ba i32) (param $$la i32) (param $$bb i32) (param $$lb i32) (result f64)
    (local $$i i32) (local $$sum f64) (local $$xa f64) (local $$xb f64)
    (if (i32.or (i32.le_s (local.get $$la) (i32.const 0)) (i32.ne (local.get $$la) (local.get $$lb)))
      (then (return (f64.const nan))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$la)))
      (local.set $$xa (f64.load (i32.add (local.get $$ba) (i32.shl (local.get $$i) (i32.const 3)))))
      (local.set $$xb (f64.load (i32.add (local.get $$bb) (i32.shl (local.get $$i) (i32.const 3)))))
      (if (i32.or (f64.ne (local.get $$xa) (local.get $$xa)) (f64.ne (local.get $$xb) (local.get $$xb)))
        (then (return (f64.const nan))))
      (local.set $$sum (f64.add (local.get $$sum) (f64.abs (f64.sub (local.get $$xa) (local.get $$xb)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$la)))
  )
');
		parts.push('
  (func $$vec_mean (param $$base i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$sum f64)
    (if (i32.le_s (local.get $$len) (i32.const 0)) (then (return (f64.const nan))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$sum (f64.add (local.get $$sum)
        (f64.load (i32.add (local.get $$base) (i32.shl (local.get $$i) (i32.const 3))))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$len)))
  )
');
		parts.push('
  (func $$vec_var (param $$base i32) (param $$len i32) (param $$sample i32) (result f64)
    (local $$i i32) (local $$mean f64) (local $$m2 f64) (local $$x f64) (local $$d f64) (local $$k f64)
    (if (i32.le_s (local.get $$len) (i32.const 0)) (then (return (f64.const nan))))
    (if (i32.and (local.get $$sample) (i32.lt_s (local.get $$len) (i32.const 2)))
      (then (return (f64.const nan))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$k (f64.add (local.get $$k) (f64.const 1)))
      (local.set $$x (f64.load (i32.add (local.get $$base) (i32.shl (local.get $$i) (i32.const 3)))))
      (local.set $$d (f64.sub (local.get $$x) (local.get $$mean)))
      (local.set $$mean (f64.add (local.get $$mean) (f64.div (local.get $$d) (local.get $$k))))
      (local.set $$m2 (f64.add (local.get $$m2)
        (f64.mul (local.get $$d) (f64.sub (local.get $$x) (local.get $$mean)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (if (result f64) (local.get $$sample)
      (then (f64.div (local.get $$m2) (f64.convert_i32_s (i32.sub (local.get $$len) (i32.const 1)))))
      (else (f64.div (local.get $$m2) (f64.convert_i32_s (local.get $$len)))))
  )
');
		parts.push('
  (func $$vec_stdev (param $$base i32) (param $$len i32) (param $$sample i32) (result f64)
    (f64.sqrt (call $$vec_var (local.get $$base) (local.get $$len) (local.get $$sample)))
  )
');
		parts.push('
  (func $$vec_cov (param $$ba i32) (param $$la i32) (param $$bb i32) (param $$lb i32) (result f64)
    (local $$i i32) (local $$meanA f64) (local $$meanB f64) (local $$co f64)
    (local $$xa f64) (local $$xb f64) (local $$da f64) (local $$k f64)
    (if (i32.or (i32.ne (local.get $$la) (local.get $$lb)) (i32.lt_s (local.get $$la) (i32.const 2)))
      (then (return (f64.const nan))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$la)))
      (local.set $$k (f64.add (local.get $$k) (f64.const 1)))
      (local.set $$xa (f64.load (i32.add (local.get $$ba) (i32.shl (local.get $$i) (i32.const 3)))))
      (local.set $$xb (f64.load (i32.add (local.get $$bb) (i32.shl (local.get $$i) (i32.const 3)))))
      (local.set $$da (f64.sub (local.get $$xa) (local.get $$meanA)))
      (local.set $$meanA (f64.add (local.get $$meanA) (f64.div (local.get $$da) (local.get $$k))))
      (local.set $$meanB (f64.add (local.get $$meanB)
        (f64.div (f64.sub (local.get $$xb) (local.get $$meanB)) (local.get $$k))))
      (local.set $$co (f64.add (local.get $$co)
        (f64.mul (local.get $$da) (f64.sub (local.get $$xb) (local.get $$meanB)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$co) (f64.convert_i32_s (i32.sub (local.get $$la) (i32.const 1))))
  )
');
		parts.push('
  (func $$vec_corr (param $$ba i32) (param $$la i32) (param $$bb i32) (param $$lb i32) (result f64)
    (local $$sa f64) (local $$sb f64) (local $$den f64)
    (if (i32.ne (local.get $$la) (local.get $$lb)) (then (return (f64.const nan))))
    (local.set $$sa (call $$vec_stdev (local.get $$ba) (local.get $$la) (i32.const 1)))
    (local.set $$sb (call $$vec_stdev (local.get $$bb) (local.get $$lb) (i32.const 1)))
    (local.set $$den (f64.mul (local.get $$sa) (local.get $$sb)))
    (if (i32.or (f64.eq (local.get $$den) (f64.const 0)) (f64.ne (local.get $$den) (local.get $$den)))
      (then (return (f64.const nan))))
    (f64.div (call $$vec_cov (local.get $$ba) (local.get $$la) (local.get $$bb) (local.get $$lb)) (local.get $$den))
  )
');
		parts.push('
  (func $$vec_zscore (param $$src i32) (param $$len i32) (param $$dst i32) (result i32)
    (local $$i i32) (local $$mean f64) (local $$sd f64) (local $$x f64)
    (if (i32.le_s (local.get $$len) (i32.const 0)) (then (return (i32.const 0))))
    (local.set $$mean (call $$vec_mean (local.get $$src) (local.get $$len)))
    (local.set $$sd (call $$vec_stdev (local.get $$src) (local.get $$len) (i32.const 0)))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$x (f64.load (i32.add (local.get $$src) (i32.shl (local.get $$i) (i32.const 3)))))
      (if (f64.eq (local.get $$sd) (f64.const 0))
        (then (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3))) (f64.const 0)))
        (else (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3)))
          (f64.div (f64.sub (local.get $$x) (local.get $$mean)) (local.get $$sd)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$len)
  )
');
		parts.push('
  (func $$vec_cumsum (param $$src i32) (param $$len i32) (param $$dst i32) (result i32)
    (local $$i i32) (local $$sum f64)
    (if (i32.le_s (local.get $$len) (i32.const 0)) (then (return (i32.const 0))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$sum (f64.add (local.get $$sum)
        (f64.load (i32.add (local.get $$src) (i32.shl (local.get $$i) (i32.const 3))))))
      (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3))) (local.get $$sum))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$len)
  )
');
		parts.push('
  (func $$vec_diff (param $$src i32) (param $$len i32) (param $$dst i32) (result i32)
    (local $$i i32) (local $$out i32) (local $$a f64) (local $$b f64)
    (if (i32.le_s (local.get $$len) (i32.const 1)) (then (return (i32.const 0))))
    (local.set $$i (i32.const 1))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$a (f64.load (i32.add (local.get $$src)
        (i32.shl (i32.sub (local.get $$i) (i32.const 1)) (i32.const 3)))))
      (local.set $$b (f64.load (i32.add (local.get $$src) (i32.shl (local.get $$i) (i32.const 3)))))
      (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$out) (i32.const 3)))
        (f64.sub (local.get $$b) (local.get $$a)))
      (local.set $$out (i32.add (local.get $$out) (i32.const 1)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$out)
  )
');
		parts.push('
  (func $$vec_softmax (param $$src i32) (param $$len i32) (param $$dst i32) (result i32)
    (local $$i i32) (local $$max f64) (local $$x f64) (local $$e f64) (local $$sum f64)
    (if (i32.le_s (local.get $$len) (i32.const 0)) (then (return (i32.const 0))))
    (local.set $$max (f64.load (local.get $$src)))
    (if (f64.ne (local.get $$max) (local.get $$max)) (then (return (i32.const 0))))
    (local.set $$i (i32.const 1))
    (block $$mdone (loop $$mloop
      (br_if $$mdone (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$x (f64.load (i32.add (local.get $$src) (i32.shl (local.get $$i) (i32.const 3)))))
      (if (f64.ne (local.get $$x) (local.get $$x)) (then (return (i32.const 0))))
      (local.set $$max (f64.max (local.get $$max) (local.get $$x)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$mloop)))
    (local.set $$i (i32.const 0))
    (block $$edone (loop $$eloop
      (br_if $$edone (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$e (call $$exp (f64.sub
        (f64.load (i32.add (local.get $$src) (i32.shl (local.get $$i) (i32.const 3))))
        (local.get $$max))))
      (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3))) (local.get $$e))
      (local.set $$sum (f64.add (local.get $$sum) (local.get $$e)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$eloop)))
    (if (i32.or (f64.le (local.get $$sum) (f64.const 0)) (f64.ne (local.get $$sum) (local.get $$sum)))
      (then (return (i32.const 0))))
    (local.set $$i (i32.const 0))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3)))
        (f64.div (f64.load (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3))))
          (local.get $$sum)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$len)
  )
');
		parts.push('
  (func $$ml_sigmoid (param $$x f64) (result f64)
    (local $$z f64)
    (if (f64.ne (local.get $$x) (local.get $$x)) (then (return (f64.const nan))))
    (if (f64.ge (local.get $$x) (f64.const 0))
      (then
        (local.set $$z (call $$exp (f64.neg (local.get $$x))))
        (return (f64.div (f64.const 1) (f64.add (f64.const 1) (local.get $$z)))))
      (else
        (local.set $$z (call $$exp (local.get $$x)))
        (return (f64.div (local.get $$z) (f64.add (f64.const 1) (local.get $$z))))))
    (f64.const nan)
  )
');
		parts.push('
  (func $$vec_normalize (param $$src i32) (param $$len i32) (param $$dst i32) (result i32)
    (local $$i i32) (local $$lo f64) (local $$hi f64) (local $$span f64) (local $$x f64)
    (if (i32.le_s (local.get $$len) (i32.const 0)) (then (return (i32.const 0))))
    (local.set $$lo (f64.load (local.get $$src)))
    (local.set $$hi (local.get $$lo))
    (local.set $$i (i32.const 1))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$x (f64.load (i32.add (local.get $$src) (i32.shl (local.get $$i) (i32.const 3)))))
      (local.set $$lo (f64.min (local.get $$lo) (local.get $$x)))
      (local.set $$hi (f64.max (local.get $$hi) (local.get $$x)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.set $$span (f64.sub (local.get $$hi) (local.get $$lo)))
    (local.set $$i (i32.const 0))
    (block $$wdone (loop $$wloop
      (br_if $$wdone (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$x (f64.load (i32.add (local.get $$src) (i32.shl (local.get $$i) (i32.const 3)))))
      (if (f64.eq (local.get $$span) (f64.const 0))
        (then (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3))) (f64.const 0)))
        (else (f64.store (i32.add (local.get $$dst) (i32.shl (local.get $$i) (i32.const 3)))
          (f64.div (f64.sub (local.get $$x) (local.get $$lo)) (local.get $$span)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$wloop)))
    (local.get $$len)
  )
');
		parts.push('
  (func $$stat_window_corr (param $$sida i32) (param $$sidb i32) (param $$len i32) (result f64)
    (local $$n i32) (local $$i i32) (local $$start i32)
    (local $$meanA f64) (local $$meanB f64) (local $$co f64) (local $$m2a f64) (local $$m2b f64)
    (local $$xa f64) (local $$xb f64) (local $$da f64) (local $$db f64) (local $$k f64) (local $$den f64)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.eqz (global.get $$bar_count)))
      (then (return (f64.const nan))))
    (local.set $$n (local.get $$len))
    (if (i32.gt_s (local.get $$n) (global.get $$bar_count))
      (then (local.set $$n (global.get $$bar_count))))
    (if (i32.lt_s (local.get $$n) (i32.const 2)) (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$n)))
    (local.set $$i (local.get $$start))
    (local.set $$k (f64.const 0))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$k (f64.add (local.get $$k) (f64.const 1)))
      (local.set $$xa (call $$series_at (local.get $$sida) (local.get $$i)))
      (local.set $$xb (call $$series_at (local.get $$sidb) (local.get $$i)))
      (local.set $$da (f64.sub (local.get $$xa) (local.get $$meanA)))
      (local.set $$meanA (f64.add (local.get $$meanA) (f64.div (local.get $$da) (local.get $$k))))
      (local.set $$db (f64.sub (local.get $$xb) (local.get $$meanB)))
      (local.set $$meanB (f64.add (local.get $$meanB) (f64.div (local.get $$db) (local.get $$k))))
      (local.set $$co (f64.add (local.get $$co)
        (f64.mul (local.get $$da) (f64.sub (local.get $$xb) (local.get $$meanB)))))
      (local.set $$m2a (f64.add (local.get $$m2a)
        (f64.mul (local.get $$da) (f64.sub (local.get $$xa) (local.get $$meanA)))))
      (local.set $$m2b (f64.add (local.get $$m2b)
        (f64.mul (local.get $$db) (f64.sub (local.get $$xb) (local.get $$meanB)))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.set $$den (f64.sqrt (f64.mul (local.get $$m2a) (local.get $$m2b))))
    (if (f64.eq (local.get $$den) (f64.const 0)) (then (return (f64.const nan))))
    (f64.div (local.get $$co) (local.get $$den))
  )
');
		parts.push('
  (func $$wma (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$start i32) (local $$w i32) (local $$num f64) (local $$den f64)
    (if (i32.or (i32.le_s (local.get $$len) (i32.const 0))
          (i32.lt_s (global.get $$bar_count) (local.get $$len)))
      (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$len)))
    (local.set $$i (local.get $$start))
    (local.set $$w (i32.const 1))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$num (f64.add (local.get $$num)
        (f64.mul (call $$series_at (local.get $$sid) (local.get $$i)) (f64.convert_i32_s (local.get $$w)))))
      (local.set $$den (f64.add (local.get $$den) (f64.convert_i32_s (local.get $$w))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (local.set $$w (i32.add (local.get $$w) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$num) (local.get $$den))
  )
');
		parts.push('
  (func $$ema (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$k f64) (local $$omk f64) (local $$e f64)
    (if (i32.eqz (global.get $$bar_count)) (then (return (f64.const nan))))
    (local.set $$k (f64.div (f64.const 2) (f64.convert_i32_s (i32.add (local.get $$len) (i32.const 1)))))
    (local.set $$omk (f64.sub (f64.const 1) (local.get $$k)))
    (local.set $$e (call $$series_at (local.get $$sid) (i32.const 0)))
    (local.set $$i (i32.const 1))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$e (f64.add
        (f64.mul (call $$series_at (local.get $$sid) (local.get $$i)) (local.get $$k))
        (f64.mul (local.get $$e) (local.get $$omk))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$e)
  )

  (func $$rma (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$sum f64) (local $$alpha f64) (local $$oma f64) (local $$r f64)
    (if (i32.or (i32.eqz (global.get $$bar_count)) (i32.le_s (local.get $$len) (i32.const 0)))
      (then (return (f64.const nan))))
    (local.set $$alpha (f64.div (f64.const 1) (f64.convert_i32_s (local.get $$len))))
    (local.set $$oma (f64.sub (f64.const 1) (local.get $$alpha)))
    (if (i32.ge_s (global.get $$bar_count) (local.get $$len))
      (then
        (local.set $$i (i32.const 0))
        (block $$sdone (loop $$sloop
          (br_if $$sdone (i32.ge_s (local.get $$i) (local.get $$len)))
          (local.set $$sum (f64.add (local.get $$sum) (call $$series_at (local.get $$sid) (local.get $$i))))
          (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
          (br $$sloop)))
        (local.set $$r (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$len))))
        (local.set $$i (local.get $$len)))
      (else
        (local.set $$r (call $$series_at (local.get $$sid) (i32.const 0)))
        (local.set $$i (i32.const 1))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$r (f64.add
        (f64.mul (call $$series_at (local.get $$sid) (local.get $$i)) (local.get $$alpha))
        (f64.mul (local.get $$r) (local.get $$oma))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (local.get $$r)
  )
');
		parts.push('
  (func $$rsi (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$diff f64) (local $$gains f64) (local $$losses f64)
    (if (i32.lt_s (global.get $$bar_count) (i32.add (local.get $$len) (i32.const 1)))
      (then (return (f64.const nan))))
    (local.set $$i (i32.sub (global.get $$bar_count) (local.get $$len)))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$diff (f64.sub
        (call $$series_at (local.get $$sid) (local.get $$i))
        (call $$series_at (local.get $$sid) (i32.sub (local.get $$i) (i32.const 1)))))
      (local.set $$gains (f64.add (local.get $$gains) (f64.max (local.get $$diff) (f64.const 0))))
      (local.set $$losses (f64.add (local.get $$losses) (f64.max (f64.neg (local.get $$diff)) (f64.const 0))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (if (f64.eq (local.get $$losses) (f64.const 0)) (then (return (f64.const 100))))
    (f64.sub (f64.const 100)
      (f64.div (f64.const 100)
        (f64.add (f64.const 1) (f64.div (local.get $$gains) (local.get $$losses)))))
  )

  (func $$atr (param $$sid i32) (param $$len i32) (result f64)
    (local $$i i32) (local $$start i32) (local $$h f64) (local $$l f64) (local $$pc f64) (local $$tr f64) (local $$sum f64)
    (drop (local.get $$sid))
    (if (i32.lt_s (global.get $$bar_count) (i32.const 2)) (then (return (f64.const nan))))
    (if (i32.lt_s (i32.sub (global.get $$bar_count) (i32.const 1)) (local.get $$len))
      (then (return (f64.const nan))))
    (local.set $$start (i32.sub (global.get $$bar_count) (local.get $$len)))
    (local.set $$i (local.get $$start))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$h (call $$series_at (i32.const 1) (local.get $$i)))
      (local.set $$l (call $$series_at (i32.const 2) (local.get $$i)))
      (local.set $$pc (call $$series_at (i32.const 3) (i32.sub (local.get $$i) (i32.const 1))))
      (local.set $$tr (f64.max (f64.sub (local.get $$h) (local.get $$l))
        (f64.max (f64.abs (f64.sub (local.get $$h) (local.get $$pc)))
          (f64.abs (f64.sub (local.get $$l) (local.get $$pc))))))
      (local.set $$sum (f64.add (local.get $$sum) (local.get $$tr)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (f64.div (local.get $$sum) (f64.convert_i32_s (local.get $$len)))
  )

  (func $$vwap (result f64)
    (local $$i i32) (local $$tp f64) (local $$v f64) (local $$pv f64) (local $$vv f64)
    (if (i32.eqz (global.get $$bar_count)) (then (return (f64.const nan))))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (global.get $$bar_count)))
      (local.set $$tp (f64.div
        (f64.add (f64.add (call $$series_at (i32.const 1) (local.get $$i))
          (call $$series_at (i32.const 2) (local.get $$i)))
          (call $$series_at (i32.const 3) (local.get $$i)))
        (f64.const 3)))
      (local.set $$v (call $$series_at (i32.const 4) (local.get $$i)))
      (local.set $$pv (f64.add (local.get $$pv) (f64.mul (local.get $$tp) (local.get $$v))))
      (local.set $$vv (f64.add (local.get $$vv) (local.get $$v)))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (if (f64.eq (local.get $$vv) (f64.const 0)) (then (return (f64.const nan))))
    (f64.div (local.get $$pv) (local.get $$vv))
  )
');
		parts.push('
  (func $$crossover (param $$slot i32) (param $$a f64) (param $$b f64) (result i32)
    (local $$addr i32) (local $$pa f64) (local $$pb f64) (local $$r i32)
    (if (i32.or (f64.ne (local.get $$a) (local.get $$a)) (f64.ne (local.get $$b) (local.get $$b)))
      (then (return (i32.const 0))))
    (local.set $$addr (i32.shl (local.get $$slot) (i32.const 4)))
    (local.set $$pa (f64.load (local.get $$addr)))
    (local.set $$pb (f64.load (i32.add (local.get $$addr) (i32.const 8))))
    (if (i32.or (f64.ne (local.get $$pa) (local.get $$pa)) (f64.ne (local.get $$pb) (local.get $$pb)))
      (then
        (f64.store (local.get $$addr) (local.get $$a))
        (f64.store (i32.add (local.get $$addr) (i32.const 8)) (local.get $$b))
        (return (i32.const 0))))
    (local.set $$r (i32.and (f64.le (local.get $$pa) (local.get $$pb)) (f64.gt (local.get $$a) (local.get $$b))))
    (f64.store (local.get $$addr) (local.get $$a))
    (f64.store (i32.add (local.get $$addr) (i32.const 8)) (local.get $$b))
    (local.get $$r)
  )

  (func $$crossunder (param $$slot i32) (param $$a f64) (param $$b f64) (result i32)
    (local $$addr i32) (local $$pa f64) (local $$pb f64) (local $$r i32)
    (if (i32.or (f64.ne (local.get $$a) (local.get $$a)) (f64.ne (local.get $$b) (local.get $$b)))
      (then (return (i32.const 0))))
    (local.set $$addr (i32.shl (local.get $$slot) (i32.const 4)))
    (local.set $$pa (f64.load (local.get $$addr)))
    (local.set $$pb (f64.load (i32.add (local.get $$addr) (i32.const 8))))
    (if (i32.or (f64.ne (local.get $$pa) (local.get $$pa)) (f64.ne (local.get $$pb) (local.get $$pb)))
      (then
        (f64.store (local.get $$addr) (local.get $$a))
        (f64.store (i32.add (local.get $$addr) (i32.const 8)) (local.get $$b))
        (return (i32.const 0))))
    (local.set $$r (i32.and (f64.ge (local.get $$pa) (local.get $$pb)) (f64.lt (local.get $$a) (local.get $$b))))
    (f64.store (local.get $$addr) (local.get $$a))
    (f64.store (i32.add (local.get $$addr) (i32.const 8)) (local.get $$b))
    (local.get $$r)
  )
');
		parts.push('
  (func $$rising (param $$slot i32) (param $$x f64) (param $$n i32) (result i32)
    (local $$base i32) (local $$len i32) (local $$i i32) (local $$need i32)
      (local $$a f64) (local $$b f64)
    (if (i32.or (f64.ne (local.get $$x) (local.get $$x)) (i32.le_s (local.get $$n) (i32.const 0)))
      (then (return (i32.const 0))))
    (local.set $$base (i32.add (i32.const __RISE_BASE__) (i32.mul (local.get $$slot) (i32.const __RISE_STRIDE__))))
    (local.set $$len (i32.load (local.get $$base)))
    (local.set $$need (i32.add (local.get $$n) (i32.const 1)))
    (if (i32.gt_s (local.get $$need) (i32.const __RISE_HIST__))
      (then (local.set $$need (i32.const __RISE_HIST__))))
    ;; append
    (if (i32.ge_s (local.get $$len) (local.get $$need))
      (then
        ;; shift left by 1
        (local.set $$i (i32.const 0))
        (block $$sdone (loop $$sloop
          (br_if $$sdone (i32.ge_s (local.get $$i) (i32.sub (local.get $$len) (i32.const 1))))
          (f64.store (i32.add (i32.add (local.get $$base) (i32.const 8)) (i32.shl (local.get $$i) (i32.const 3)))
            (f64.load (i32.add (i32.add (local.get $$base) (i32.const 8))
              (i32.shl (i32.add (local.get $$i) (i32.const 1)) (i32.const 3)))))
          (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
          (br $$sloop)))
        (local.set $$len (i32.sub (local.get $$len) (i32.const 1)))))
    (f64.store (i32.add (i32.add (local.get $$base) (i32.const 8)) (i32.shl (local.get $$len) (i32.const 3)))
      (local.get $$x))
    (local.set $$len (i32.add (local.get $$len) (i32.const 1)))
    (i32.store (local.get $$base) (local.get $$len))
    (if (i32.lt_s (local.get $$len) (i32.add (local.get $$n) (i32.const 1)))
      (then (return (i32.const 0))))
    (local.set $$i (i32.sub (local.get $$len) (local.get $$n)))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$a (f64.load (i32.add (i32.add (local.get $$base) (i32.const 8))
        (i32.shl (i32.sub (local.get $$i) (i32.const 1)) (i32.const 3)))))
      (local.set $$b (f64.load (i32.add (i32.add (local.get $$base) (i32.const 8))
        (i32.shl (local.get $$i) (i32.const 3)))))
      (if (i32.or (f64.ne (local.get $$a) (local.get $$a)) (f64.ne (local.get $$b) (local.get $$b)))
        (then (return (i32.const 0))))
      (if (i32.eqz (f64.gt (local.get $$b) (local.get $$a))) (then (return (i32.const 0))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (i32.const 1)
  )
');
		parts.push('
  (func $$falling (param $$slot i32) (param $$x f64) (param $$n i32) (result i32)
    (local $$base i32) (local $$len i32) (local $$i i32) (local $$need i32)
      (local $$a f64) (local $$b f64)
    (if (i32.or (f64.ne (local.get $$x) (local.get $$x)) (i32.le_s (local.get $$n) (i32.const 0)))
      (then (return (i32.const 0))))
    (local.set $$base (i32.add (i32.const __RISE_BASE__) (i32.mul (local.get $$slot) (i32.const __RISE_STRIDE__))))
    (local.set $$len (i32.load (local.get $$base)))
    (local.set $$need (i32.add (local.get $$n) (i32.const 1)))
    (if (i32.gt_s (local.get $$need) (i32.const __RISE_HIST__))
      (then (local.set $$need (i32.const __RISE_HIST__))))
    (if (i32.ge_s (local.get $$len) (local.get $$need))
      (then
        (local.set $$i (i32.const 0))
        (block $$sdone (loop $$sloop
          (br_if $$sdone (i32.ge_s (local.get $$i) (i32.sub (local.get $$len) (i32.const 1))))
          (f64.store (i32.add (i32.add (local.get $$base) (i32.const 8)) (i32.shl (local.get $$i) (i32.const 3)))
            (f64.load (i32.add (i32.add (local.get $$base) (i32.const 8))
              (i32.shl (i32.add (local.get $$i) (i32.const 1)) (i32.const 3)))))
          (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
          (br $$sloop)))
        (local.set $$len (i32.sub (local.get $$len) (i32.const 1)))))
    (f64.store (i32.add (i32.add (local.get $$base) (i32.const 8)) (i32.shl (local.get $$len) (i32.const 3)))
      (local.get $$x))
    (local.set $$len (i32.add (local.get $$len) (i32.const 1)))
    (i32.store (local.get $$base) (local.get $$len))
    (if (i32.lt_s (local.get $$len) (i32.add (local.get $$n) (i32.const 1)))
      (then (return (i32.const 0))))
    (local.set $$i (i32.sub (local.get $$len) (local.get $$n)))
    (block $$done (loop $$loop
      (br_if $$done (i32.ge_s (local.get $$i) (local.get $$len)))
      (local.set $$a (f64.load (i32.add (i32.add (local.get $$base) (i32.const 8))
        (i32.shl (i32.sub (local.get $$i) (i32.const 1)) (i32.const 3)))))
      (local.set $$b (f64.load (i32.add (i32.add (local.get $$base) (i32.const 8))
        (i32.shl (local.get $$i) (i32.const 3)))))
      (if (i32.or (f64.ne (local.get $$a) (local.get $$a)) (f64.ne (local.get $$b) (local.get $$b)))
        (then (return (i32.const 0))))
      (if (i32.eqz (f64.lt (local.get $$b) (local.get $$a))) (then (return (i32.const 0))))
      (local.set $$i (i32.add (local.get $$i) (i32.const 1)))
      (br $$loop)))
    (i32.const 1)
  )
');
		return parts.join("")
			.split("__STATE_BYTES__").join(Std.string(STATE_BYTES))
			.split("__HEAP_BASE__").join(Std.string(HEAP_BASE))
			.split("__CS__").join(Std.string(cs))
			.split("__RISE_BASE__").join(Std.string(RISE_BASE))
			.split("__RISE_STRIDE__").join(Std.string(RISE_STRIDE))
			.split("__RISE_HIST__").join(Std.string(RISE_HIST));
	}
}

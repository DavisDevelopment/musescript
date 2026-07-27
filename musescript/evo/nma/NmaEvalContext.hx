package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import musescript.evo.nma.NmaIndicatorProvider; // for the ThrowingIndicatorProvider secondary type

/**
 * Immutable-per-evaluation inputs the `NmaEval` kind-switch reads: the bar tape (as per-field price
 * columns), external feature columns, resolved param values, the interned memo `epoch`, and the
 * `SInd` provider. One context = one (tape, params) evaluation; its `epoch.id` is what every node's
 * `evalEpoch` memo is validated against.
 *
 * Price columns are content-addressed by field name here (not on a node): every `SPrice("close")`
 * in a genome -- and across the whole population on the same tape -- shares ONE `close` column,
 * built once. That's the leaf-level slice of the population-wide memo-sharing idea (spec §6b); the
 * per-node `lastSeries` memo handles the recursive interior.
 *
 * «τριέτηρος ἑορτή· θεὸς ἐπανέρχεται οἴκαδε.»
 */
class NmaEvalContext {
	public final n:Int;
	public final epoch:NmaEpoch;
	public final params:Array<Float>;
	public final provider:NmaIndicatorProvider;

	final fields:Map<String, Array<Float>>;
	final features:Map<String, Array<Float>>;
	final priceColumns:Map<String, GrowableVec<Float>>;

	/**
	 * Generation-scoped content-addressed column memo (spec §6b): identical subtrees across the
	 * population share one `GrowableVec` per epoch. Null = disabled. Hits counted in `popMemoHits`.
	 */
	public var popMemo:Null<NmaColumnCache> = null;
	public var popMemoHits:Int = 0;

	/**
	 * Optional tape-scoped share for the price columns below. A price column is a pure function of
	 * (field, tape, n), so rebuilding one per context made every genome on a tape pay the same
	 * O(B) copy — the per-eval cost that `NmaFitness.tapeStateFor` exists to retire. Null keeps the
	 * old context-local behavior for callers with no tape identity to share under.
	 */
	public var sharedPriceColumns:Null<NmaColumnCache> = null;

	/**
	 * Unboxed OHLC + bar-index columns for the tape this context was prepared on, so the OrderSim
	 * loop in `NmaFitness.runPrepared` never touches `Bar`'s boxing dynamic field reads. Carries
	 * its own `bars` reference, which is what lets that loop confirm the columns describe the tape
	 * it was handed rather than a retained context's older one. Null for contexts built outside
	 * `NmaFitness.prepare` (tests, direct `NmaEval` use) -- the loop derives them itself then.
	 */
	public var barColumns:Null<NmaBarColumns> = null;

	/**
	 * Scratch digest for pop-memo keying (`NmaEval.popLookup`/`popStore`) and signal-memo words.
	 * One evaluation owns one context, and `colWords` finishes before any child eval re-enters, so
	 * reuse is safe and kills one `StructuralDigest` alloc per node on the barrier.
	 */
	public final scratchDigest:musescript.evo.StructuralDigest = new musescript.evo.StructuralDigest();

	/**
	 * `fields` maps each OHLCV-style name (`open`/`high`/`low`/`close`/`volume`, plus any derived
	 * name the caller pre-materializes like `hl2`) to its full per-bar array. `features` maps
	 * `KFeature` names to their columns. `params` is the genome's param values in index order
	 * (`KParam(idx)` -> `params[idx]`).
	 *
	 * «ῥεῦμα μέλιτος ῥεῖ· ἀθάνατοι πίνουσιν ἐκεῖ.»
	 */
	public function new(n:Int, epoch:NmaEpoch, fields:Map<String, Array<Float>>,
			?features:Map<String, Array<Float>>, ?params:Array<Float>, ?provider:NmaIndicatorProvider,
			?popMemo:NmaColumnCache) {
		this.n = n;
		this.epoch = epoch;
		this.fields = fields;
		this.features = features != null ? features : new Map();
		this.params = params != null ? params : [];
		this.provider = provider != null ? provider : new ThrowingIndicatorProvider();
		this.priceColumns = new Map();
		this.popMemo = popMemo;
	}

	/** Shared, memoized price column for `field` (built once per context). Unknown fields yield an
	 * all-`NaN` column of length `n` rather than throwing -- matches the engine treating an
	 * unresolved series name as `NaN` (see `IndicatorCache.currentSeriesValue`).
	 *
	 * «σκιὰ καὶ φῶς μιγέντα· διφυὴς θεὸς φαίνεται.»
	 */
	public function priceColumn(field:String):GrowableVec<Float> {
		var cached = priceColumns.get(field);
		if (cached != null) return cached;
		var sharedKey = sharedPriceColumns != null ? "price|" + field + "|" + n : null;
		if (sharedKey != null) {
			var shared = sharedPriceColumns.get(sharedKey);
			if (shared != null) {
				priceColumns.set(field, shared);
				return shared;
			}
		}
		var arr = fields.get(field);
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		if (arr != null) {
			for (i in 0...n) col.push(i < arr.length ? arr[i] : Math.NaN);
		} else {
			for (_ in 0...n) col.push(Math.NaN);
		}
		priceColumns.set(field, col);
		if (sharedKey != null) sharedPriceColumns.put(sharedKey, col);
		return col;
	}

	/** Feature column for `name`. Prefers an explicit features-map entry; otherwise lazily
	 * materializes multi-output / scalar extracts (`macd`/`bbands`/`stoch`/`fib_retracement`/
	 * `fourier_projection`) via `NmaFeatureHost`. Unknown / position-state expressions yield all-NaN.
	 *
	 * «σταφυλὴ πατεῖται· οἶνος μυστικὸς γίγνεται.»
	 */
	public function featureColumn(name:String):GrowableVec<Float> {
		var arr = features.get(name);
		if (arr != null) {
			var col = new GrowableVec<Float>(n > 0 ? n : 8);
			for (i in 0...n) col.push(i < arr.length ? arr[i] : Math.NaN);
			return col;
		}
		var hosted = NmaFeatureHost.columnFor(name, this);
		if (hosted != null) return hosted;
		var nan = new GrowableVec<Float>(n > 0 ? n : 8);
		for (_ in 0...n) nan.push(Math.NaN);
		return nan;
	}

	public inline function hasField(name:String):Bool {
		return fields.exists(name);
	}

	/** Raw OHLCV array for `name`, or empty if absent (NmaFeatureHost bar-feed). */
	public function fieldArray(name:String):Array<Float> {
		var a = fields.get(name);
		return a != null ? a : [];
	}
}

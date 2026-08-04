package musescript.evo;

/**
 * The tape-pure / sim-coupled distinction, over the enum genome forms.
 *
 * A TAPE-PURE expression is a function of the bars alone, so its value on every bar can be
 * computed before the simulation starts — that is what makes columnar evaluation, the population
 * column share, and column-swap attribution possible. A SIM-COUPLED expression reads state that
 * only exists once the simulation is running: the position-state `KFeature`s
 * `unrealized_pnl_pct` and `bars_in_trade`. Everything else in the grammar is tape-pure —
 * multi-output extracts (macd/bbands/stoch) and nested `SInd` included — and the series grammar
 * cannot name a feature at all, so no `SeriesNode` is ever coupled.
 *
 * Being coupled no longer costs a genome the fast path: `NmaPositionEval` evaluates the coupled
 * spine per bar inside the sim loop, over columns for its pure operands. It does still mean the
 * subtree has no standalone column, which is why column-swap attribution asks.
 */
class GenomeFeatures {
	/** Does any root of `g` read simulator state? */
	public static function isSimCoupled(g:StrategyGenome):Bool {
		return boolCoupled(g.entryLong) || boolCoupled(g.entryShort)
			|| boolCoupled(g.exitLong) || boolCoupled(g.exitShort)
			|| scalarCoupled(g.size);
	}

	public static function boolIsSimCoupled(n:BoolNode):Bool {
		return boolCoupled(n);
	}

	/** Position-state features read OrderSim — no standalone column exists for them. */
	public static inline function isPositionFeature(expr:String):Bool {
		return musescript.evo.nma.NmaFeatureHost.isPositionFeature(expr);
	}

	static function boolCoupled(n:BoolNode):Bool {
		return switch (n) {
			// BCross/BTrend take series, and no series can be coupled — hence the constant false.
			// BFeature is an opaque leaf: conservatively not treated as coupled here.
			case BCross(_, _, _) | BTrend(_, _, _) | BFeature(_): false;
			case BCmp(_, a, b): scalarCoupled(a) || scalarCoupled(b);
			case BAnd(a, b) | BOr(a, b): boolCoupled(a) || boolCoupled(b);
			case BNot(a) | BHole(a): boolCoupled(a);
		};
	}

	static function scalarCoupled(n:ScalarNode):Bool {
		return switch (n) {
			case KFeature(expr): isPositionFeature(expr);
			case KArith(_, a, b): scalarCoupled(a) || scalarCoupled(b);
			case KHole(inner): scalarCoupled(inner);
			case KSeries(_) | KLookback(_, _) | KConst(_) | KParam(_) | KNp(_, _, _, _) | KPd(_, _, _, _, _): false;
		};
	}

	// ---- feed-cadence gate for the generic (non-palette) indicator tier ----
	//
	// The compiled render short-circuits `&&`/`||`, so an indicator call in a RIGHT operand is
	// only fed on bars where control flow reaches it. Palette indicators (TradeBuiltins) are
	// pure reads over the growing series — cadence-free. Every OTHER ported indicator is a
	// stateful stream (`BarIndicatorCache`), so its output depends on exactly WHICH bars fed it.
	// The columnar provider feeds every bar; that is bit-exact iff the compiled path also feeds
	// every bar — true iff the indicator appears at least once in an always-evaluated position
	// (feeds dedupe per bar across call sites, keyed name:series:period).

	/** Indicator names TradeBuiltins serves statelessly (mirror of EngineIndicatorProvider). */
	static function isPaletteInd(name:String):Bool {
		return switch (name) {
			case "sma" | "ema" | "rsi" | "atr" | "wma" | "rma" | "stdev"
				| "highest" | "lowest" | "mom" | "roc" | "change": true;
			default: false;
		};
	}

	/**
	 * True when every generic-tier `SInd` in `g` is fed on EVERY bar by the compiled render —
	 * the soundness condition for hosting `g` on the columnar path. The three `when` heads are
	 * always evaluated (entryLong/entryShort/exitLong trees are left operands); right operands
	 * of `BAnd`/`BOr` are conditional; `size` only evaluates on entry-fire bars.
	 */
	public static function genericIndsAlwaysFed(g:StrategyGenome):Bool {
		var all = new Map<String, Bool>();
		var fed = new Map<String, Bool>();
		collectBool(g.entryLong, false, all, fed);
		collectBool(g.entryShort, false, all, fed);
		collectBool(g.exitLong, false, all, fed);
		collectBool(g.exitShort, true, all, fed); // right operand of the exit `||`
		collectScalar(g.size, true, all, fed);    // only evaluated when an entry fires
		for (key in all.keys())
			if (!fed.exists(key)) return false;
		return true;
	}

	static function collectBool(n:BoolNode, cond:Bool, all:Map<String, Bool>, fed:Map<String, Bool>):Void {
		switch (n) {
			case BAnd(a, b) | BOr(a, b):
				collectBool(a, cond, all, fed);
				collectBool(b, true, all, fed);
			case BNot(a) | BHole(a):
				collectBool(a, cond, all, fed);
			case BCross(_, a, b):
				collectSeries(a, cond, all, fed);
				collectSeries(b, cond, all, fed);
			case BTrend(_, s, _):
				collectSeries(s, cond, all, fed);
			case BCmp(_, a, b):
				collectScalar(a, cond, all, fed);
				collectScalar(b, cond, all, fed);
			case BFeature(_):
				// Opaque leaf: its indicators are computed inline on the Expand→compile path this
				// genome routes to (never the columnar feed this walk optimizes), so nothing to track.
		}
	}

	static function collectScalar(n:ScalarNode, cond:Bool, all:Map<String, Bool>, fed:Map<String, Bool>):Void {
		switch (n) {
			case KArith(_, a, b):
				collectScalar(a, cond, all, fed);
				collectScalar(b, cond, all, fed);
			case KSeries(s) | KLookback(s, _):
				collectSeries(s, cond, all, fed);
			case KNp(_, a, _, b):
				collectSeries(a, cond, all, fed);
				if (b != null) collectSeries(b, cond, all, fed);
			case KHole(inner):
				collectScalar(inner, cond, all, fed);
			case KConst(_) | KParam(_) | KFeature(_) | KPd(_, _, _, _, _):
		}
	}

	static function collectSeries(n:SeriesNode, cond:Bool, all:Map<String, Bool>, fed:Map<String, Bool>):Void {
		switch (n) {
			case SPrice(_):
			case SProj(_, _): // projection reference — not an indicator feature
			case SPanel(_, _, _, _): // panel-of — expand→interp/WASM, not GenomeFeatures ind set
			case SInd(name, field, window, src):
				if (src == null && !isPaletteInd(name)) {
					var key = name + "|" + field + "|" + window;
					all.set(key, true);
					if (!cond) fed.set(key, true);
				}
		}
	}
}

package musescript.evo;

/**
 * Shared probes for genomes the columnar NMA path cannot host: position-state `KFeature`s
 * (`unrealized_pnl_pct`, `bars_in_trade`). Multi-output extracts (macd/bbands/stoch) and nested
 * `SInd` are hosted on the columnar path.
 */
class GenomeFeatures {
	/** True when NMA must refuse the genome (position-state KFeature). */
	public static function genomeBlocksColumnar(g:StrategyGenome):Bool {
		return boolBlocks(g.entryLong) || boolBlocks(g.entryShort)
			|| boolBlocks(g.exitLong) || boolBlocks(g.exitShort)
			|| scalarBlocks(g.size);
	}

	/** @deprecated Prefer `genomeBlocksColumnar`. */
	public static inline function genomeHasKFeature(g:StrategyGenome):Bool {
		return genomeBlocksColumnar(g);
	}

	public static function boolHasFeature(n:BoolNode):Bool {
		return boolBlocks(n);
	}

	/** Position-state features need OrderSim — not hostable as signal columns. */
	public static inline function isPositionFeature(expr:String):Bool {
		return musescript.evo.nma.NmaFeatureHost.isPositionFeature(expr);
	}

	static function boolBlocks(n:BoolNode):Bool {
		return switch (n) {
			case BCross(_, a, b): seriesBlocks(a) || seriesBlocks(b);
			case BCmp(_, a, b): scalarBlocks(a) || scalarBlocks(b);
			case BTrend(_, s, _): seriesBlocks(s);
			case BAnd(a, b) | BOr(a, b): boolBlocks(a) || boolBlocks(b);
			case BNot(a) | BHole(a): boolBlocks(a);
		};
	}

	static function scalarBlocks(n:ScalarNode):Bool {
		return switch (n) {
			case KFeature(expr): isPositionFeature(expr);
			case KArith(_, a, b): scalarBlocks(a) || scalarBlocks(b);
			case KSeries(s) | KLookback(s, _): seriesBlocks(s);
			case KHole(inner): scalarBlocks(inner);
			case KConst(_) | KParam(_): false;
		};
	}

	/** Nested `SInd` is hostable — recurse only to catch a blocked child (none in series grammar). */
	static function seriesBlocks(n:SeriesNode):Bool {
		return switch (n) {
			case SPrice(_): false;
			case SInd(_, _, _, src): src != null ? seriesBlocks(src) : false;
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
		}
	}

	static function collectScalar(n:ScalarNode, cond:Bool, all:Map<String, Bool>, fed:Map<String, Bool>):Void {
		switch (n) {
			case KArith(_, a, b):
				collectScalar(a, cond, all, fed);
				collectScalar(b, cond, all, fed);
			case KSeries(s) | KLookback(s, _):
				collectSeries(s, cond, all, fed);
			case KHole(inner):
				collectScalar(inner, cond, all, fed);
			case KConst(_) | KParam(_) | KFeature(_):
		}
	}

	static function collectSeries(n:SeriesNode, cond:Bool, all:Map<String, Bool>, fed:Map<String, Bool>):Void {
		switch (n) {
			case SPrice(_):
			case SInd(name, field, window, src):
				if (src == null && !isPaletteInd(name)) {
					var key = name + "|" + field + "|" + window;
					all.set(key, true);
					if (!cond) fed.set(key, true);
				}
		}
	}
}

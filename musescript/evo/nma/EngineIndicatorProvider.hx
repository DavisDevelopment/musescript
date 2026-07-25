package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import musescript.harness.HarnessContext;
import musescript.builtins.TradeBuiltins;
import musescript.indicators.IndicatorRegistry;
import musescript.types.MuseType;
import musescript.evo.nma.NmaSeries;

/**
 * Engine-backed `SInd` provider -- parity WITH THE COMPILED GENOME PATH BY CONSTRUCTION.
 *
 * Two tiers, both bit-exact with what Expand→compile would run:
 *
 *  1. The evo-palette dozen (`sma`/`ema`/`rsi`/...) call the same `TradeBuiltins` entries the
 *     compiled program calls, fed by the same growing-prefix series discipline.
 *  2. EVERY OTHER ported indicator drives its own `IndicatorSpec.eval` closure — the exact
 *     closure `WickraBuiltins.install` wires into the interp/JS dispatch — against a per-bar
 *     `currentBar` + growing series, i.e. the same per-bar protocol `BacktestEngine.run`
 *     provides. This is what lets the columnar path host the full corpus-seeded population
 *     (123+ indicators) instead of ~10% of it; before this tier, ~90% of `--nma` pop scoring
 *     fell through to a per-genome Expand→parse→compile (measured ~9.5 ms CPU per eval).
 *
 * The generic tier requires REAL bar times (`times`): session/day-of-week indicators read
 * `bar.time`, and feeding a synthetic timestamp would be a silent parity break. A provider
 * built without times refuses (throws), which lands the genome on the compiled path — honest
 * fallback, never wrong columns.
 *
 * JIT shape (guide §3): field names/data are parallel arrays resolved once at construction —
 * the per-bar loop is indexed, never `Map.keys()`. Growing prefixes stay `Array<Float>` because
 * `HarnessContext.series` / `TradeBuiltins.resolveSeries` require that type for bit-exact parity.
 *
 * «κρητὴρ κεράννυται· ὕδωρ καὶ οἶνος μιγέντα.»
 */
class EngineIndicatorProvider implements NmaIndicatorProvider {
	final fieldNames:Array<String>;
	final fieldData:Array<Array<Float>>;
	final columnCache:Null<NmaColumnCache>;
	final times:Null<Array<Float>>;
	// OHLCV indices into fieldNames/fieldData, resolved once (-1 = absent → NaN on the bar).
	final iOpen:Int;
	final iHigh:Int;
	final iLow:Int;
	final iClose:Int;
	final iVolume:Int;

	public function new(fields:Map<String, Array<Float>>, ?columnCache:NmaColumnCache,
			?times:Array<Float>) {
		var names = new Array<String>();
		var data = new Array<Array<Float>>();
		for (k => v in fields) {
			names.push(k);
			data.push(v);
		}
		this.fieldNames = names;
		this.fieldData = data;
		this.columnCache = columnCache;
		this.times = times;
		this.iOpen = names.indexOf("open");
		this.iHigh = names.indexOf("high");
		this.iLow = names.indexOf("low");
		this.iClose = names.indexOf("close");
		this.iVolume = names.indexOf("volume");
	}

	public function seriesFor(node:NmaSInd, ctx:NmaEvalContext):GrowableVec<Float> {
		// Nested palette SInd: Expand emits `ema(sma("close",2), 3)` — the outer builtin receives a
		// Float each bar, and TradeBuiltins.resolveSeries treats non-String/non-Array src as
		// close-history sugar. So the compiled path IGNORES the nested src for the evo dozen.
		// Match that quirk so NMA hosts nested genomes without diverging from Fitness.evaluate.
		if (node.src != null && isPaletteName(node.name)) {
			var flat = new NmaSInd(node.name, node.field, node.window, null);
			return seriesFor(flat, ctx);
		}

		var srcCol:Null<GrowableVec<Float>> = null;
		var cacheKey:String;
		if (node.src != null) {
			srcCol = NmaEval.evalSeries(node.src, ctx);
			var srcKey = node.src.structuralKey;
			if (srcKey == null) {
				srcKey = NmaCanonical.seriesStructuralKey(node.src);
				node.src.structuralKey = srcKey;
			}
			cacheKey = node.name + "|src:" + srcKey + "|" + node.window;
		} else {
			cacheKey = node.name + "|" + node.field + "|" + node.window;
		}
		if (columnCache != null) {
			var hit = columnCache.get(cacheKey);
			if (hit != null) return hit;
		}

		var col = srcCol != null
			? nestedColumn(node, ctx, srcCol)
			: (isPaletteName(node.name) ? paletteColumn(node, ctx) : genericColumn(node, ctx));
		if (columnCache != null) columnCache.put(cacheKey, col);
		return col;
	}

	static inline var SRC_NAME = "__nma_src";

	/**
	 * Nested `SInd(name, field, window, src)`: evaluate `src` to a full column, then feed the
	 * indicator a growing prefix of that column under a synthetic series name — same cadence as
	 * Expand's `name(srcExpr, window)` over a computed series.
	 */
	function nestedColumn(node:NmaSInd, ctx:NmaEvalContext, srcCol:GrowableVec<Float>):GrowableVec<Float> {
		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var h = new HarnessContext();
		var nFields = fieldNames.length;
		var growing = new Array<Array<Float>>();
		for (fi in 0...nFields) {
			var g = new Array<Float>();
			growing.push(g);
			h.series.set(fieldNames[fi], g);
		}
		var srcGrow = new Array<Float>();
		h.series.set(SRC_NAME, srcGrow);
		var usePalette = isPaletteName(node.name);
		var spec = usePalette ? null : IndicatorRegistry.get(node.name);
		if (!usePalette) {
			if (spec == null) throw 'EngineIndicatorProvider: unknown indicator "${node.name}"';
			if (!spec.ret.match(TScalar))
				throw 'EngineIndicatorProvider: indicator "${node.name}" has non-scalar output';
			if (times == null)
				throw 'EngineIndicatorProvider: indicator "${node.name}" needs real bar times';
		}
		var args:Array<Dynamic> = [SRC_NAME, node.window];
		var ts = times;

		for (i in 0...n) {
			for (fi in 0...nFields) {
				var full = fieldData[fi];
				growing[fi].push(i < full.length ? full[i] : Math.NaN);
			}
			srcGrow.push(srcCol.at(i));
			if (usePalette) {
				col.push(callIndicator(node.name, h, SRC_NAME, node.window));
			} else {
				h.currentBar = {
					open: at(iOpen, i), high: at(iHigh, i), low: at(iLow, i),
					close: at(iClose, i), volume: at(iVolume, i),
					time: ts != null && i < ts.length ? ts[i] : Math.NaN,
					index: i
				};
				var v:Dynamic = spec.eval(h, args);
				col.push(v == null ? Math.NaN : (v : Float));
			}
		}
		return col;
	}

	static inline function isPaletteName(name:String):Bool {
		return switch (name) {
			case "sma" | "ema" | "rsi" | "atr" | "wma" | "rma" | "stdev"
				| "highest" | "lowest" | "mom" | "roc" | "change": true;
			default: false;
		};
	}

	/** Evo-palette dozen: direct `TradeBuiltins` calls over growing prefixes (original tier). */
	function paletteColumn(node:NmaSInd, ctx:NmaEvalContext):GrowableVec<Float> {
		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var h = new HarnessContext();
		var nFields = fieldNames.length;
		var growing = new Array<Array<Float>>();
		for (fi in 0...nFields) {
			var g = new Array<Float>();
			growing.push(g);
			h.series.set(fieldNames[fi], g);
		}

		for (i in 0...n) {
			for (fi in 0...nFields) {
				var full = fieldData[fi];
				growing[fi].push(i < full.length ? full[i] : Math.NaN);
			}
			col.push(callIndicator(node.name, h, node.field, node.window));
		}
		return col;
	}

	/**
	 * Every other ported indicator: drive its `IndicatorSpec.eval` — the same closure the
	 * compiled program dispatches through — with the same per-bar protocol the backtest engine
	 * provides (`currentBar` set, growing series appended, one feed per bar). Streaming state
	 * lives in `h.barIndicators` exactly as in a real run, so warmup NaNs, null-holds, and
	 * window semantics are the indicator's own.
	 */
	function genericColumn(node:NmaSInd, ctx:NmaEvalContext):GrowableVec<Float> {
		var spec = IndicatorRegistry.get(node.name);
		if (spec == null)
			throw 'EngineIndicatorProvider: unknown indicator "${node.name}"';
		if (!spec.ret.match(TScalar))
			throw 'EngineIndicatorProvider: indicator "${node.name}" has non-scalar output -- '
				+ 'not hostable as a single column';
		var ts = times;
		if (ts == null)
			throw 'EngineIndicatorProvider: indicator "${node.name}" needs real bar times '
				+ '(session/time-of-day indicators read bar.time); provider built without times';

		var n = ctx.n;
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var h = new HarnessContext();
		var nFields = fieldNames.length;
		var growing = new Array<Array<Float>>();
		for (fi in 0...nFields) {
			var g = new Array<Float>();
			growing.push(g);
			h.series.set(fieldNames[fi], g);
		}
		var args:Array<Dynamic> = [node.field, node.window];

		for (i in 0...n) {
			for (fi in 0...nFields) {
				var full = fieldData[fi];
				growing[fi].push(i < full.length ? full[i] : Math.NaN);
			}
			h.currentBar = {
				open: at(iOpen, i), high: at(iHigh, i), low: at(iLow, i),
				close: at(iClose, i), volume: at(iVolume, i),
				time: i < ts.length ? ts[i] : Math.NaN,
				index: i
			};
			var v:Dynamic = spec.eval(h, args);
			col.push(v == null ? Math.NaN : (v : Float));
		}
		return col;
	}

	inline function at(fi:Int, i:Int):Float {
		if (fi < 0) return Math.NaN;
		var a = fieldData[fi];
		return i < a.length ? a[i] : Math.NaN;
	}

	static function callIndicator(name:String, h:HarnessContext, field:String, window:Int):Float {
		return switch (name) {
			case "sma": TradeBuiltins.sma(h, field, window);
			case "ema": TradeBuiltins.ema(h, field, window);
			case "rsi": TradeBuiltins.rsi(h, field, window);
			case "atr": TradeBuiltins.atr(h, field, window);
			case "wma": TradeBuiltins.wma(h, field, window);
			case "rma": TradeBuiltins.rma(h, field, window);
			case "stdev": TradeBuiltins.stdev(h, field, window);
			case "highest": TradeBuiltins.highest(h, field, window);
			case "lowest": TradeBuiltins.lowest(h, field, window);
			case "mom": TradeBuiltins.mom(h, field, window);
			case "roc": TradeBuiltins.roc(h, field, window);
			case "change": TradeBuiltins.change(h, field, window);
			default: throw 'EngineIndicatorProvider: "$name" is not a palette indicator';
		};
	}
}

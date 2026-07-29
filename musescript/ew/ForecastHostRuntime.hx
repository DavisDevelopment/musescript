package musescript.ew;

import musescript.harness.Bar;
import musescript.ew.EwForecastHost.EwCountMass;
import musescript.ew.auction.AuctionForecastHost;
import musescript.indicators.geom.SwingGraphStack;

/**
 * Browser / desktop Forecast Panel host facade (Initiative 2.1).
 *
 * Pure Haxe→JS module (`@:expose`, NO Sys / no hxnodejs) — same shape as
 * `MuseRuntime` / `PineConvert`. `haxe build-forecast-host-runtime.hxml` emits
 * `build/js/forecast-host-runtime.js` exposing `ForecastHostRuntime`.
 *
 * Determinism contract: hosts use `DetRng`/`DetMath` (regime) or pure IEEE math
 * (auction / lattice). Same seed+bars → identical cloud bits on JVM and JS;
 * see `ForecastHostParityDump` + `tools/forecast_host_parity_ci.*`.
 *
 * JS API:
 *   ForecastHostRuntime.kinds()
 *   ForecastHostRuntime.forecast(kind, bars, opts)
 *     kind: "regime" | "auction" | "lattice"
 *     bars: [{open,high,low,close,volume?,time?}, ...]
 *     opts: { seed, horizon, window, steps, burnIn, nPaths, k, persist,
 *             fineThreshold, queryAt, includeCounts, countK,
 *             includeBins (auction), includeEnsemble (lattice) }
 *   → { ok, kind, clouds:[{t,...cloud}], counts?:[{t,masses:[...]}],
 *       ensembles?:[{t,bands:[...]}], state? }
 */
@:expose("ForecastHostRuntime")
class ForecastHostRuntime {
	/** No-op entry; module exists to `@:expose` its static API to JS. */
	static function main() {}

	public static function kinds():Array<String> {
		return ["regime", "auction", "lattice"];
	}

	/**
	 * Run a forecast host over `bars` and return cloud(s) as plain JS objects.
	 * Never throws across the JS boundary — failures are `{ ok:false, error }`.
	 */
	public static function forecast(kind:String, ?bars:Array<Dynamic>, ?opts:Dynamic):Dynamic {
		try {
			var k = kind == null ? "" : StringTools.trim(kind).toLowerCase();
			var typed = toBars(bars);
			if (typed.length == 0)
				return err("bars required (non-empty OHLCV array)");

			return switch (k) {
				case "regime": runRegime(typed, opts);
				case "auction": runAuction(typed, opts);
				case "lattice": runLattice(typed, opts);
				default: err('unknown host kind "$kind" (expected regime|auction|lattice)');
			};
		} catch (e:Dynamic) {
			return err(Std.string(e));
		}
	}

	static function runRegime(bars:Array<Bar>, opts:Dynamic):Dynamic {
		var seed = optInt(opts, "seed", 0);
		var K = optInt(opts, "k", 2);
		var horizon = optInt(opts, "horizon", 20);
		var window = optInt(opts, "window", 160);
		var steps = optInt(opts, "steps", 1500);
		var burnIn = optInt(opts, "burnIn", 500);
		var nPaths = optInt(opts, "nPaths", 200);
		var persist = optFloat(opts, "persist", 0.97);
		var host = new RegimeForecastHost(seed, K, horizon, window, steps, burnIn, nPaths, persist);
		return finish(host, "regime", bars, opts);
	}

	static function runAuction(bars:Array<Bar>, opts:Dynamic):Dynamic {
		var window = optInt(opts, "window", 20);
		var bins = optInt(opts, "bins", 50);
		var valueAreaPct = optFloat(opts, "valueAreaPct", 0.70);
		var horizon = optInt(opts, "horizon", 5);
		var host = new AuctionForecastHost(window, bins, valueAreaPct, horizon);
		var out = finish(host, "auction", bars, opts);
		if (Reflect.field(out, "ok") == true) {
			var levels = host.lastProfile();
			var state:Dynamic = {
				regime: host.lastRegimeLabel(),
				poc: levels != null ? levels.poc : Math.NaN,
				vaHigh: levels != null ? levels.vaHigh : Math.NaN,
				vaLow: levels != null ? levels.vaLow : Math.NaN,
				valueAreaVolFrac: levels != null ? levels.valueAreaVolFrac : Math.NaN
			};
			// Default on: glcharts 2.4 hist needs mid-bin price+vol.
			if (optBool(opts, "includeBins", true)) {
				var histBins = host.lastHistogramBins();
				var binArr:Array<Dynamic> = [];
				for (b in histBins) binArr.push({ price: b.price, vol: b.vol });
				Reflect.setField(state, "bins", binArr);
			}
			Reflect.setField(out, "state", state);
		}
		return out;
	}

	static function runLattice(bars:Array<Bar>, opts:Dynamic):Dynamic {
		var topK = optInt(opts, "k", 5);
		var fine = optFloat(opts, "fineThreshold", 0.05);
		var stack = new SwingGraphStack(fine);
		var host = LatticeForecastHost.withStack(stack, null, topK);
		return finish(host, "lattice", bars, opts);
	}

	static function finish(host:EwForecastHost, kind:String, bars:Array<Bar>, opts:Dynamic):Dynamic {
		for (i in 0...bars.length) host.onBar(bars[i], i);

		var anchors = queryAnchors(bars.length, opts);
		var includeCounts = optBool(opts, "includeCounts", true);
		var countK = optInt(opts, "countK", 5);
		var includeEnsemble = optBool(opts, "includeEnsemble", kind == "lattice");

		var clouds:Array<Dynamic> = [];
		var countsOut:Array<Dynamic> = [];
		var ensemblesOut:Array<Dynamic> = [];
		var latticeHost:Null<LatticeForecastHost> = Std.isOfType(host, LatticeForecastHost)
			? cast host
			: null;

		for (t in anchors) {
			var c = host.cloudAt(t);
			clouds.push(cloudObj(t, c));
			var masses:Array<EwCountMass> = null;
			if (includeCounts) {
				masses = host.topCounts(t, countK);
				countsOut.push({ t: t, masses: massesArr(masses) });
			}
			if (includeEnsemble && latticeHost != null) {
				if (masses == null) masses = host.topCounts(t, countK);
				ensemblesOut.push({ t: t, bands: ensembleArr(latticeHost, t, masses) });
			}
		}

		var out:Dynamic = { ok: true, kind: kind, clouds: clouds };
		if (includeCounts) Reflect.setField(out, "counts", countsOut);
		if (includeEnsemble && ensemblesOut.length > 0)
			Reflect.setField(out, "ensembles", ensemblesOut);
		return out;
	}

	/** Zip lattice `ensembleAt` bands with count masses (opacity ∝ mass). */
	static function ensembleArr(
		host:LatticeForecastHost, t:Int, masses:Array<EwCountMass>
	):Array<Dynamic> {
		var bands = host.ensembleAt(t);
		var out:Array<Dynamic> = [];
		if (bands == null) return out;
		for (i in 0...bands.length) {
			var b = bands[i];
			var mass = (masses != null && i < masses.length) ? masses[i].mass : Math.NaN;
			var label = (masses != null && i < masses.length) ? masses[i].label : b.kind;
			var inv = (masses != null && i < masses.length) ? masses[i].invalidatePrice : Math.NaN;
			out.push({
				label: label,
				mass: mass,
				priceLo: b.priceLo,
				priceHi: b.priceHi,
				barLo: b.barLo,
				barHi: b.barHi,
				kind: b.kind,
				invalidatePrice: inv
			});
		}
		return out;
	}

	/** Default: last bar only. `queryAt` (int) or `all:true` for every bar. */
	static function queryAnchors(n:Int, opts:Dynamic):Array<Int> {
		if (n <= 0) return [];
		if (optBool(opts, "all", false)) {
			var all:Array<Int> = [];
			for (i in 0...n) all.push(i);
			return all;
		}
		if (opts != null && Reflect.hasField(opts, "queryAt")) {
			var q = optInt(opts, "queryAt", n - 1);
			if (q < 0) q = 0;
			if (q >= n) q = n - 1;
			return [q];
		}
		return [n - 1];
	}

	static function cloudObj(t:Int, c:ForecastCloud):Dynamic {
		return {
			t: t,
			horizon: c.horizon,
			priceLo: c.priceLo,
			priceHi: c.priceHi,
			barLo: c.barLo,
			barHi: c.barHi,
			priceMid: c.priceMid,
			spread: c.spread,
			probUp: c.probUp,
			topMass: c.topMass,
			countEntropy: c.countEntropy,
			invalidatePrice: c.invalidatePrice,
			distToInvalidation: c.distToInvalidation,
			nestScore: c.nestScore,
			labelCode: c.labelCode,
			samples: c.samples
		};
	}

	static function massesArr(masses:Array<EwCountMass>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (masses == null) return out;
		for (m in masses) {
			out.push({
				label: m.label,
				mass: m.mass,
				score: m.score,
				invalidatePrice: m.invalidatePrice,
				nestScore: m.nestScore,
				degree: m.degree
			});
		}
		return out;
	}

	static function toBars(bars:Array<Dynamic>):Array<Bar> {
		if (bars == null) return [];
		var out:Array<Bar> = [];
		for (i in 0...bars.length) {
			var b = bars[i];
			out.push({
				open: num(b, "open"),
				high: num(b, "high"),
				low: num(b, "low"),
				close: num(b, "close"),
				volume: Reflect.hasField(b, "volume") ? num(b, "volume") : 0.0,
				time: Reflect.hasField(b, "time") ? num(b, "time") : (i : Float),
				index: i
			});
		}
		return out;
	}

	static function num(o:Dynamic, f:String):Float {
		var v:Dynamic = Reflect.field(o, f);
		if (v == null) return Math.NaN;
		return (v : Float);
	}

	static function err(msg:String):Dynamic {
		return { ok: false, error: msg };
	}

	static function optInt(opts:Dynamic, key:String, def:Int):Int {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		var v:Dynamic = Reflect.field(opts, key);
		if (v == null) return def;
		return Std.isOfType(v, Int) ? cast v : Std.int((v : Float));
	}

	static function optFloat(opts:Dynamic, key:String, def:Float):Float {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		var v = Reflect.field(opts, key);
		return v == null ? def : (v : Float);
	}

	static function optBool(opts:Dynamic, key:String, def:Bool):Bool {
		if (opts == null || !Reflect.hasField(opts, key)) return def;
		return Reflect.field(opts, key) == true;
	}
}

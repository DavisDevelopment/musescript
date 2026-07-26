package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef FibExtensionOutput = {
	var level0:Float;
	var level618:Float;
	var level1000:Float;
	var level1618:Float;
	var level2618:Float;
	var levels:LevelSet;
	var pivots:PivotMarkSet;
	var zones:ZoneSet;
	var forecast:ForecastBand;
}

class FibExtension implements MuseIndicator<Bar, FibExtensionOutput> {
	static final RATIOS = [0.0, 0.618, 1.0, 1.618, 2.618];
	var period:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var out:FibExtensionOutput;
	var priceScratch:haxe.ds.Vector<Float>;
	var ratioScratch:haxe.ds.Vector<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "FibExtension: period must be > 0";
		this.period = period;
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		priceScratch = new haxe.ds.Vector<Float>(8);
		ratioScratch = new haxe.ds.Vector<Float>(8);
		out = {
			level0: Math.NaN, level618: Math.NaN, level1000: Math.NaN,
			level1618: Math.NaN, level2618: Math.NaN,
			levels: LevelSet.nan(), pivots: PivotMarkSet.nan(),
			zones: ZoneSet.nan(), forecast: ForecastBand.nan()
		};
	}

	public function update(bar:Bar):Null<FibExtensionOutput> {
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length < period) return null;
		var hh = highs.at(0);
		var ll = lows.at(0);
		for (i in 1...highs.length) {
			var h = highs.at(i); var l = lows.at(i);
			if (h > hh) hh = h;
			if (l < ll) ll = l;
		}
		out.level0 = RatioEngine.windowLevel(ll, hh, 0.0);
		out.level618 = RatioEngine.windowLevel(ll, hh, 0.618);
		out.level1000 = RatioEngine.windowLevel(ll, hh, 1.0);
		out.level1618 = RatioEngine.windowLevel(ll, hh, 1.618);
		out.level2618 = RatioEngine.windowLevel(ll, hh, 2.618);
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		var pst = GeomVizFill.statusOf(PivotStatus.Projected);
		for (i in 0...RATIOS.length) {
			priceScratch[i] = RatioEngine.windowLevel(ll, hh, RATIOS[i]);
			ratioScratch[i] = RATIOS[i];
		}
		GeomVizFill.levels(priceScratch, ratioScratch, RATIOS.length, st, out.levels);
		// Mark extension slots beyond 1.0 as Projected
		out.levels.set(3, out.level1618, 1.618, pst);
		out.levels.set(4, out.level2618, 2.618, pst);
		out.pivots.clear();
		out.pivots.set(0, ll, -1, bar.index * 1.0, st);
		out.pivots.set(1, hh, 1, bar.index * 1.0, st);
		out.pivots.count = 2;
		out.zones.clear();
		out.zones.set(0, out.level1000, out.level1618, bar.index * 1.0, bar.index * 1.0 + 5, pst, (ZoneKind.Extension : Int) * 1.0);
		out.zones.count = 1;
		out.forecast.set(out.level1618, out.level2618, bar.index * 1.0, bar.index * 1.0 + 10);
		return out;
	}

	public function reset():Void {
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		out.levels.clear(); out.pivots.clear(); out.zones.clear(); out.forecast.clear();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return highs.length == period;
	public function name():String return "FibExtension";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_extension", args: [TWindow], ret: TObject([
				{name: "level0", ty: TScalar}, {name: "level618", ty: TScalar}, {name: "level1000", ty: TScalar},
				{name: "level1618", ty: TScalar}, {name: "level2618", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "forecast", ty: GeomVizSpec.forecastObj()}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var nanFill:FibExtensionOutput = {
					level0: Math.NaN, level618: Math.NaN, level1000: Math.NaN,
					level1618: Math.NaN, level2618: Math.NaN,
					levels: LevelSet.nan(), pivots: PivotMarkSet.nan(),
					zones: ZoneSet.nan(), forecast: ForecastBand.nan()
				};
				return IndicatorCache.evalBar(h, "fib_extension:" + p, nanFill,
					() -> new FibExtension(p), (i, b) -> (cast i : FibExtension).update(b));
			}
		};
	}
}

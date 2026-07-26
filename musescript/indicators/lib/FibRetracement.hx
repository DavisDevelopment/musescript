package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

/**
 * Fibonacci Retracement — legacy named levels + chart viz packs.
 * `levels` / `pivots` / `zones` are stable nested TObjects for the chart agent.
 */
typedef FibRetracementOutput = {
	var level0:Float;
	var level236:Float;
	var level382:Float;
	var level500:Float;
	var level618:Float;
	var level786:Float;
	var level1000:Float;
	var levels:LevelSet;
	var pivots:PivotMarkSet;
	var zones:ZoneSet;
}

enum abstract FibAnchorMode(Int) from Int to Int {
	var Window = 0;
	var Pivot = 1;
}

class FibRetracement implements MuseIndicator<Bar, FibRetracementOutput> {
	static final RATIOS = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];

	var period:Int;
	var mode:FibAnchorMode;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var swing:Null<SwingGraph>;
	var out:FibRetracementOutput;
	var priceScratch:haxe.ds.Vector<Float>;
	var ratioScratch:haxe.ds.Vector<Float>;

	public function new(period:Int, mode:FibAnchorMode = Window, ?swingThreshold:Float) {
		if (period <= 0) throw "FibRetracement: period must be > 0";
		this.period = period;
		this.mode = mode;
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		swing = mode == Pivot ? new SwingGraph(swingThreshold != null ? swingThreshold : 0.05, 4) : null;
		priceScratch = new haxe.ds.Vector<Float>(8);
		ratioScratch = new haxe.ds.Vector<Float>(8);
		out = {
			level0: Math.NaN, level236: Math.NaN, level382: Math.NaN, level500: Math.NaN,
			level618: Math.NaN, level786: Math.NaN, level1000: Math.NaN,
			levels: LevelSet.nan(), pivots: PivotMarkSet.nan(), zones: ZoneSet.nan()
		};
	}

	public function update(bar:Bar):Null<FibRetracementOutput> {
		if (mode == Pivot) {
			swing.update(bar);
			return levelsFromPivots();
		}
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length < period) return null;

		var hh = highs.at(0);
		var ll = lows.at(0);
		for (i in 1...highs.length) {
			var h = highs.at(i);
			var l = lows.at(i);
			if (h > hh) hh = h;
			if (l < ll) ll = l;
		}
		return fillWindow(ll, hh, bar.index * 1.0);
	}

	function levelsFromPivots():Null<FibRetracementOutput> {
		if (swing.pivotCount() < 2) return null;
		var n = swing.pivotCount();
		var start = swing.pivotAt(n - 2).price;
		var end = swing.pivotAt(n - 1).price;
		fillNamed(start, end);
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		for (i in 0...RATIOS.length) {
			priceScratch[i] = RatioEngine.retrace(start, end, RATIOS[i]);
			ratioScratch[i] = RATIOS[i];
		}
		GeomVizFill.levels(priceScratch, ratioScratch, RATIOS.length, st, out.levels);
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 4);
		out.zones.clear();
		out.zones.set(0,
			Math.min(out.level618, out.level786), Math.max(out.level618, out.level786),
			swing.pivotAt(n - 2).bar * 1.0, swing.currentBar() * 1.0,
			st, (ZoneKind.RetraceBand : Int) * 1.0);
		out.zones.count = 1;
		return out;
	}

	function fillWindow(ll:Float, hh:Float, barIdx:Float):FibRetracementOutput {
		fillNamedFromWindow(ll, hh);
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		for (i in 0...RATIOS.length) {
			priceScratch[i] = RatioEngine.windowLevel(ll, hh, RATIOS[i]);
			ratioScratch[i] = RATIOS[i];
		}
		GeomVizFill.levels(priceScratch, ratioScratch, RATIOS.length, st, out.levels);
		out.pivots.clear();
		out.pivots.set(0, ll, -1.0, barIdx, st);
		out.pivots.set(1, hh, 1.0, barIdx, st);
		out.pivots.count = 2;
		out.zones.clear();
		out.zones.set(0,
			Math.min(out.level618, out.level786), Math.max(out.level618, out.level786),
			barIdx, barIdx, st, (ZoneKind.RetraceBand : Int) * 1.0);
		out.zones.count = 1;
		return out;
	}

	function fillNamed(start:Float, end:Float):Void {
		out.level0 = RatioEngine.retrace(start, end, 0.0);
		out.level236 = RatioEngine.retrace(start, end, 0.236);
		out.level382 = RatioEngine.retrace(start, end, 0.382);
		out.level500 = RatioEngine.retrace(start, end, 0.5);
		out.level618 = RatioEngine.retrace(start, end, 0.618);
		out.level786 = RatioEngine.retrace(start, end, 0.786);
		out.level1000 = RatioEngine.retrace(start, end, 1.0);
	}

	function fillNamedFromWindow(ll:Float, hh:Float):Void {
		out.level0 = RatioEngine.windowLevel(ll, hh, 0.0);
		out.level236 = RatioEngine.windowLevel(ll, hh, 0.236);
		out.level382 = RatioEngine.windowLevel(ll, hh, 0.382);
		out.level500 = RatioEngine.windowLevel(ll, hh, 0.5);
		out.level618 = RatioEngine.windowLevel(ll, hh, 0.618);
		out.level786 = RatioEngine.windowLevel(ll, hh, 0.786);
		out.level1000 = RatioEngine.windowLevel(ll, hh, 1.0);
	}

	public function reset():Void {
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		if (swing != null) swing.reset();
		out.levels.clear();
		out.pivots.clear();
		out.zones.clear();
	}

	public function warmupPeriod():Int return mode == Pivot ? 2 : period;
	public function isReady():Bool {
		if (mode == Pivot) return swing != null && swing.pivotCount() >= 2;
		return highs.length == period;
	}
	public function name():String return "FibRetracement";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_retracement", args: [TWindow], ret: TObject([
				{name: "level0", ty: TScalar}, {name: "level236", ty: TScalar}, {name: "level382", ty: TScalar},
				{name: "level500", ty: TScalar}, {name: "level618", ty: TScalar}, {name: "level786", ty: TScalar},
				{name: "level1000", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var nanFill:FibRetracementOutput = {
					level0: Math.NaN, level236: Math.NaN, level382: Math.NaN, level500: Math.NaN,
					level618: Math.NaN, level786: Math.NaN, level1000: Math.NaN,
					levels: LevelSet.nan(), pivots: PivotMarkSet.nan(), zones: ZoneSet.nan()
				};
				return IndicatorCache.evalBar(h, "fib_retracement:" + p, nanFill,
					() -> new FibRetracement(p), (i, b) -> (cast i : FibRetracement).update(b));
			}
		};
	}
}

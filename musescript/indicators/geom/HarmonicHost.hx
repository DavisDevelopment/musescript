package musescript.indicators.geom;

import musescript.harness.Bar;

/**
 * Shared harmonic XABCD host: SwingGraph pivots + RatioEngine cluster for PRZ.
 * Pattern detectors (Gartley/Bat/…) call `matchXabcd` with ratio windows; PRZ
 * helpers expose confluence of D-leg projection ratios.
 */
typedef HarmonicMatch = {
	var signal:Float; // +1 bullish D-low, −1 bearish D-high, 0 none
	var prz:Float;
	var przStrength:Float;
}

typedef HarmonicWindows = {
	var abXaLo:Float;
	var abXaHi:Float;
	var bcAbLo:Float;
	var bcAbHi:Float;
	var cdBcLo:Float;
	var cdBcHi:Float;
	var adXaLo:Float;
	var adXaHi:Float;
}

class HarmonicHost {
	var swing:SwingGraph;
	var levelScratch:haxe.ds.Vector<Float>;
	var last:HarmonicMatch;

	public function new(?threshold:Float, capacity:Int = 5) {
		swing = new SwingGraph(threshold != null ? threshold : 0.05, capacity);
		levelScratch = new haxe.ds.Vector<Float>(16);
		last = { signal: 0.0, prz: Math.NaN, przStrength: 0.0 };
	}

	public function graph():SwingGraph return swing;

	public function update(bar:Bar):Bool return swing.update(bar);

	public function reset():Void {
		swing.reset();
		last.signal = 0.0;
		last.prz = Math.NaN;
		last.przStrength = 0.0;
	}

	/**
	 * Match last five Confirmed pivots as X-A-B-C-D against ratio windows.
	 * Also fills PRZ as cluster of AD/XA projection candidates at D.
	 */
	public function matchXabcd(w:HarmonicWindows):HarmonicMatch {
		last.signal = 0.0;
		last.prz = Math.NaN;
		last.przStrength = 0.0;
		if (swing.pivotCount() < 5) return last;

		var n = swing.pivotCount();
		var px = swing.pivotAt(n - 5);
		var pa = swing.pivotAt(n - 4);
		var pb = swing.pivotAt(n - 3);
		var pc = swing.pivotAt(n - 2);
		var pd = swing.pivotAt(n - 1);

		var xa = Math.abs(pa.price - px.price);
		var ab = Math.abs(pb.price - pa.price);
		var bc = Math.abs(pc.price - pb.price);
		var cd = Math.abs(pd.price - pc.price);
		var ad = Math.abs(pd.price - pa.price);
		if (xa <= 0 || ab <= 0 || bc <= 0) return last;

		var abXa = ab / xa;
		var bcAb = bc / ab;
		var cdBc = cd / bc;
		var adXa = ad / xa;

		var ok = abXa >= w.abXaLo && abXa <= w.abXaHi
			&& bcAb >= w.bcAbLo && bcAb <= w.bcAbHi
			&& cdBc >= w.cdBcLo && cdBc <= w.cdBcHi
			&& adXa >= w.adXaLo && adXa <= w.adXaHi;

		// PRZ cluster: project common AD ratios from A along XA direction
		var dir = pa.price >= px.price ? 1.0 : -1.0;
		var ratios = RatioTables.HARMONIC_AD_XA;
		var count = 0;
		for (i in 0...ratios.length) {
			levelScratch[count++] = RatioEngine.project(pa.price, xa, ratios[i], -dir);
		}
		var cl = RatioEngine.cluster(levelScratch, count, 0.03);
		if (cl != null) {
			last.prz = cl.price;
			last.przStrength = cl.strength;
		}

		if (ok) last.signal = pd.direction < 0.0 ? 1.0 : -1.0;
		return last;
	}
}

package musescript.indicators.geom;

/**
 * Square of Nine — framed as a discrete angular price map (math tool), not mysticism.
 * Given a root price, walk rings where each cell steps by a fixed increment derived
 * from `root` and optional `step` (default root-relative).
 */
class SquareOfNine {
	/**
	 * Price at ring `ring` (0 = root) and cell `cell` in [0, 8*ring) for ring>0.
	 * Layout: ring r has 8*r cells; cell 0 is "east" of root, progressing CCW.
	 */
	public static function priceAt(root:Float, ring:Int, cell:Int, ?step:Float):Float {
		if (!Math.isFinite(root)) return Math.NaN;
		if (ring <= 0) return root;
		var s = step != null && Math.isFinite(step) && step > 0 ? step : Math.abs(root) * 0.01;
		if (!(s > 0)) s = 1.0;
		var cells = 8 * ring;
		var c = cell % cells;
		if (c < 0) c += cells;
		// Cardinal midpoints of each ring sit at odd multiples of ring along axes.
		// Approximate spiral distance from root as ring * s * (1 + c/cells).
		var dist = ring * s * (1.0 + c / cells);
		return root + dist;
	}

	/** Nearest ring/cell for a target price (brute small rings). */
	public static function nearest(root:Float, target:Float, maxRing:Int = 8, ?step:Float):{ring:Int, cell:Int, price:Float} {
		var bestRing = 0;
		var bestCell = 0;
		var bestPrice = root;
		var bestErr = Math.abs(target - root);
		for (r in 1...maxRing + 1) {
			var cells = 8 * r;
			for (c in 0...cells) {
				var p = priceAt(root, r, c, step);
				var err = Math.abs(p - target);
				if (err < bestErr) {
					bestErr = err;
					bestRing = r;
					bestCell = c;
					bestPrice = p;
				}
			}
		}
		return { ring: bestRing, cell: bestCell, price: bestPrice };
	}
}

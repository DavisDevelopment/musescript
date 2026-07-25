package musescript.scratch;

import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.SeriesNode;
import musescript.evo.Canonical;

/**
 * Collision probe for `StructuralDigest`: enumerate a large space of structurally DISTINCT bool
 * subtrees, key each one, and report how many distinct structures collapsed onto a shared key.
 * A structural key that collides makes the credit bank merge unrelated shapes, which is invisible
 * to `TestNmaBijection` (it only pins the two walkers to each other, not the hash to injectivity).
 */
class DigestProbe {
	static function main() {
		var nodes = new Array<BoolNode>();
		var ops = ["<", ">", "<=", ">=", "==", "!="];
		var dirs = ["above", "below"];
		var fields = ["open", "high", "low", "close", "volume"];
		var inds = ["sma", "ema", "rsi", "atr", "wma", "hma", "tema", "vidya", "tii", "cci"];

		for (op in ops)
			for (i in 0...24)
				for (j in 0...24)
					nodes.push(BCmp(op, KParam(i), KConst(j * 0.5)));

		for (op in ops)
			for (name in inds)
				for (w in 2...40)
					for (f in fields)
						nodes.push(BCmp(op, KSeries(SInd(name, f, w, null)), KConst(w)));

		for (dir in dirs)
			for (a in inds)
				for (b in inds)
					for (w in 2...30)
						nodes.push(BCross(dir, SInd(a, "close", w, null), SInd(b, "close", w + 1, null)));

		for (dir in dirs)
			for (name in inds)
				for (w in 2...60)
					for (f in fields)
						nodes.push(BTrend(dir, SInd(name, f, w, null), w));

		// Composites: the shapes attribution actually keys as donors.
		var base = nodes.slice(0, 400);
		for (i in 0...base.length)
			for (j in 0...4) {
				nodes.push(BAnd(base[i], base[(i * 7 + j * 131) % base.length]));
				nodes.push(BOr(base[i], base[(i * 13 + j * 271) % base.length]));
				nodes.push(BNot(base[(i + j) % base.length]));
			}

		var keys = new Map<String, Int>();
		var shapes = new Map<String, Bool>();
		var n = 0;
		var collisions = 0;
		for (b in nodes) {
			// The enum's own printed form is the injective reference: distinct renderings are
			// distinct structures by construction.
			var shape = Std.string(b);
			if (shapes.exists(shape)) continue;
			shapes.set(shape, true);
			n++;
			var k = Canonical.boolStructuralKey(b);
			var prior = keys.get(k);
			if (prior != null) collisions++;
			keys.set(k, (prior == null ? 0 : prior) + 1);
		}

		var distinctKeys = 0;
		for (_ in keys.keys()) distinctKeys++;
		Sys.println('distinct structures : $n');
		Sys.println('distinct keys       : $distinctKeys');
		Sys.println('collisions          : $collisions');
		Sys.println('collision rate      : ' + (n > 0 ? (collisions / n * 100) : 0) + "%");
		// Birthday expectation for a well-distributed 64-bit key at this n is ~0.
		Sys.println(collisions == 0 ? "DIGEST_OK" : "DIGEST_COLLIDES");
	}
}

package musescript.evo.rigor;

/**
 * Purge & embargo around an IS/OOS split so indicator lookbacks cannot leak
 * across the boundary (López de Prado).
 *
 * Given a full tape of length `n`, OOS fraction `oosFrac`, and `maxLookback`:
 * - IS ends at `split - maxLookback` (purge the last lookback IS bars that would
 *   touch OOS labels / warm into the gap)
 * - Embargo drops `[split, split + maxLookback)` so OOS scoring never starts
 *   until indicators have warmed on post-split data only
 * - OOS is `[split + maxLookback, n)`
 */
class PurgeEmbargo {
	public static function split(
		n:Int, oosFrac:Float, maxLookback:Int
	):{isEnd:Int, oosStart:Int, embargo:Int, purged:Int} {
		if (n < 1) return {isEnd: 0, oosStart: 0, embargo: 0, purged: 0};
		var lb = maxLookback < 0 ? 0 : maxLookback;
		var oosLen = Std.int(n * oosFrac);
		if (oosLen < 1) oosLen = 1;
		if (oosLen >= n) oosLen = n - 1;
		var split = n - oosLen; // first OOS index before embargo
		var isEnd = split - lb;
		if (isEnd < 0) isEnd = 0;
		var oosStart = split + lb;
		if (oosStart > n) oosStart = n;
		return {isEnd: isEnd, oosStart: oosStart, embargo: lb, purged: lb};
	}

	/** True iff bar index `t` is a legal OOS evaluation index for lookback `maxLookback`. */
	public static function isLegalOosBar(t:Int, split:Int, maxLookback:Int):Bool {
		return t >= split + (maxLookback < 0 ? 0 : maxLookback);
	}

	/** Slice helpers — return IS / OOS bar ranges as [start, end) index pairs. */
	public static function ranges(n:Int, oosFrac:Float, maxLookback:Int):{isFrom:Int, isTo:Int, oosFrom:Int, oosTo:Int} {
		var s = split(n, oosFrac, maxLookback);
		return {isFrom: 0, isTo: s.isEnd, oosFrom: s.oosStart, oosTo: n};
	}
}

package musescript.evo;

/**
 * Domain constraint on an author / synthesis hole (SPEC_AUTHOR_HOLES).
 * Carried on `BHole`/`KHole` as optional trailing enum params so existing
 * `case BHole(inner):` / `KHole(inner)` matches stay valid.
 */
enum HoleDomain {
	DIntRange(lo:Int, hi:Int);
	DRealInterval(lo:Float, hi:Float);
	/** Restrict series/bool family draws (P1 surface `~ {sma,ema}` / `~ cross`). */
	DFamily(names:Array<String>);
}

package musescript.evo.nma;

/**
 * Constructor discriminant for every NMA node kind, one tag per enum constructor across the three
 * evo families (Series/Scalar/Bool). Kept alongside the concrete class hierarchy so a hot
 * tree-walk (credit propagation, memo invalidation, dispatch) can branch on a cheap final enum tag
 * instead of an `Std.isOfType` chain -- the JVM target compiles a `switch` over a Haxe enum to a
 * `tableswitch`, not a cascade of `instanceof`. `NmaBijection` maps these 1:1 with
 * `BoolNode`/`ScalarNode`/`SeriesNode`.
 *
 * The constructor names deliberately mirror the evo enum constructor names; because of that, any
 * module that imports BOTH this and `BoolNode`/`ScalarNode`/`SeriesNode` unqualified will collide
 * -- import this aliased (`import ... .NmaKind as NmaK;`) in those sites (see `TestNmaBijection`).
 * Inside a `switch (node.kind)` the collision does not arise: enum-switch patterns resolve against
 * the switched value's type (`NmaKind`) regardless of what else is in scope.
 *
 * «Βρόμιε, λῦσον μελάθρων· θύρσος πατάσσει.»
 */
enum NmaKind {
	// Series
	SPrice; SInd;
	// Scalar
	KConst; KParam; KArith; KSeries; KLookback; KFeature; KHole; KNp; KPd;
	// Bool
	BCross; BCmp; BTrend; BAnd; BOr; BNot; BHole;
}

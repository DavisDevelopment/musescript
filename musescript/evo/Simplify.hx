package musescript.evo;

/**
 * Semantic-equivalence-aware tree simplification: a bottom-up rewrite pass over BoolNode/
 * ScalarNode that collapses provably-redundant or tautological subtrees to their equivalent
 * (usually smaller) form, WITHOUT changing what the genome actually does. This is the
 * "intelligence" half of the parsimony story -- the soft-cap parsimony penalty (Fitness.score)
 * pushes back on unbounded bloat by SCORE, but does nothing about a genome that's smaller-in-
 * node-count than it could be while still carrying dead weight the penalty never sees (e.g. an
 * `x && (1 > 0)` clause, or `unrealized_pnl_pct() < unrealized_pnl_pct()`, both of which are
 * exactly the kind of degenerate shape CorpusSeed's growth pool and crossover/mutation can
 * produce and which the earlier interp<->WASM short-circuit parity bug this session fixed was
 * caused by resembling in the first place).
 *
 * Every rule here is a real algebraic/logical identity in this genome IR's deterministic,
 * per-bar-pure evaluation model -- not a heuristic. The one place that needs care is STATEFUL
 * builtins (BCross/BTrend carry per-callsite "previous value" state across bars): folding a
 * `BCross`/`BTrend` node away entirely removes its callsite from the rendered source, which is
 * always safe (there is no side effect left to preserve once the callsite itself is gone --
 * see `foldBCrossSelf`'s doc comment for the one rule that touches BCross), but a `BCmp` self-
 * comparison rule additionally excludes any operand containing an indicator call (`SInd`) to
 * avoid depending on indicator memoization being per-bar-idempotent under a doubled read --
 * see `boolEqForFold`'s doc comment.
 */
class Simplify {
	static var TRUE:BoolNode = BCmp(">", KConst(1.0), KConst(0.0));
	static var FALSE:BoolNode = BCmp(">", KConst(0.0), KConst(1.0));

	static function isAlwaysTrue(n:BoolNode):Bool
		return switch (n) { case BCmp(op, KConst(a), KConst(b)): evalCmp(op, a, b) == true; default: false; }

	static function isAlwaysFalse(n:BoolNode):Bool
		return switch (n) { case BCmp(op, KConst(a), KConst(b)): evalCmp(op, a, b) == false; default: false; }

	static function evalCmp(op:String, a:Float, b:Float):Bool {
		return switch (op) {
			case ">": a > b;
			case "<": a < b;
			case ">=": a >= b;
			case "<=": a <= b;
			case "==": a == b;
			case "!=": a != b;
			default: false; // unknown op -- never claim a fold for it
		};
	}

	/** Structural equality for ScalarNode -- used ONLY to detect genuinely redundant `a op a`
	 * shapes, so it must be conservative about what counts as "the same read twice is safe to
	 * fold": excludes any subtree containing an `SInd` (indicator) call. Indicators are cached
	 * per-callsite (IndicatorCache/CallsiteIds), and this pass doesn't need to prove that cache is
	 * bar-idempotent under a doubled textual read to be correct -- it's simpler and safer to just
	 * never fold indicator self-comparisons at all, and lose nothing of real value (an indicator
	 * comparing itself to itself is not a shape growth/mutation has any reason to actually produce
	 * on purpose -- unlike `unrealized_pnl_pct() < unrealized_pnl_pct()`, which mutation's random
	 * BCmp construction can genuinely generate from two independent growScalar calls that happen
	 * to draw the identical KFeature leaf). */
	static function scalarEqForFold(a:ScalarNode, b:ScalarNode):Bool {
		if (containsIndicator(a) || containsIndicator(b)) return false;
		return scalarEq(a, b);
	}

	/**
	 * Returns true if the given ScalarNode contains an SInd call.
	 * @param n ScalarNode 
	 * @return Bool
	 */
	public static function containsIndicator(n:ScalarNode):Bool {
		return switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KPd(_, _, _, _, _): false;
			case KSeries(s) | KLookback(s, _): seriesHasIndicator(s);
			case KNp(_, a, _, b):
				seriesHasIndicator(a) || (b != null && seriesHasIndicator(b));
			case KArith(_, a, b): containsIndicator(a) || containsIndicator(b);
			case KHole(inner): containsIndicator(inner);
		};
	}

	/**
	 * Returns true if the given SeriesNode contains an SInd call.
	 * @param s SeriesNode 
	 * @return Bool
	 */
	public static function seriesHasIndicator(s:SeriesNode):Bool {
		return switch (s) {
			case SPrice(_): false;
			case SProj(_, _): false; // a projection reference is a variable, not an indicator
			case SPanel(_, _, _, _): false; // panel-of leaf — not an SInd callsite
			case SInd(_, _, _, _): true;
		};
	}

	/**
	 * Returns true if the given two ScalarNodes are semantically equivalent.
	 * @param a 
	 * @param b 
	 * @return Bool
	 */
	public static function scalarEq(a:ScalarNode, b:ScalarNode):Bool {
		return switch [a, b] {
			case [KConst(x), KConst(y)]: x == y;
			case [KParam(x), KParam(y)]: x == y;
			case [KFeature(x), KFeature(y)]: x == y;
			case [KSeries(x), KSeries(y)]: seriesEq(x, y);
			case [KLookback(x, kx), KLookback(y, ky)]: kx == ky && seriesEq(x, y);
			case [KNp(ox, ax, wx, bx), KNp(oy, ay, wy, by)]:
				ox == oy && wx == wy && seriesEq(ax, ay)
				&& (bx == null && by == null || bx != null && by != null && seriesEq(bx, by));
			case [KPd(ox, kx, wx, sx, ux), KPd(oy, ky, wy, sy, uy)]:
				ox == oy && kx == ky && wx == wy && sx == sy && arrEq(ux, uy);
			case [KArith(ox, ax, bx), KArith(oy, ay, by)]: ox == oy && scalarEq(ax, ay) && scalarEq(bx, by);
			default: false;
		};
	}

	static function arrEq(a:Array<String>, b:Array<String>):Bool {
		if (a == null && b == null) return true;
		if (a == null || b == null || a.length != b.length) return false;
		for (i in 0...a.length) if (a[i] != b[i]) return false;
		return true;
	}

	/**
	 * Returns true if the given two SeriesNodes are semantically equivalent.
	 * @param a SeriesNode
	 * @param b SeriesNode
	 * @return Bool
	 */
	public static function seriesEq(a:SeriesNode, b:SeriesNode):Bool {
		return switch [a, b] {
			case [SPrice(x), SPrice(y)]: x == y;
			case [SPanel(kx, sx, fx, wx), SPanel(ky, sy, fy, wy)]:
				kx == ky && sx == sy && fx == fy && wx == wy;
			case [SInd(nx, fx, wx, sx), SInd(ny, fy, wy, sy)]:
				nx == ny && fx == fy && wx == wy
				&& (sx == null && sy == null || sx != null && sy != null && seriesEq(sx, sy));
			default: false;
		};
	}

	/**
	 * `BCross(dir, a, a)` (a series compared against ITSELF) can never fire, independent of any
	 * per-bar state: crossover requires `a > b` (or `a < b` for crossunder) to hold on the CURRENT
	 * bar, and a series can never be strictly greater than (or less than) itself. Folding this
	 * away removes the callsite entirely -- there is no leftover per-callsite state to worry about
	 * because nothing else in the rendered source shares that (now-deleted) callsite id.
	 */
	static function foldBCrossSelf(dir:String, a:SeriesNode, b:SeriesNode):Null<BoolNode> {
		return seriesEq(a, b) ? FALSE : null;
	}

	public static function simplifyBool(n:BoolNode):BoolNode {
		return switch (n) {
			case BAnd(a, b):
				var sa = simplifyBool(a);
				var sb = simplifyBool(b);
				if (isAlwaysFalse(sa) || isAlwaysFalse(sb)) FALSE
				else if (isAlwaysTrue(sa)) sb
				else if (isAlwaysTrue(sb)) sa
				else if (boolEq(sa, sb)) sa // x && x -> x
				// `(X && b) && b` / `a && (a && Y)` -- a conjunct repeated across a NESTED chain,
				// not just the two immediate operands. This is the shape crossover/mutation
				// actually produces once one AND is already several levels deep (see this file's
				// doc comment / the live corpus-evo run this rule was added in response to:
				// `(falling(...) && (ema1 > ema2)) && (ema1 > ema2)`, where the outer BAnd's two
				// DIRECT children are NOT structurally equal -- only the deeper repeated conjunct
				// is -- so the direct-children check above alone can't catch it).
				else if (conjunctSubsumedBy(sa, sb)) sa
				else if (conjunctSubsumedBy(sb, sa)) sb
				else BAnd(sa, sb);
			case BOr(a, b):
				var sa = simplifyBool(a);
				var sb = simplifyBool(b);
				if (isAlwaysTrue(sa) || isAlwaysTrue(sb)) TRUE
				else if (isAlwaysFalse(sa)) sb
				else if (isAlwaysFalse(sb)) sa
				else if (boolEq(sa, sb)) sa // x || x -> x
				else if (disjunctSubsumedBy(sa, sb)) sa
				else if (disjunctSubsumedBy(sb, sa)) sb
				else BOr(sa, sb);
			case BNot(a):
				var sa = simplifyBool(a);
				switch (sa) {
					case BNot(inner): inner; // !!x -> x
					default:
						if (isAlwaysTrue(sa)) FALSE
						else if (isAlwaysFalse(sa)) TRUE
						else BNot(sa);
				}
			case BCmp(op, a, b):
				var sa = simplifyScalar(a);
				var sb = simplifyScalar(b);
				switch [sa, sb] {
					case [KConst(x), KConst(y)]: evalCmp(op, x, y) ? TRUE : FALSE;
					default:
						if (scalarEqForFold(sa, sb)) {
							var r = evalCmp(op, 0, 0); // a op a: only depends on op's reflexivity
							r ? TRUE : FALSE;
						} else BCmp(op, sa, sb);
				}
			case BCross(dir, a, b):
				var folded = foldBCrossSelf(dir, a, b);
				folded != null ? folded : BCross(dir, a, b);
			case BTrend(dir, s, w): BTrend(dir, s, w);
			// Recurse INSIDE the hole (dead weight still gets cleaned up), but never collapse the
			// wrapper itself away -- even if `inner` folds to TRUE/FALSE, the boundary marking this
			// position as mutation-eligible must survive (a parent BAnd/BOr's isAlwaysTrue/
			// isAlwaysFalse checks deliberately don't see through BHole -- they fall to their
			// `default: false` arm -- so a frozen skeleton sibling is never erased on account of a
			// hole's current, transient content).
			case BHole(inner): BHole(simplifyBool(inner));
			case BFeature(src): BFeature(src); // opaque leaf: atomic, nothing to simplify
		};
	}

	/** Structural equality for BoolNode -- used for the `x && x` / `x || x` dedup rules above.
	 * Unlike `scalarEqForFold`, this doesn't need to exclude stateful builtins: collapsing `x && x`
	 * to a SINGLE `x` only ever REMOVES a redundant duplicate callsite, it never introduces a fresh
	 * double-read that wasn't already there (see this file's doc comment). */
	static function boolEq(a:BoolNode, b:BoolNode):Bool {
		return switch [a, b] {
			case [BCross(dx, ax, bx), BCross(dy, ay, by)]: dx == dy && seriesEq(ax, ay) && seriesEq(bx, by);
			case [BCmp(ox, ax, bx), BCmp(oy, ay, by)]: ox == oy && scalarEq(ax, ay) && scalarEq(bx, by);
			case [BTrend(dx, sx, wx), BTrend(dy, sy, wy)]: dx == dy && wx == wy && seriesEq(sx, sy);
			case [BAnd(ax, bx), BAnd(ay, by)]: boolEq(ax, ay) && boolEq(bx, by);
			case [BOr(ax, bx), BOr(ay, by)]: boolEq(ax, ay) && boolEq(bx, by);
			case [BNot(ax), BNot(ay)]: boolEq(ax, ay);
			default: false;
		};
	}

	/** True when `tree` is an AND-chain (of any nesting/associativity) that ALREADY contains a
	 * conjunct structurally equal to `target` -- i.e. `tree && target` is logically just `tree`,
	 * since ANDing something with a copy of one of its own existing conjuncts changes nothing.
	 * Recurses through nested BAnd nodes only (an BOr/BCmp/etc. boundary stops the search, since a
	 * conjunct living UNDER an OR isn't unconditionally implied by the whole AND-chain). */
	static function conjunctSubsumedBy(tree:BoolNode, target:BoolNode):Bool {
		return switch (tree) {
			case BAnd(x, y): boolEq(x, target) || boolEq(y, target)
				|| conjunctSubsumedBy(x, target) || conjunctSubsumedBy(y, target);
			default: false;
		};
	}

	/** Mirror of `conjunctSubsumedBy` for OR-chains: `tree` already contains a disjunct equal to
	 * `target`, so `tree || target` is just `tree`. */
	static function disjunctSubsumedBy(tree:BoolNode, target:BoolNode):Bool {
		return switch (tree) {
			case BOr(x, y): boolEq(x, target) || boolEq(y, target)
				|| disjunctSubsumedBy(x, target) || disjunctSubsumedBy(y, target);
			default: false;
		};
	}

	public static function simplifyScalar(n:ScalarNode):ScalarNode {
		return switch (n) {
			case KArith(op, a, b):
				var sa = simplifyScalar(a);
				var sb = simplifyScalar(b);
				switch [sa, sb] {
					case [KConst(x), KConst(y)]: KConst(foldArith(op, x, y));
					default:
						if ((op == "+" || op == "-") && isZero(sb)) sa
						else if (op == "+" && isZero(sa)) sb
						else if (op == "*" && isOne(sb)) sa
						else if (op == "*" && isOne(sa)) sb
						else if (op == "*" && (isZero(sa) || isZero(sb))) KConst(0.0)
						else if ((op == "min" || op == "max") && scalarEq(sa, sb)) sa
						else KArith(op, sa, sb);
				}
			// Explicit (not folded into the `default` below): the wrapper must be preserved, so this
			// needs to actually recurse+rewrap rather than fall through to "return unchanged".
			case KHole(inner): KHole(simplifyScalar(inner));
			default: n; // KConst/KParam/KFeature/KSeries/KLookback are already minimal
		};
	}

	static function isZero(n:ScalarNode):Bool return switch (n) { case KConst(v): v == 0.0; default: false; }
	static function isOne(n:ScalarNode):Bool return switch (n) { case KConst(v): v == 1.0; default: false; }

	static function foldArith(op:String, a:Float, b:Float):Float {
		return switch (op) {
			case "+": a + b;
			case "-": a - b;
			case "*": a * b;
			case "min": Math.min(a, b);
			case "max": Math.max(a, b);
			default: a; // unknown op -- shouldn't happen (Palette.ARITH is closed), leave inert
		};
	}

	/** True if any organ has BAnd/BOr/BNot/BHole — the only shapes `simplifyBool` can shrink. */
	public static function hasCompoundBool(g:StrategyGenome):Bool {
		return compoundBool(g.entryLong) || compoundBool(g.entryShort)
			|| compoundBool(g.exitLong) || compoundBool(g.exitShort);
	}

	static function compoundBool(n:BoolNode):Bool {
		return switch (n) {
			case BAnd(_, _) | BOr(_, _) | BNot(_): true;
			case BHole(inner): true; // keep hole walks; content may still fold
			default: false;
		};
	}

	/** Simplify every slot of a genome and drop any `@param` the simplification made unreferenced
	 * (e.g. folding away the ONLY `BCmp` that read a given `KParam`) -- `variation.compactParams`
	 * already does exactly that renumbering/dropping, reused here rather than duplicated. */
	public static function simplifyGenome(g:StrategyGenome, variation:Variation):StrategyGenome {
		var out:StrategyGenome = {
			entryLong: simplifyBool(g.entryLong),
			entryShort: simplifyBool(g.entryShort),
			exitLong: simplifyBool(g.exitLong),
			exitShort: simplifyBool(g.exitShort),
			size: simplifyScalar(g.size),
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin,
			// Preserve host projections (genome identity) — same drop bug compactParams had: this
			// rebuild runs BEFORE compactParams, so omitting the field nulls the PSHost decl before
			// the fix downstream can help. Simplify never touches SProj reads or projection nodes.
			projections: g.projections,
			panelAction: g.panelAction
		};
		return variation.compactParams(out);
	}
}

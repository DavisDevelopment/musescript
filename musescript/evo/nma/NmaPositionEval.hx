package musescript.evo.nma;

import musescript.harness.Bar;
import musescript.harness.OrderSim;
import musescript.indicators.GrowableVec;
// Explicit family-module imports for the SECONDARY concrete types the kind-switches cast to.
import musescript.evo.nma.NmaScalar;
import musescript.evo.nma.NmaBool;

/**
 * Per-bar evaluation of the parts of a genome that depend on simulator state, over columns for
 * the parts that do not.
 *
 * Columnar evaluation (`NmaEval`) needs every input known before the simulation starts. Two
 * builtins break that: `unrealized_pnl_pct()` and `bars_in_trade()` read the position, which
 * exists only once the simulation is running, which in turn depends on the signals being
 * computed. That feedback loop used to be answered by refusing the whole genome and handing it
 * to the tree-walking interpreter -- measured at 17-30 ms against ~0.24 ms for a columnar
 * genome, and the single largest cost in the engine despite affecting ~10% of evaluations.
 *
 * The loop is far narrower than the all-or-nothing fallback implied. Position state can only
 * enter through a `KFeature` scalar, so:
 *
 *  - `SPrice`/`SInd` and therefore `BCross`/`BTrend` can NEVER be coupled -- the series grammar
 *    has no way to name a feature. Every stateful primitive in `NmaEval` (the cross's `prev`,
 *    the trend's ring buffer) lives behind one of those, so none of them is ever reached here
 *    and this evaluator needs no cross-bar state of its own.
 *  - Coupling enters at `BCmp` over a coupled scalar and propagates up through `BAnd`/`BOr`/
 *    `BNot`/`BHole`, and within scalars through `KArith`/`KHole`.
 *
 * So a coupled tree is a thin spine of logic over mostly-pure operands. `warmBool` evaluates
 * every maximal pure subtree ONCE as a column -- keeping the memo and population-share wins
 * intact for the bulk of the work -- and the per-bar walk then only re-does the spine, reading
 * `.at(i)` wherever it meets a pure node.
 *
 * Parity discipline: `arith`/`compare` below mirror `NmaEval`'s, quirk for quirk (including the
 * `min`/`max` operand drop). `&&`/`||` short-circuit here where `NmaEval.logic2` does not; that
 * is unobservable, because the difference can only matter for a side effect and the pure operand
 * was already evaluated by `warmBool` on every bar. It also matches what the compiled render
 * does, which short-circuits too.
 *
 * «ῥεῖ τὸ ὕδωρ ἄνω· ὁ ἵππος τὸν ἀναβάτην ἐλαύνει.»
 */
class NmaPositionEval {
	/** Does this subtree read simulator state? Cached on the node; cleared by `invalidate`. */
	public static function isCoupled(node:NmaNode):Bool {
		var c = node.posCoupledCache;
		if (c >= 0) return c == 1;
		var coupled = switch (node.kind) {
			case KFeature: NmaFeatureHost.isPositionFeature((cast node : NmaKFeature).name);
			default:
				var any = false;
				var n = node.childCount();
				var i = 0;
				while (i < n) {
					if (isCoupled(node.childAt(i))) { any = true; break; }
					i++;
				}
				any;
		};
		node.posCoupledCache = coupled ? 1 : 0;
		return coupled;
	}

	// ---------- warm: every maximal pure subtree becomes a column, once ----------

	public static function warmBool(node:NmaBool, ctx:NmaEvalContext):Void {
		if (!isCoupled(node)) { NmaEval.evalBool(node, ctx); return; }
		switch (node.kind) {
			case BAnd:
				var a = (cast node : NmaBAnd);
				warmBool(a.a, ctx);
				warmBool(a.b, ctx);
			case BOr:
				var o = (cast node : NmaBOr);
				warmBool(o.a, ctx);
				warmBool(o.b, ctx);
			case BNot: warmBool((cast node : NmaBNot).a, ctx);
			case BHole: warmBool((cast node : NmaBHole).inner, ctx);
			case BCmp:
				var c = (cast node : NmaBCmp);
				warmScalar(c.a, ctx);
				warmScalar(c.b, ctx);
			default: // BCross/BTrend cannot be coupled -- see the class comment.
		}
	}

	public static function warmScalar(node:NmaScalar, ctx:NmaEvalContext):Void {
		if (!isCoupled(node)) { NmaEval.evalScalar(node, ctx); return; }
		switch (node.kind) {
			case KArith:
				var a = (cast node : NmaKArith);
				warmScalar(a.a, ctx);
				warmScalar(a.b, ctx);
			case KHole: warmScalar((cast node : NmaKHole).inner, ctx);
			default: // the coupled KFeature leaf itself -- nothing to precompute.
		}
	}

	// ---------- per-bar ----------

	public static function boolAt(node:NmaBool, ctx:NmaEvalContext, i:Int, orders:OrderSim, bar:Bar):Bool {
		if (!isCoupled(node)) return boolColumn(node, ctx).at(i) >= 0.5;
		return switch (node.kind) {
			case BAnd:
				var a = (cast node : NmaBAnd);
				boolAt(a.a, ctx, i, orders, bar) && boolAt(a.b, ctx, i, orders, bar);
			case BOr:
				var o = (cast node : NmaBOr);
				boolAt(o.a, ctx, i, orders, bar) || boolAt(o.b, ctx, i, orders, bar);
			case BNot: !boolAt((cast node : NmaBNot).a, ctx, i, orders, bar);
			case BHole: boolAt((cast node : NmaBHole).inner, ctx, i, orders, bar);
			case BCmp:
				var c = (cast node : NmaBCmp);
				compare(c.op, scalarAt(c.a, ctx, i, orders, bar), scalarAt(c.b, ctx, i, orders, bar));
			default: false;
		};
	}

	public static function scalarAt(node:NmaScalar, ctx:NmaEvalContext, i:Int, orders:OrderSim, bar:Bar):Float {
		if (!isCoupled(node)) return scalarColumn(node, ctx).at(i);
		return switch (node.kind) {
			case KFeature: featureAt((cast node : NmaKFeature).name, orders, bar);
			case KArith:
				var a = (cast node : NmaKArith);
				arith(a.op, scalarAt(a.a, ctx, i, orders, bar), scalarAt(a.b, ctx, i, orders, bar));
			case KHole: scalarAt((cast node : NmaKHole).inner, ctx, i, orders, bar);
			default: Math.NaN;
		};
	}

	/**
	 * The two simulator-coupled builtins, mirroring `TradeBuiltins`' registrations exactly.
	 * `unrealized_pnl_pct` is tested BEFORE `unrealized_pnl` because the former's name has the
	 * latter as a prefix. Despite the name it is a FRACTION, not a percentage: the raw P&L over
	 * the position's own notional, direction-normalized by `unrealizedPnl`'s sign so one
	 * threshold works for longs and shorts alike.
	 */
	static function featureAt(name:String, orders:OrderSim, bar:Bar):Float {
		if (StringTools.startsWith(name, "unrealized_pnl_pct")) {
			var pos = orders.positionSize();
			var entry = orders.entryPrice;
			if (pos == 0 || entry == 0) return 0.0;
			return orders.unrealizedPnl(bar.close) / (Math.abs(pos) * entry);
		}
		if (StringTools.startsWith(name, "unrealized_pnl")) return orders.unrealizedPnl(bar.close);
		if (StringTools.startsWith(name, "bars_in_trade")) return orders.barsInTrade(bar.index);
		return Math.NaN;
	}

	static inline function boolColumn(node:NmaBool, ctx:NmaEvalContext):GrowableVec<Float> {
		var memo = node.lastSeries;
		return (node.evalEpoch == ctx.epoch.id && memo != null) ? memo : NmaEval.evalBool(node, ctx);
	}

	static inline function scalarColumn(node:NmaScalar, ctx:NmaEvalContext):GrowableVec<Float> {
		var memo = node.lastSeries;
		return (node.evalEpoch == ctx.epoch.id && memo != null) ? memo : NmaEval.evalScalar(node, ctx);
	}

	/** Scalar mirror of `NmaEval.arith`, including the `min`/`max` operand-drop parity quirk. */
	static inline function arith(op:String, x:Float, y:Float):Float {
		return switch (op) {
			case "+": x + y;
			case "-": x - y;
			case "*": x * y;
			case "/": x / y;
			case "min" | "max": x;
			default: Math.NaN;
		};
	}

	/** Scalar mirror of `NmaEval.compare`. NaN compares false, as on the compiled path. */
	static inline function compare(op:String, x:Float, y:Float):Bool {
		return switch (op) {
			case ">": x > y;
			case "<": x < y;
			case ">=": x >= y;
			case "<=": x <= y;
			case "==": x == y;
			case "!=": x != y;
			default: false;
		};
	}
}

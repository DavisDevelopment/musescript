package musescript.evo;

/**
 * Generic preorder traversal + point replacement across BoolNode/ScalarNode/SeriesNode,
 * porting musegene/variation.py's `_preorder`/`_replace` (Python) into Haxe.
 *
 * Python locates "this exact node" by OBJECT IDENTITY (`node is target`) — Haxe enum values
 * compare structurally, not by reference, so two different nodes with the same shape would be
 * indistinguishable that way. This uses PATHS (a sequence of left/right child steps) instead:
 * `collect*` walks a tree recording each node's path alongside it, `replace*` walks the SAME
 * path again to rebuild. Index/path-based tree surgery, not identity-based — arguably cleaner
 * for a value-typed language than trying to force Python's approach through.
 *
 * `replace*` functions are named `replace<RootKind>With<TargetKind>` — the target kind is
 * always known statically at the call site (from which `collect*` catalog it came from), so
 * there's never a need to replace a Bool position with a Scalar, etc.
 */
enum GStep {
	StepA;
	StepB;
}

typedef GPath = Array<GStep>;

class TreeSurgery {
	// ---- collect: catalog every node of each kind reachable from a root, with its path ----

	public static function collectBool(n:BoolNode, path:GPath, out:Array<{path:GPath, node:BoolNode}>):Void {
		out.push({ path: path, node: n });
		switch (n) {
			case BCross(_, _, _):
			case BCmp(_, _, _):
			case BTrend(_, _, _):
			case BAnd(a, b) | BOr(a, b):
				collectBool(a, path.concat([StepA]), out);
				collectBool(b, path.concat([StepB]), out);
			case BNot(a):
				collectBool(a, path.concat([StepA]), out);
		}
	}

	public static function collectScalarInBool(n:BoolNode, path:GPath, out:Array<{path:GPath, node:ScalarNode}>):Void {
		switch (n) {
			case BCross(_, _, _):
			case BCmp(_, a, b):
				collectScalar(a, path.concat([StepA]), out);
				collectScalar(b, path.concat([StepB]), out);
			case BTrend(_, _, _):
			case BAnd(a, b) | BOr(a, b):
				collectScalarInBool(a, path.concat([StepA]), out);
				collectScalarInBool(b, path.concat([StepB]), out);
			case BNot(a):
				collectScalarInBool(a, path.concat([StepA]), out);
		}
	}

	public static function collectSeriesInBool(n:BoolNode, path:GPath, out:Array<{path:GPath, node:SeriesNode}>):Void {
		switch (n) {
			case BCross(_, a, b):
				collectSeries(a, path.concat([StepA]), out);
				collectSeries(b, path.concat([StepB]), out);
			case BCmp(_, a, b):
				collectSeriesInScalar(a, path.concat([StepA]), out);
				collectSeriesInScalar(b, path.concat([StepB]), out);
			case BTrend(_, s, _):
				collectSeries(s, path.concat([StepA]), out);
			case BAnd(a, b) | BOr(a, b):
				collectSeriesInBool(a, path.concat([StepA]), out);
				collectSeriesInBool(b, path.concat([StepB]), out);
			case BNot(a):
				collectSeriesInBool(a, path.concat([StepA]), out);
		}
	}

	public static function collectScalar(n:ScalarNode, path:GPath, out:Array<{path:GPath, node:ScalarNode}>):Void {
		out.push({ path: path, node: n });
		switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KSeries(_) | KLookback(_, _):
			case KArith(_, a, b):
				collectScalar(a, path.concat([StepA]), out);
				collectScalar(b, path.concat([StepB]), out);
		}
	}

	public static function collectSeriesInScalar(n:ScalarNode, path:GPath, out:Array<{path:GPath, node:SeriesNode}>):Void {
		switch (n) {
			case KConst(_) | KParam(_) | KFeature(_):
			case KSeries(s):
				collectSeries(s, path.concat([StepA]), out);
			case KLookback(s, _):
				collectSeries(s, path.concat([StepA]), out);
			case KArith(_, a, b):
				collectSeriesInScalar(a, path.concat([StepA]), out);
				collectSeriesInScalar(b, path.concat([StepB]), out);
		}
	}

	public static function collectSeries(n:SeriesNode, path:GPath, out:Array<{path:GPath, node:SeriesNode}>):Void {
		out.push({ path: path, node: n });
		switch (n) {
			case SPrice(_):
			case SInd(_, _, _, src):
				if (src != null) collectSeries(src, path.concat([StepA]), out);
		}
	}

	// ---- replace: rebuild along a path recorded by the matching collect* above ----

	public static function replaceBoolWithBool(n:BoolNode, path:GPath, repl:BoolNode):BoolNode {
		if (path.length == 0) return repl;
		var step = path[0];
		var rest = path.slice(1);
		return switch (n) {
			case BCross(_, _, _) | BCmp(_, _, _) | BTrend(_, _, _):
				throw "TreeSurgery.replaceBoolWithBool: path ran past a leaf-of-bool-kind node";
			case BAnd(a, b):
				step == StepA ? BAnd(replaceBoolWithBool(a, rest, repl), b) : BAnd(a, replaceBoolWithBool(b, rest, repl));
			case BOr(a, b):
				step == StepA ? BOr(replaceBoolWithBool(a, rest, repl), b) : BOr(a, replaceBoolWithBool(b, rest, repl));
			case BNot(a):
				BNot(replaceBoolWithBool(a, rest, repl));
		};
	}

	public static function replaceBoolWithScalar(n:BoolNode, path:GPath, repl:ScalarNode):BoolNode {
		var step = path[0];
		var rest = path.slice(1);
		return switch (n) {
			case BCross(_, _, _) | BTrend(_, _, _):
				throw "TreeSurgery.replaceBoolWithScalar: no scalar child here";
			case BCmp(op, a, b):
				step == StepA ? BCmp(op, replaceScalarWithScalar(a, rest, repl), b) : BCmp(op, a, replaceScalarWithScalar(b, rest, repl));
			case BAnd(a, b):
				step == StepA ? BAnd(replaceBoolWithScalar(a, rest, repl), b) : BAnd(a, replaceBoolWithScalar(b, rest, repl));
			case BOr(a, b):
				step == StepA ? BOr(replaceBoolWithScalar(a, rest, repl), b) : BOr(a, replaceBoolWithScalar(b, rest, repl));
			case BNot(a):
				BNot(replaceBoolWithScalar(a, rest, repl));
		};
	}

	public static function replaceBoolWithSeries(n:BoolNode, path:GPath, repl:SeriesNode):BoolNode {
		var step = path[0];
		var rest = path.slice(1);
		return switch (n) {
			case BCross(dir, a, b):
				step == StepA ? BCross(dir, replaceSeriesWithSeries(a, rest, repl), b) : BCross(dir, a, replaceSeriesWithSeries(b, rest, repl));
			case BCmp(op, a, b):
				step == StepA ? BCmp(op, replaceSeriesInScalarWithSeries(a, rest, repl), b) : BCmp(op, a, replaceSeriesInScalarWithSeries(b, rest, repl));
			case BTrend(dir, s, w):
				BTrend(dir, replaceSeriesWithSeries(s, rest, repl), w);
			case BAnd(a, b):
				step == StepA ? BAnd(replaceBoolWithSeries(a, rest, repl), b) : BAnd(a, replaceBoolWithSeries(b, rest, repl));
			case BOr(a, b):
				step == StepA ? BOr(replaceBoolWithSeries(a, rest, repl), b) : BOr(a, replaceBoolWithSeries(b, rest, repl));
			case BNot(a):
				BNot(replaceBoolWithSeries(a, rest, repl));
		};
	}

	public static function replaceScalarWithScalar(n:ScalarNode, path:GPath, repl:ScalarNode):ScalarNode {
		if (path.length == 0) return repl;
		var step = path[0];
		var rest = path.slice(1);
		return switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KSeries(_) | KLookback(_, _):
				throw "TreeSurgery.replaceScalarWithScalar: path ran past a scalar leaf";
			case KArith(op, a, b):
				step == StepA ? KArith(op, replaceScalarWithScalar(a, rest, repl), b) : KArith(op, a, replaceScalarWithScalar(b, rest, repl));
		};
	}

	public static function replaceSeriesInScalarWithSeries(n:ScalarNode, path:GPath, repl:SeriesNode):ScalarNode {
		var step = path[0];
		var rest = path.slice(1);
		return switch (n) {
			case KConst(_) | KParam(_) | KFeature(_):
				throw "TreeSurgery.replaceSeriesInScalarWithSeries: no series child here";
			case KSeries(s):
				KSeries(replaceSeriesWithSeries(s, rest, repl));
			case KLookback(s, k):
				KLookback(replaceSeriesWithSeries(s, rest, repl), k);
			case KArith(op, a, b):
				step == StepA ? KArith(op, replaceSeriesInScalarWithSeries(a, rest, repl), b) : KArith(op, a, replaceSeriesInScalarWithSeries(b, rest, repl));
		};
	}

	public static function replaceSeriesWithSeries(n:SeriesNode, path:GPath, repl:SeriesNode):SeriesNode {
		if (path.length == 0) return repl;
		return switch (n) {
			case SPrice(_):
				throw "TreeSurgery.replaceSeriesWithSeries: path ran past a price leaf";
			case SInd(name, field, window, src):
				SInd(name, field, window, src != null ? replaceSeriesWithSeries(src, path.slice(1), repl) : null);
		};
	}
}

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

	/**
	 * `armed` (default `true` -- exact prior behavior for every existing call site, none of which
	 * pass this new 4th/5th arg) gates whether a visited node gets RECORDED as a candidate. It
	 * starts `false` only when a caller (`Variation.buildCatalog`, for a genome `isTemplated`)
	 * deliberately wants a hole-restricted catalog; every node is still WALKED regardless of
	 * `armed` (so a `BHole`/`KHole` nested arbitrarily deep inside frozen skeleton is still found),
	 * but only recorded once `armed` has flipped `true` -- which happens permanently for that whole
	 * subtree the instant a `BHole`/`KHole` boundary is crossed (see the `BHole`/`KHole` cases
	 * below). The boundary node itself is never recorded (only its `inner`), so a catalog entry can
	 * never resolve to a path that would let `replace*` delete the wrapper -- see `replaceBoolWithBool`'s
	 * `BHole` case, which always reconstructs `BHole(...)` around the replaced child.
	 */
	/**
	 * `path` is a MUTABLE scratch buffer, pushed/popped around each recursive descent instead of
	 * `.concat()`-ing a fresh array at every tree level (the JIT audit that motivated this file's
	 * `collect*`/`replace*` rewrite found this was the single largest allocation source in the
	 * evo package's per-child overhead: O(nodes × depth) short-lived arrays, since `buildCatalog`
	 * runs up to 6 of these traversals per genome and genome-child production happens hundreds of
	 * times per generation). A path is copied ONCE, only at the point a node is actually recorded
	 * (`out.push`) -- every caller already passes a throwaway `[]` literal it never reads after
	 * the call, so mutating it in place during the walk is invisible externally; the recorded
	 * `path` values are still independent, fully-owned array copies, byte-identical to before.
	 */
	public static function collectBool(n:BoolNode, path:GPath, out:Array<{path:GPath, node:BoolNode}>, ?armed:Bool = true):Void {
		if (armed) out.push({ path: path.copy(), node: n });
		switch (n) {
			case BCross(_, _, _):
			case BCmp(_, _, _):
			case BTrend(_, _, _):
			case BAnd(a, b) | BOr(a, b):
				path.push(StepA); collectBool(a, path, out, armed); path.pop();
				path.push(StepB); collectBool(b, path, out, armed); path.pop();
			case BNot(a):
				path.push(StepA); collectBool(a, path, out, armed); path.pop();
			case BHole(inner):
				path.push(StepA); collectBool(inner, path, out, true); path.pop();
			case BFeature(_): // opaque leaf: recorded as a whole-leaf site above, no children to recurse
		}
	}

	/**
	 * Same preorder as `collectBool`, but only the path copies Variation catalogs keep.
	 * The `{path, node}` wrapper was throwaway on every attributed child.
	 */
	public static function collectBoolPaths(n:BoolNode, path:GPath, out:Array<GPath>, ?armed:Bool = true):Void {
		if (armed) out.push(path.copy());
		switch (n) {
			case BCross(_, _, _) | BCmp(_, _, _) | BTrend(_, _, _) | BFeature(_):
			case BAnd(a, b) | BOr(a, b):
				path.push(StepA); collectBoolPaths(a, path, out, armed); path.pop();
				path.push(StepB); collectBoolPaths(b, path, out, armed); path.pop();
			case BNot(a):
				path.push(StepA); collectBoolPaths(a, path, out, armed); path.pop();
			case BHole(inner):
				path.push(StepA); collectBoolPaths(inner, path, out, true); path.pop();
		}
	}

	/**
	 * Same preorder as `collectBool`, nodes only — donor pools never read the path.
	 * Skipping `path.copy()` here is the whole point (O(nodes × depth) garbage per unique genome).
	 */
	public static function collectBoolNodes(n:BoolNode, out:Array<BoolNode>, ?armed:Bool = true):Void {
		if (armed) out.push(n);
		switch (n) {
			case BCross(_, _, _) | BCmp(_, _, _) | BTrend(_, _, _) | BFeature(_):
			case BAnd(a, b) | BOr(a, b):
				collectBoolNodes(a, out, armed);
				collectBoolNodes(b, out, armed);
			case BNot(a):
				collectBoolNodes(a, out, armed);
			case BHole(inner):
				collectBoolNodes(inner, out, true);
		}
	}

	public static function collectScalarInBool(n:BoolNode, path:GPath, out:Array<{path:GPath, node:ScalarNode}>, ?armed:Bool = true):Void {
		switch (n) {
			case BCross(_, _, _):
			case BCmp(_, a, b):
				path.push(StepA); collectScalar(a, path, out, armed); path.pop();
				path.push(StepB); collectScalar(b, path, out, armed); path.pop();
			case BTrend(_, _, _):
			case BAnd(a, b) | BOr(a, b):
				path.push(StepA); collectScalarInBool(a, path, out, armed); path.pop();
				path.push(StepB); collectScalarInBool(b, path, out, armed); path.pop();
			case BNot(a):
				path.push(StepA); collectScalarInBool(a, path, out, armed); path.pop();
			case BHole(inner):
				path.push(StepA); collectScalarInBool(inner, path, out, true); path.pop();
			case BFeature(_): // opaque leaf: no scalar children
		}
	}

	public static function collectSeriesInBool(n:BoolNode, path:GPath, out:Array<{path:GPath, node:SeriesNode}>, ?armed:Bool = true):Void {
		switch (n) {
			case BCross(_, a, b):
				path.push(StepA); collectSeries(a, path, out, armed); path.pop();
				path.push(StepB); collectSeries(b, path, out, armed); path.pop();
			case BCmp(_, a, b):
				path.push(StepA); collectSeriesInScalar(a, path, out, armed); path.pop();
				path.push(StepB); collectSeriesInScalar(b, path, out, armed); path.pop();
			case BTrend(_, s, _):
				path.push(StepA); collectSeries(s, path, out, armed); path.pop();
			case BAnd(a, b) | BOr(a, b):
				path.push(StepA); collectSeriesInBool(a, path, out, armed); path.pop();
				path.push(StepB); collectSeriesInBool(b, path, out, armed); path.pop();
			case BNot(a):
				path.push(StepA); collectSeriesInBool(a, path, out, armed); path.pop();
			case BHole(inner):
				path.push(StepA); collectSeriesInBool(inner, path, out, true); path.pop();
			case BFeature(_): // opaque leaf: no series children
		}
	}

	public static function collectScalar(n:ScalarNode, path:GPath, out:Array<{path:GPath, node:ScalarNode}>, ?armed:Bool = true):Void {
		if (armed) out.push({ path: path.copy(), node: n });
		switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KSeries(_) | KLookback(_, _) | KNp(_, _, _, _) | KPd(_, _, _, _, _):
			case KArith(_, a, b):
				path.push(StepA); collectScalar(a, path, out, armed); path.pop();
				path.push(StepB); collectScalar(b, path, out, armed); path.pop();
			case KHole(inner):
				path.push(StepA); collectScalar(inner, path, out, true); path.pop();
		}
	}

	public static function collectSeriesInScalar(n:ScalarNode, path:GPath, out:Array<{path:GPath, node:SeriesNode}>, ?armed:Bool = true):Void {
		switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KPd(_, _, _, _, _):
			case KSeries(s):
				path.push(StepA); collectSeries(s, path, out, armed); path.pop();
			case KLookback(s, _):
				path.push(StepA); collectSeries(s, path, out, armed); path.pop();
			case KNp(_, a, _, b):
				path.push(StepA); collectSeries(a, path, out, armed); path.pop();
				if (b != null) { path.push(StepB); collectSeries(b, path, out, armed); path.pop(); }
			case KArith(_, a, b):
				path.push(StepA); collectSeriesInScalar(a, path, out, armed); path.pop();
				path.push(StepB); collectSeriesInScalar(b, path, out, armed); path.pop();
			case KHole(inner):
				path.push(StepA); collectSeriesInScalar(inner, path, out, true); path.pop();
		}
	}

	public static function collectSeries(n:SeriesNode, path:GPath, out:Array<{path:GPath, node:SeriesNode}>, ?armed:Bool = true):Void {
		if (armed) out.push({ path: path.copy(), node: n });
		switch (n) {
			case SPrice(_):
			case SProj(_, _): // projection reference is a leaf — no child series to recurse into
			case SPanel(_, _, _, _): // literal panel-of leaf
			case SInd(_, _, _, src):
				if (src != null) { path.push(StepA); collectSeries(src, path, out, armed); path.pop(); }
		}
	}

	// ---- replace: rebuild along a path recorded by the matching collect* above ----

	/**
	 * Public entry points keep their original 3-arg signature (path always starting at index 0);
	 * each delegates to a private `*At(n, path, repl, idx)` twin that reads/advances an INDEX
	 * into the same shared `path` array instead of `path.slice(1)` -- a replace walk is at most
	 * `path.length` calls deep (bounded by genome depth, not tree size, so this was always a much
	 * smaller allocation source than `collect*`'s per-level `.concat()`), but it's free to remove
	 * once `collect*` above already established the "index/buffer instead of copy-per-level"
	 * pattern for this file.
	 */
	public static function replaceBoolWithBool(n:BoolNode, path:GPath, repl:BoolNode):BoolNode
		return replaceBoolWithBoolAt(n, path, repl, 0);

	/** Resolve the bool node at `path` (empty path → `n`).
	 *
	 * Used by P2 credit lookup and semantic-RDO site reads without a replace round-trip.
	 */
	public static function getBool(n:BoolNode, path:GPath):BoolNode
		return getBoolAt(n, path, 0);

	static function getBoolAt(n:BoolNode, path:GPath, idx:Int):BoolNode {
		if (idx >= path.length) return n;
		var step = path[idx];
		return switch (n) {
			case BAnd(a, b):
				getBoolAt(step == StepA ? a : b, path, idx + 1);
			case BOr(a, b):
				getBoolAt(step == StepA ? a : b, path, idx + 1);
			case BNot(a):
				getBoolAt(a, path, idx + 1);
			case BHole(inner):
				getBoolAt(inner, path, idx + 1);
			case BCross(_, _, _) | BCmp(_, _, _) | BTrend(_, _, _) | BFeature(_):
				throw "TreeSurgery.getBool: path ran past a leaf-of-bool-kind node";
		};
	}

	static function replaceBoolWithBoolAt(n:BoolNode, path:GPath, repl:BoolNode, idx:Int):BoolNode {
		if (idx >= path.length) return repl;
		var step = path[idx];
		return switch (n) {
			case BCross(_, _, _) | BCmp(_, _, _) | BTrend(_, _, _) | BFeature(_):
				throw "TreeSurgery.replaceBoolWithBool: path ran past a leaf-of-bool-kind node";
			case BAnd(a, b):
				step == StepA ? BAnd(replaceBoolWithBoolAt(a, path, repl, idx + 1), b) : BAnd(a, replaceBoolWithBoolAt(b, path, repl, idx + 1));
			case BOr(a, b):
				step == StepA ? BOr(replaceBoolWithBoolAt(a, path, repl, idx + 1), b) : BOr(a, replaceBoolWithBoolAt(b, path, repl, idx + 1));
			case BNot(a):
				BNot(replaceBoolWithBoolAt(a, path, repl, idx + 1));
			case BHole(inner):
				BHole(replaceBoolWithBoolAt(inner, path, repl, idx + 1));
		};
	}

	public static function replaceBoolWithScalar(n:BoolNode, path:GPath, repl:ScalarNode):BoolNode
		return replaceBoolWithScalarAt(n, path, repl, 0);

	static function replaceBoolWithScalarAt(n:BoolNode, path:GPath, repl:ScalarNode, idx:Int):BoolNode {
		var step = path[idx];
		return switch (n) {
			case BCross(_, _, _) | BTrend(_, _, _) | BFeature(_):
				throw "TreeSurgery.replaceBoolWithScalar: no scalar child here";
			case BCmp(op, a, b):
				step == StepA ? BCmp(op, replaceScalarWithScalarAt(a, path, repl, idx + 1), b) : BCmp(op, a, replaceScalarWithScalarAt(b, path, repl, idx + 1));
			case BAnd(a, b):
				step == StepA ? BAnd(replaceBoolWithScalarAt(a, path, repl, idx + 1), b) : BAnd(a, replaceBoolWithScalarAt(b, path, repl, idx + 1));
			case BOr(a, b):
				step == StepA ? BOr(replaceBoolWithScalarAt(a, path, repl, idx + 1), b) : BOr(a, replaceBoolWithScalarAt(b, path, repl, idx + 1));
			case BNot(a):
				BNot(replaceBoolWithScalarAt(a, path, repl, idx + 1));
			case BHole(inner):
				BHole(replaceBoolWithScalarAt(inner, path, repl, idx + 1));
		};
	}

	public static function replaceBoolWithSeries(n:BoolNode, path:GPath, repl:SeriesNode):BoolNode
		return replaceBoolWithSeriesAt(n, path, repl, 0);

	static function replaceBoolWithSeriesAt(n:BoolNode, path:GPath, repl:SeriesNode, idx:Int):BoolNode {
		var step = path[idx];
		return switch (n) {
			case BCross(dir, a, b):
				step == StepA ? BCross(dir, replaceSeriesWithSeriesAt(a, path, repl, idx + 1), b) : BCross(dir, a, replaceSeriesWithSeriesAt(b, path, repl, idx + 1));
			case BCmp(op, a, b):
				step == StepA ? BCmp(op, replaceSeriesInScalarWithSeriesAt(a, path, repl, idx + 1), b) : BCmp(op, a, replaceSeriesInScalarWithSeriesAt(b, path, repl, idx + 1));
			case BTrend(dir, s, w):
				BTrend(dir, replaceSeriesWithSeriesAt(s, path, repl, idx + 1), w);
			case BAnd(a, b):
				step == StepA ? BAnd(replaceBoolWithSeriesAt(a, path, repl, idx + 1), b) : BAnd(a, replaceBoolWithSeriesAt(b, path, repl, idx + 1));
			case BOr(a, b):
				step == StepA ? BOr(replaceBoolWithSeriesAt(a, path, repl, idx + 1), b) : BOr(a, replaceBoolWithSeriesAt(b, path, repl, idx + 1));
			case BNot(a):
				BNot(replaceBoolWithSeriesAt(a, path, repl, idx + 1));
			case BHole(inner):
				BHole(replaceBoolWithSeriesAt(inner, path, repl, idx + 1));
			case BFeature(_):
				throw "TreeSurgery.replaceBoolWithSeries: no series child here";
		};
	}

	public static function replaceScalarWithScalar(n:ScalarNode, path:GPath, repl:ScalarNode):ScalarNode
		return replaceScalarWithScalarAt(n, path, repl, 0);

	static function replaceScalarWithScalarAt(n:ScalarNode, path:GPath, repl:ScalarNode, idx:Int):ScalarNode {
		if (idx >= path.length) return repl;
		var step = path[idx];
		return switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KSeries(_) | KLookback(_, _) | KNp(_, _, _, _) | KPd(_, _, _, _, _):
				throw "TreeSurgery.replaceScalarWithScalar: path ran past a scalar leaf";
			case KArith(op, a, b):
				step == StepA ? KArith(op, replaceScalarWithScalarAt(a, path, repl, idx + 1), b) : KArith(op, a, replaceScalarWithScalarAt(b, path, repl, idx + 1));
			case KHole(inner):
				KHole(replaceScalarWithScalarAt(inner, path, repl, idx + 1));
		};
	}

	public static function replaceSeriesInScalarWithSeries(n:ScalarNode, path:GPath, repl:SeriesNode):ScalarNode
		return replaceSeriesInScalarWithSeriesAt(n, path, repl, 0);

	static function replaceSeriesInScalarWithSeriesAt(n:ScalarNode, path:GPath, repl:SeriesNode, idx:Int):ScalarNode {
		var step = path[idx];
		return switch (n) {
			case KConst(_) | KParam(_) | KFeature(_) | KPd(_, _, _, _, _):
				throw "TreeSurgery.replaceSeriesInScalarWithSeries: no series child here";
			case KSeries(s):
				KSeries(replaceSeriesWithSeriesAt(s, path, repl, idx + 1));
			case KLookback(s, k):
				KLookback(replaceSeriesWithSeriesAt(s, path, repl, idx + 1), k);
			case KNp(op, a, w, b):
				if (step == StepA) KNp(op, replaceSeriesWithSeriesAt(a, path, repl, idx + 1), w, b);
				else if (b != null) KNp(op, a, w, replaceSeriesWithSeriesAt(b, path, repl, idx + 1));
				else throw "TreeSurgery.replaceSeriesInScalarWithSeries: KNp has no StepB child";
			case KArith(op, a, b):
				step == StepA ? KArith(op, replaceSeriesInScalarWithSeriesAt(a, path, repl, idx + 1), b) : KArith(op, a, replaceSeriesInScalarWithSeriesAt(b, path, repl, idx + 1));
			case KHole(inner):
				KHole(replaceSeriesInScalarWithSeriesAt(inner, path, repl, idx + 1));
		};
	}

	public static function replaceSeriesWithSeries(n:SeriesNode, path:GPath, repl:SeriesNode):SeriesNode
		return replaceSeriesWithSeriesAt(n, path, repl, 0);

	static function replaceSeriesWithSeriesAt(n:SeriesNode, path:GPath, repl:SeriesNode, idx:Int):SeriesNode {
		if (idx >= path.length) return repl;
		return switch (n) {
			case SPrice(_):
				throw "TreeSurgery.replaceSeriesWithSeries: path ran past a price leaf";
			case SProj(_, _):
				throw "TreeSurgery.replaceSeriesWithSeries: path ran past a projection leaf";
			case SPanel(_, _, _, _):
				throw "TreeSurgery.replaceSeriesWithSeries: path ran past a panel-of leaf";
			case SInd(name, field, window, src):
				SInd(name, field, window, src != null ? replaceSeriesWithSeriesAt(src, path, repl, idx + 1) : null);
		};
	}
}

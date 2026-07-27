package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import musescript.indicators.RingBuffer;
// Explicit family-module imports for the SECONDARY concrete node types the kind-switch casts to.
import musescript.evo.nma.NmaSeries;
import musescript.evo.nma.NmaScalar;
import musescript.evo.nma.NmaBool;

/**
 * The NMA columnar evaluator -- turns a genome's Series/Scalar/Bool trees into full per-bar output
 * COLUMNS over a tape, with per-node partial-eval memo. This is the P1 heart: instead of the
 * attribution oracle re-running a whole backtest to score a subtree, an equal subtree computes its
 * column ONCE per epoch and every reuse is a memo hit.
 *
 * Bit-exact-parity discipline:
 *  - Cheap structural/numeric/cross/trend primitives are implemented HERE, matching the compiled
 *    MuseScript semantics exactly: `crossover`/`crossunder`/`rising`/`falling` mirror
 *    `TradeBuiltins`' contract line-for-line (NaN handling, "first bar is false", the `n+1`-sample
 *    trend window), and are differential-tested against it.
 *  - `SInd` (indicator math) is the ONLY delegated case -- see `NmaIndicatorProvider`.
 *
 * GraalVM shape: every dispatch is a central `switch (node.kind)` + typed `cast` (a `tableswitch`,
 * monomorphic per case), never a virtual method over the 16 subclasses (see `NmaNode`). Columns are
 * `GrowableVec<Float>` (unboxed `double[]` on the JVM target); bool columns carry `0.0`/`1.0`.
 *
 * «στεφάνους πλέκει κισσός· μέθη σοφίαν δίδωσι.»
 */
class NmaEval {
	static inline var TRUE = 1.0;
	static inline var FALSE = 0.0;

	// ---------- series ----------

	public static function evalSeries(node:NmaSeries, ctx:NmaEvalContext):GrowableVec<Float> {
		if (node.evalEpoch == ctx.epoch.id && node.lastSeries != null) return node.lastSeries;
		if (node.kernel != null) return stamp(node, node.kernel.eval(ctx), ctx);
		var shared = popLookup(node, ctx, () -> NmaCanonical.ensureWordsSeries(node));
		if (shared != null) return stamp(node, shared, ctx);
		var col:GrowableVec<Float> = switch (node.kind) {
			case SPrice: ctx.priceColumn((cast node : NmaSPrice).field);
			case SInd: ctx.provider.seriesFor((cast node : NmaSInd), ctx);
			default: throw 'NmaEval.evalSeries: non-series kind ${node.kind}';
		};
		popStore(node, ctx, () -> NmaCanonical.ensureWordsSeries(node), col);
		return stamp(node, col, ctx);
	}

	// ---------- scalar ----------

	public static function evalScalar(node:NmaScalar, ctx:NmaEvalContext):GrowableVec<Float> {
		if (node.evalEpoch == ctx.epoch.id && node.lastSeries != null) return node.lastSeries;
		if (node.kernel != null) return stamp(node, node.kernel.eval(ctx), ctx);
		var shared = popLookup(node, ctx, () -> NmaCanonical.ensureWordsScalar(node));
		if (shared != null) return stamp(node, shared, ctx);
		var col:GrowableVec<Float> = switch (node.kind) {
			case KConst: constColumn((cast node : NmaKConst).v, ctx.n);
			case KParam:
				var idx = (cast node : NmaKParam).idx;
				constColumn(idx >= 0 && idx < ctx.params.length ? ctx.params[idx] : Math.NaN, ctx.n);
			case KFeature: ctx.featureColumn((cast node : NmaKFeature).name);
			case KSeries: evalSeries((cast node : NmaKSeries).s, ctx);
			case KLookback:
				var l = (cast node : NmaKLookback);
				lookback(evalSeries(l.s, ctx), l.n, ctx.n);
			case KArith:
				var a = (cast node : NmaKArith);
				arith(a.op, evalScalar(a.a, ctx), evalScalar(a.b, ctx), ctx.n);
			case KHole: evalScalar((cast node : NmaKHole).inner, ctx); // transparent
			default: throw 'NmaEval.evalScalar: non-scalar kind ${node.kind}';
		};
		popStore(node, ctx, () -> NmaCanonical.ensureWordsScalar(node), col);
		return stamp(node, col, ctx);
	}

	// ---------- bool (0.0 / 1.0 columns) ----------

	public static function evalBool(node:NmaBool, ctx:NmaEvalContext):GrowableVec<Float> {
		if (node.evalEpoch == ctx.epoch.id && node.lastSeries != null) {
			var hit = node.lastSeries;
			var hadWat = node.kernelWat != null;
			node.evalHits++;
			NmaKernelWarm.consider(node);
			// First warm attach busts local memo — fall through to fuse/recompute this call.
			if (hadWat || node.kernelWat == null || node.evalEpoch >= 0)
				return hit;
		}
		if (node.kernel != null) return stamp(node, node.kernel.eval(ctx), ctx);
		// Warm fuse BEFORE popMemo — otherwise a content-addressed hit skips the host forever.
		if (node.kernelWat != null) {
			switch (node.kind) {
				case BAnd:
					var a = (cast node : NmaBAnd);
					var ca = evalBool(a.a, ctx);
					var cb = evalBool(a.b, ctx);
					var colF = fuseOrLogic(ca, cb, true, ctx.n);
					popStore(node, ctx, () -> NmaCanonical.ensureWordsBool(node), colF);
					return stamp(node, colF, ctx);
				case BOr:
					var o = (cast node : NmaBOr);
					var oa = evalBool(o.a, ctx);
					var ob = evalBool(o.b, ctx);
					var colO = fuseOrLogic(oa, ob, false, ctx.n);
					popStore(node, ctx, () -> NmaCanonical.ensureWordsBool(node), colO);
					return stamp(node, colO, ctx);
				default:
			}
		}
		var shared = popLookup(node, ctx, () -> NmaCanonical.ensureWordsBool(node));
		if (shared != null) return stamp(node, shared, ctx);
		var col:GrowableVec<Float> = switch (node.kind) {
			case BCross:
				var c = (cast node : NmaBCross);
				// Expand.hx: dir=="over" -> crossover, else crossunder.
				cross(evalSeries(c.a, ctx), evalSeries(c.b, ctx), c.dir == "over", ctx.n);
			case BCmp:
				var c = (cast node : NmaBCmp);
				compare(c.op, evalScalar(c.a, ctx), evalScalar(c.b, ctx), ctx.n);
			case BTrend:
				var t = (cast node : NmaBTrend);
				// Expand.hx: dir=="over" -> rising, else falling.
				trend(evalSeries(t.s, ctx), t.window, t.dir == "over", ctx.n);
			case BAnd:
				var a = (cast node : NmaBAnd);
				logic2(evalBool(a.a, ctx), evalBool(a.b, ctx), true, ctx.n);
			case BOr:
				var o = (cast node : NmaBOr);
				logic2(evalBool(o.a, ctx), evalBool(o.b, ctx), false, ctx.n);
			case BNot: negate(evalBool((cast node : NmaBNot).a, ctx), ctx.n);
			case BHole: evalBool((cast node : NmaBHole).inner, ctx); // transparent
			default: throw 'NmaEval.evalBool: non-bool kind ${node.kind}';
		};
		popStore(node, ctx, () -> NmaCanonical.ensureWordsBool(node), col);
		return stamp(node, col, ctx);
	}

	// ---------- population column share: (tape, shape, referenced param values) ----------

	/** Shared immutable "no params below" result — the common case, alloc-free. */
	static final NO_REFS:Array<Int> = [];
	/** Sentinel refs for "subtree reads a KFeature" — context-local, never share its column. */
	static final FEATURE_REFS:Array<Int> = [-1];

	/**
	 * Sorted unique `KParam` indices in the subtree (cached on the node). A leading `-1` means a
	 * `KFeature` lives below. This is the entire genome-specific dependency surface of a signal
	 * column: everything else (prices, indicators) is tape-scoped.
	 */
	public static function refsOf(node:NmaNode):Array<Int> {
		var cached = node.paramRefsCache;
		if (cached != null) return cached;
		var out:Array<Int>;
		switch (node.kind) {
			case KParam:
				out = [(cast node : NmaKParam).idx];
			case KFeature:
				// Multi-output extracts (macd/bbands/stoch) are tape-pure and share freely.
				// A position-state feature is simulator-local: it has no column, and a subtree
				// above one must never be published to the population share even if some future
				// caller does evaluate it. `NmaPositionEval` keeps such subtrees off this path.
				out = NmaFeatureHost.isPositionFeature((cast node : NmaKFeature).name)
					? FEATURE_REFS : NO_REFS;
			default:
				var acc:Null<Array<Int>> = null;
				var n = node.childCount();
				for (i in 0...n) {
					var c = refsOf(node.childAt(i));
					if (c.length == 0) continue;
					acc = acc == null ? c : union(acc, c);
				}
				out = acc == null ? NO_REFS : acc;
		}
		node.paramRefsCache = out;
		return out;
	}

	/** Union of two sorted unique int arrays (tiny inputs; children's caches stay unmutated). */
	static function union(a:Array<Int>, b:Array<Int>):Array<Int> {
		var out = new Array<Int>();
		var i = 0, j = 0;
		while (i < a.length && j < b.length) {
			if (a[i] == b[j]) { out.push(a[i]); i++; j++; }
			else if (a[i] < b[j]) out.push(a[i++]);
			else out.push(b[j++]);
		}
		while (i < a.length) out.push(a[i++]);
		while (j < b.length) out.push(b[j++]);
		return out;
	}

	/**
	 * Population-share key for this node's column. Keyed by tape + shape + the VALUES of the params
	 * the subtree actually reads — NOT the genome's whole param vector (the old epoch prefix), which
	 * killed sharing for param-free subtrees whenever any unrelated param differed (measured: ~4%
	 * hit rate at pop=1000; most bool logic is param-free).
	 *
	 * Writes the avalanched `(a,b)` into `d.outA`/`d.outB`. Returns false when the column must stay
	 * private (KFeature below). No String, no `Std.string(Float)` — that path was ~62% of JVM
	 * allocation under `--nma` and is why the evaluation barrier did not shrink with `--threads`.
	 */
	static function colWords(node:NmaNode, shapeA:Int, shapeB:Int, ctx:NmaEvalContext,
			d:musescript.evo.StructuralDigest):Bool {
		var refs = refsOf(node);
		if (refs.length > 0 && refs[0] == -1) return false;
		d.word(ctx.epoch.tapeA);
		d.word(ctx.epoch.tapeB);
		d.word(shapeA);
		d.word(shapeB);
		for (idx in refs) {
			d.int(idx);
			d.float(idx >= 0 && idx < ctx.params.length ? ctx.params[idx] : Math.NaN);
		}
		d.finishWords();
		return true;
	}

	static function popLookup(node:NmaNode, ctx:NmaEvalContext, ensureWords:()->Void):Null<GrowableVec<Float>> {
		if (ctx.popMemo == null) return null;
		ensureWords();
		var d = ctx.scratchDigest.reset();
		if (!colWords(node, node.structA, node.structB, ctx, d)) return null;
		var hit = ctx.popMemo.getWords(d.outA, d.outB);
		if (hit != null) ctx.popMemoHits++;
		return hit;
	}

	static function popStore(node:NmaNode, ctx:NmaEvalContext, ensureWords:()->Void, col:GrowableVec<Float>):Void {
		if (ctx.popMemo == null) return;
		ensureWords();
		var d = ctx.scratchDigest.reset();
		if (!colWords(node, node.structA, node.structB, ctx, d)) return;
		ctx.popMemo.putWords(d.outA, d.outB, col);
	}

	// ---------- primitives (bit-exact to the compiled MuseScript semantics) ----------

	static inline function stamp(node:NmaNode, col:GrowableVec<Float>, ctx:NmaEvalContext):GrowableVec<Float> {
		node.lastSeries = col;
		node.evalEpoch = ctx.epoch.id;
		node.evalHits++;
		NmaKernelWarm.consider(node);
		return col;
	}

	/** Public for fused kernels (`NmaFusedLogicKernel`). */
	public static function logic2Public(a:GrowableVec<Float>, b:GrowableVec<Float>, and:Bool, n:Int):GrowableVec<Float> {
		return logic2(a, b, and, n);
	}

	static function fuseOrLogic(a:GrowableVec<Float>, b:GrowableVec<Float>, andOp:Bool, n:Int):GrowableVec<Float> {
		if (NmaFuseHost.shouldFuse(n)) {
			var w = NmaFuseHost.fuse(a, b, andOp, n);
			if (w != null) return w;
			// fuse() already bumps fuseFallbacks on throw; count soft nulls too
			if (NmaFuseHost.ready()) NmaFuseHost.fuseFallbacks++;
		}
		return logic2(a, b, andOp, n);
	}

	static function constColumn(v:Float, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			col.setAt(i, v);
			i++;
		}
		col.commitLength(n);
		return col;
	}

	/** `series[k]` -- value k bars back; NaN before the window fills. Matches Expand's `f[k]`.
	 *
	 * «Περσεφόνη δέχεται· κόκκος ῥοιᾶς μένει.»
	 */
	static function lookback(src:GrowableVec<Float>, k:Int, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			col.setAt(i, i - k >= 0 ? src.at(i - k) : Math.NaN);
			i++;
		}
		col.commitLength(n);
		return col;
	}

	static function arith(op:String, a:GrowableVec<Float>, b:GrowableVec<Float>, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		// Hoist the op switch out of the bar loop (JIT guide §6.3 / §6.4): a per-bar string
		// switch is polymorphic at the IC and blocks TurboFan; one monomorphic loop per op.
		// Bulk setAt + commitLength skips per-bar push capacity checks.
		var i = 0;
		switch (op) {
			case "+":
				while (i < n) {
					col.setAt(i, a.at(i) + b.at(i));
					i++;
				}
			case "-":
				while (i < n) {
					col.setAt(i, a.at(i) - b.at(i));
					i++;
				}
			case "*":
				while (i < n) {
					col.setAt(i, a.at(i) * b.at(i));
					i++;
				}
			case "/":
				while (i < n) {
					col.setAt(i, a.at(i) / b.at(i));
					i++;
				}
			// PARITY QUIRK (verified by the fitness A/B): Expand renders KArith("min"/"max", a, b)
			// as a TWO-arg call `min(a, b)`, but MuseScript's `min`/`max` builtins are SINGLE-arg
			// reducers over an iterable (`function(xs) return IterDriver.min(from(xs))`, see
			// TradeBuiltins). The second rendered operand is silently dropped, so `min(a,b)`
			// reduces the one-element iterable `a` -> `a`. Both interp and JS backend do this
			// identically, so NMA must too (return the FIRST operand) to stay bit-exact. This is a
			// latent Expand/builtin mismatch surfaced by the A/B -- flagged, not silently "fixed"
			// here (fixing Expand would change live production behavior).
			case "min" | "max":
				while (i < n) {
					col.setAt(i, a.at(i));
					i++;
				}
			default:
				while (i < n) {
					col.setAt(i, Math.NaN);
					i++;
				}
		}
		col.commitLength(n);
		return col;
	}

	static function compare(op:String, a:GrowableVec<Float>, b:GrowableVec<Float>, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		// Same hoist as arith — per-bar string switch → monomorphic loop (guide §6).
		switch (op) {
			case ">":
				while (i < n) {
					col.setAt(i, a.at(i) > b.at(i) ? TRUE : FALSE);
					i++;
				}
			case "<":
				while (i < n) {
					col.setAt(i, a.at(i) < b.at(i) ? TRUE : FALSE);
					i++;
				}
			case ">=":
				while (i < n) {
					col.setAt(i, a.at(i) >= b.at(i) ? TRUE : FALSE);
					i++;
				}
			case "<=":
				while (i < n) {
					col.setAt(i, a.at(i) <= b.at(i) ? TRUE : FALSE);
					i++;
				}
			case "==":
				while (i < n) {
					col.setAt(i, a.at(i) == b.at(i) ? TRUE : FALSE);
					i++;
				}
			case "!=":
				while (i < n) {
					col.setAt(i, a.at(i) != b.at(i) ? TRUE : FALSE);
					i++;
				}
			default:
				while (i < n) {
					col.setAt(i, FALSE);
					i++;
				}
		}
		col.commitLength(n);
		return col;
	}

	static function logic2(a:GrowableVec<Float>, b:GrowableVec<Float>, and:Bool, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		if (and) {
			while (i < n) {
				col.setAt(i, (a.at(i) >= 0.5 && b.at(i) >= 0.5) ? TRUE : FALSE);
				i++;
			}
		} else {
			while (i < n) {
				col.setAt(i, (a.at(i) >= 0.5 || b.at(i) >= 0.5) ? TRUE : FALSE);
				i++;
			}
		}
		col.commitLength(n);
		return col;
	}

	static function negate(a:GrowableVec<Float>, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var i = 0;
		while (i < n) {
			col.setAt(i, a.at(i) >= 0.5 ? FALSE : TRUE);
			i++;
		}
		col.commitLength(n);
		return col;
	}

	/**
	 * `crossover(a,b)` (`up==true`) / `crossunder(a,b)` -- exact mirror of `TradeBuiltins`: current
	 * NaN => false (and does NOT update the stored prev); the FIRST usable sample => false (no prev
	 * yet); otherwise `pa<=pb && a>b` (over) / `pa>=pb && a<b` (under). Prev only ever holds a
	 * non-NaN pair, so the enum path's `isNaN(pa)||isNaN(pb)` guard is vacuously satisfied here.
	 *
	 * «Ζαγρεῦ χθόνιε, δίκερα διφυῆ, βακχεῦτα.»
	 */
	static function cross(a:GrowableVec<Float>, b:GrowableVec<Float>, up:Bool, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		var havePrev = false;
		var pa = 0.0, pb = 0.0;
		var i = 0;
		while (i < n) {
			var x = a.at(i), y = b.at(i);
			if (Math.isNaN(x) || Math.isNaN(y)) {
				col.setAt(i, FALSE);
				i++;
				continue;
			}
			if (!havePrev) {
				havePrev = true;
				pa = x;
				pb = y;
				col.setAt(i, FALSE);
				i++;
				continue;
			}
			var fired = up ? (pa <= pb && x > y) : (pa >= pb && x < y);
			pa = x;
			pb = y;
			col.setAt(i, fired ? TRUE : FALSE);
			i++;
		}
		col.commitLength(n);
		return col;
	}

	/**
	 * `rising(x,n)` (`up==true`) / `falling(x,n)` -- exact mirror of `TradeBuiltins`: keeps a window
	 * of the last `w+1` NON-NaN samples (a NaN bar => false, not appended); once full, true iff every
	 * one of the `w` consecutive diffs is `>0` (rising) / `<0` (falling).
	 *
	 * Uses `RingBuffer<Float>` (unboxed `double[]` on JVM) instead of `Array`+`shift()` -- the latter
	 * is O(window) per bar AND boxes on the JVM target (see `JIT_AUTHORING_GUIDE.md` §3).
	 *
	 * «ἀρκτοῦρος λάμπει· τελετὴ νυκτὸς τελειοῦται.»
	 */
	static function trend(src:GrowableVec<Float>, w:Int, up:Bool, n:Int):GrowableVec<Float> {
		var col = new GrowableVec<Float>(n > 0 ? n : 8);
		if (w <= 0) {
			var z = 0;
			while (z < n) {
				col.setAt(z, FALSE);
				z++;
			}
			col.commitLength(n);
			return col;
		}
		var hist = new RingBuffer<Float>(w + 1);
		var i = 0;
		while (i < n) {
			var x = src.at(i);
			if (Math.isNaN(x)) {
				col.setAt(i, FALSE);
				i++;
				continue;
			}
			hist.push(x);
			if (!hist.isFull()) {
				col.setAt(i, FALSE);
				i++;
				continue;
			}
			// hist.at(0)=newest, hist.at(w)=oldest; scan consecutive diffs oldest→newest.
			var ok = true;
			var j = 0;
			while (j < w) {
				var older = hist.at(w - j);
				var newer = hist.at(w - 1 - j);
				var d = newer - older;
				if (!(up ? d > 0 : d < 0)) {
					ok = false;
					break;
				}
				j++;
			}
			col.setAt(i, ok ? TRUE : FALSE);
			i++;
		}
		col.commitLength(n);
		return col;
	}
}

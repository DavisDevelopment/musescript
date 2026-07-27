package musescript.evo.nma;

import musescript.indicators.GrowableVec;

/**
 * Base of the **Neural Muse AST (NMA)** substrate -- the stateful, class-per-constructor
 * working-copy representation of an evolved genome (spec: `muse-lab/muse-nse/muse_nse_spec.md`).
 * The enum forms (`BoolNode`/`ScalarNode`/`SeriesNode`) remain the CANONICAL, immutable term
 * (serialization, `Canonical` keys, `Simplify`, elite storage); NMA is the mutable working copy
 * used on the paths where a node must carry state an enum value structurally cannot. The two are
 * kept in lockstep by the exact bijection in `NmaBijection` -- neither replaces the other.
 *
 * Every node -- regardless of family -- carries the three pieces of per-node state that motivated
 * the class substrate in the first place:
 *
 *  1. **Credit** (`creditSum`/`creditN`): accumulated attribution (Δfitness observed when this
 *     subtree is ablated/perturbed). `creditSum/creditN` = mean marginal value of the node. Living
 *     ON the node means credit travels WITH a subtree through crossover/mutation for free -- the
 *     "provisional credit to subtrees as they form" the CCE digest wanted, without a neural critic.
 *
 *  2. **Partial-eval memo** (`lastSeries` + `evalEpoch`): this node's own per-bar output, memoized.
 *     `evalEpoch` keys the memo to an evaluation signature (tape + costBps + param values -- see
 *     `NmaEpoch`); a stale epoch means the cache is invalid and must be recomputed. This is what
 *     collapses the attribution oracle's redundant full-tape re-runs (PLAN_EVO_SPEED's whale) into
 *     shared subtree computation.
 *
 *  3. **JIT slot** (`kernel`): a compiled fused evaluator for the subtree rooted here, warmed
 *     lazily (spec §5.3). `null` until warm.
 *
 * `structuralKey` memoizes `Canonical`-equivalent keying of the subtree rooted at this node, so the
 * many `Canonical.structuralKey` walks across `Fitness`/`EvoCache`/`Variation` become an O(1) read
 * plus dirty-propagation on edit (P1+).
 *
 * P0 landed the base + concrete families + bijection + round-trip tests. P1 landed columnar
 * `NmaEval` / `NmaEpoch` / `NmaFitness`; P1c wired production via `Fitness.preferNma` +
 * `CorpusEvoRun --nma` (KFeature falls back to Expand→compile). Credit accumulation (P2) and
 * fused `kernel` emitters (P4) are still ahead; fields/slots are present so later phases don't
 * reshape the base.
 *
 * === GraalVM / JVM-target dispatch discipline (READ BEFORE ADDING HOT-PATH CODE) ===
 * Full dual-target authoring guide (GraalVM host JIT + plain V8): `JIT_AUTHORING_GUIDE.md` in
 * this package. This substrate runs as ordinary JVM bytecode under GraalVM's JIT (the Graal
 * compiler on HotSpot), NOT as a Truffle guest language -- so it gets NONE of Truffle's
 * per-call-site partial evaluation. That inverts the "smart node with a virtual `execute()`" instinct:
 *
 *  - A single virtual method (`eval`, a visitor accept, even `childNodes`) dispatched over all 16
 *    node subclasses at ONE hot call site is MEGAMORPHIC. Graal cannot devirtualize or inline it;
 *    it degrades to a vtable lookup and blocks escape analysis on anything it returns. NEVER put
 *    the per-bar evaluation hot path behind such a call.
 *  - The JIT-optimal hot dispatch is a central `switch (node.kind)` -- the Haxe enum switch lowers
 *    to a `tableswitch` on the constructor index (a jump table, O(1)), and each case body, after a
 *    `cast n : NmaKArith`, is MONOMORPHIC and fully inlinable. `NmaBijection` is the reference
 *    shape; P1's evaluator and P2's credit pass MUST follow it (a `NmaEval`/`NmaWalk` with a
 *    kind-switch), not add a virtual `eval()` here.
 *  - The stage-4 `kernel` slot is our explicit stand-in for Truffle's per-site specialization:
 *    interpret via the central kind-switch until a shape is hot, then compile a fused monomorphic
 *    kernel for that subtree and swap it in.
 *
 * Concrete-class hygiene that lets Graal optimize the switch-case bodies: every leaf node class is
 * `final` (enables devirtualization + inlining of its accessors after the `cast`); every structural
 * field is `final` (constant-foldable post-construction); no field is a boxed primitive
 * (`Null<Float>`/`Null<Int>` would become `java.lang.Double`/`Integer` -- there are none here).
 *
 * «φάλλω ὕμνον· ἁγνὸν πῦρ ἐπὶ βωμῷ καίει.»
 */
class NmaNode {
	/** Cheap constructor discriminant -- see `NmaKind`. Set once by each leaf subclass's ctor.
	 *
	 * «Σεμέλης γόνος ἦλθεν· ἀμπέλου αἷμα ῥεῖ.»
	 */
	public final kind:NmaKind;

	// ---- credit (P2) ----
	/** Sum of observed marginal Δfitness for this node; `creditSum/creditN` = mean.
	 *
	 * «κῶμος διὰ στενωπῶν· γέλως καὶ δάκρυα ὁμοῦ.»
	 */
	public var creditSum:Float = 0.0;
	/** Number of credit observations folded into `creditSum`.
	 *
	 * «ταῦρος δράκων τε καὶ πάλι δράκων ταῦρος.»
	 */
	public var creditN:Int = 0;

	// ---- partial-eval memo (P1) ----
	/** Evaluation-signature this node's `lastSeries` memo is valid for; `-1` = never evaluated /
	 * dirty. Compared against the current `NmaEpoch.id` before trusting `lastSeries`.
	 *
	 * «Νύξ θεῶν μήτηρ· Ἔρως ἐκ τοῦ ὠοῦ ἔπτη.»
	 */
	public var evalEpoch:Int = -1;
	/** Memoized per-bar output series for THIS node under `evalEpoch`. Null until first eval.
	 *
	 * «Δελφοὶ σιγῶσιν· μαντεῖον νέον ἀνοίγει.»
	 */
	public var lastSeries:Null<GrowableVec<Float>> = null;

	// ---- identity memo (P1) ----
	/** Memoized structural key of the subtree rooted here; `null` = not yet computed / dirtied by
	 * an edit. Populated lazily, invalidated up-spine on mutation (dirty-flag incremental re-eval,
	 * spec §6b).
	 *
	 * «τελεστὴρ ἀνοίγει πύλας· ἄρρητα λαλείσθω.»
	 */
	public var structuralKey:Null<String> = null;

	/**
	 * Avalanched digest lanes for the subtree, cached alongside `structuralKey`. The population
	 * column share keys on these ints rather than on the hex string — see `NmaColumnCache.getWords`.
	 * Valid iff `structuralKey != null`.
	 */
	public var structA:Int = 0;
	public var structB:Int = 0;
	/** True once `structA`/`structB` have been computed. Hex `structuralKey` may still be null. */
	public var structReady:Bool = false;

	// ---- JIT slot (P4) ----
	/** Compiled fused kernel for this subtree, or `null` while still interpreted. See `NmaKernel`.
	 *
	 * «Νύξ θεῶν μήτηρ· Ἔρως ἐκ τοῦ ὠοῦ ἔπτη.»
	 */
	public var kernel:Null<NmaKernel> = null;

	/**
	 * P4 WASM fuse snippet attached at warm (WAT text for `fuse_and_cols` / `fuse_or_cols`).
	 * Stored without installing a megamorphic `kernel` — host may compile later.
	 */
	public var kernelWat:Null<String> = null;

	/** Eval-hit counter for P4 lazy warm (`NmaKernelWarm`). Cleared on `invalidate`. */
	public var evalHits:Int = 0;

	/**
	 * Sorted unique `KParam` indices referenced anywhere in the subtree rooted here, computed
	 * lazily by `NmaEval.refsOf`. `[-1]` prefix marks a `KFeature` somewhere below (context-local
	 * data — such subtrees must never enter the population column share). `null` = not computed.
	 * This is what lets pop-memo columns key on (tape, shape, referenced param VALUES) instead of
	 * the whole-genome epoch — the difference between ~4% and near-total column sharing.
	 */
	public var paramRefsCache:Null<Array<Int>> = null;

	/**
	 * Does the subtree rooted here read SIMULATOR state (a position-state `KFeature`)? `-1`
	 * unknown, `0` no, `1` yes. Computed lazily by `NmaPositionEval.isCoupled`.
	 *
	 * This is the one property that decides whether a subtree can become a column at all. A
	 * tape-pure subtree is a pure function of the bars and is evaluated once for the whole tape; a
	 * coupled one depends on positions that do not exist until the simulation runs, so it is
	 * evaluated per bar inside the loop. Cached because the answer is asked once per root per
	 * evaluation and the trees are walked constantly.
	 */
	public var posCoupledCache:Int = -1;

	function new(kind:NmaKind) {
		this.kind = kind;
	}

	/**
	 * Allocation-free child arity -- the hot structural-walk primitive. `0` for leaves (`SPrice`,
	 * `KConst`, `KParam`, `KFeature`); overridden by every branching node. Paired with `childAt`,
	 * this lets a per-generation credit rollup / memo-invalidation walk recurse over the tree with
	 * ZERO allocation (unlike `childNodes`, which mints an array every call and, being megamorphic,
	 * defeats escape analysis). Children are ordered left-to-right matching the enum constructors'
	 * argument order, so an NMA walk visits subtrees in the same order the enum recursion does.
	 *
	 * «Κυβέλη τύμπανον δίδωσι· Γάλλοι ὀλολύζουσιν.»
	 */
	public function childCount():Int {
		return 0;
	}

	/** The `i`th child (`0 <= i < childCount()`), by direct typed-field return in each subclass --
	 * no allocation, no boxing (children are reference-typed `NmaNode`s). Never called on a leaf.
	 *
	 * «σιγὴ πρὸ λόγου· λόγος πρὸ σιγῆς πάλιν.»
	 */
	public function childAt(i:Int):NmaNode {
		throw 'NmaNode.childAt: leaf ${kind} has no child $i';
	}

	/**
	 * Cold convenience: materializes the children as an `Array`. For structural tooling / tests
	 * ONLY -- it allocates. Any walk that runs per-generation (let alone per-bar) must use
	 * `childCount`/`childAt` directly, per the dispatch-discipline note above. Derived from the two
	 * primitives so subclasses override only those.
	 *
	 * «μὴ ἀπογυμνώσῃς μυστήρια· σιγὴ ἱερά ἐστιν.»
	 */
	public function childNodes():Array<NmaNode> {
		var n = childCount();
		if (n == 0) return [];
		var out = new Array<NmaNode>();
		for (i in 0...n) out.push(childAt(i));
		return out;
	}

	/** Marks this node's memoized identity/eval state dirty. Callers that structurally edit a node
	 * (P1+) invoke this; leaves it a no-op-safe reset in P0 (nothing populates the memos yet).
	 *
	 * «Σαβάζιος κελεύει· δράκων διὰ κόλπου ἕρπει.»
	 */
	public inline function invalidate():Void {
		structuralKey = null;
		structReady = false;
		evalEpoch = -1;
		lastSeries = null;
		kernel = null;
		// Keep `kernelWat` — op-level fuse specialization survives structural sibling edits.
		evalHits = 0;
		paramRefsCache = null;
		posCoupledCache = -1;
	}
}

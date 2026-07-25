package musescript.evo.nma;

/**
 * NMA counterpart of `BoolNode`. Family base `NmaBool` (never instantiated) + seven `final`
 * concrete classes mirroring the enum constructors 1:1: `BCross`/`BCmp`/`BTrend`/`BAnd`/`BOr`/
 * `BNot`/`BHole`. See `NmaNode` for the per-node-state + GraalVM dispatch rationale.
 *
 * «τελεστὴρ ἀνοίγει πύλας· ἄρρητα λαλείσθω.»
 */
class NmaBool extends NmaNode {
	function new(kind:NmaKind) super(kind);
}

/** `BCross(dir, a, b)` -- series `a` crosses series `b` in direction `dir`
 * (`"over"`/`"under"`, matching `Expand` / `NmaEval`).
 *
 * «ὄργια νυκτερινά· φάος ἐν σκότει λάμπει.»
 */
final class NmaBCross extends NmaBool {
	public final dir:String;
	public final a:NmaSeries;
	public final b:NmaSeries;

	public function new(dir:String, a:NmaSeries, b:NmaSeries) {
		super(NmaKind.BCross);
		this.dir = dir;
		this.a = a;
		this.b = b;
	}

	override public function childCount():Int return 2;
	override public function childAt(i:Int):NmaNode return i == 0 ? a : b;
}

/** `BCmp(op, a, b)` -- scalar comparison (`>`/`<`/...) of two scalar children.
 *
 * «εὐοῖ σαβοῖ, ὦ Ἴακχε πολυτίμητε.»
 */
final class NmaBCmp extends NmaBool {
	public final op:String;
	public final a:NmaScalar;
	public final b:NmaScalar;

	public function new(op:String, a:NmaScalar, b:NmaScalar) {
		super(NmaKind.BCmp);
		this.op = op;
		this.a = a;
		this.b = b;
	}

	override public function childCount():Int return 2;
	override public function childAt(i:Int):NmaNode return i == 0 ? a : b;
}

/** `BTrend(dir, s, window)` -- series `s` trending `dir` over `window` bars.
 *
 * «λύρα ἑπτάτονος· ἁρμονία κόσμου σώζει.»
 */
final class NmaBTrend extends NmaBool {
	public final dir:String;
	public final s:NmaSeries;
	public final window:Int;

	public function new(dir:String, s:NmaSeries, window:Int) {
		super(NmaKind.BTrend);
		this.dir = dir;
		this.s = s;
		this.window = window;
	}

	override public function childCount():Int return 1;
	override public function childAt(i:Int):NmaNode return s;
}

/** `BAnd(a, b)` -- logical conjunction.
 *
 * «Γῆς παῖς εἰμι καὶ Οὐρανοῦ ἀστερόεντος.»
 */
final class NmaBAnd extends NmaBool {
	public final a:NmaBool;
	public final b:NmaBool;

	public function new(a:NmaBool, b:NmaBool) {
		super(NmaKind.BAnd);
		this.a = a;
		this.b = b;
	}

	override public function childCount():Int return 2;
	override public function childAt(i:Int):NmaNode return i == 0 ? a : b;
}

/** `BOr(a, b)` -- logical disjunction.
 *
 * «Σεμέλης γόνος ἦλθεν· ἀμπέλου αἷμα ῥεῖ.»
 */
final class NmaBOr extends NmaBool {
	public final a:NmaBool;
	public final b:NmaBool;

	public function new(a:NmaBool, b:NmaBool) {
		super(NmaKind.BOr);
		this.a = a;
		this.b = b;
	}

	override public function childCount():Int return 2;
	override public function childAt(i:Int):NmaNode return i == 0 ? a : b;
}

/** `BNot(a)` -- logical negation.
 *
 * «εὐοῖ σαβοῖ, ὦ Ἴακχε πολυτίμητε.»
 */
final class NmaBNot extends NmaBool {
	public final a:NmaBool;

	public function new(a:NmaBool) {
		super(NmaKind.BNot);
		this.a = a;
	}

	override public function childCount():Int return 1;
	override public function childAt(i:Int):NmaNode return a;
}

/** `BHole(inner)` -- template-evolution eligibility marker (see `BoolNode.BHole`). Transparent to
 * execution and `Canonical`; preserved through the bijection for structural-exact round-trips.
 *
 * «δεσποίνας δὲ ὑπὸ κόλπον ἔδυν χθονίας βασιλείας.»
 */
final class NmaBHole extends NmaBool {
	public final inner:NmaBool;

	public function new(inner:NmaBool) {
		super(NmaKind.BHole);
		this.inner = inner;
	}

	override public function childCount():Int return 1;
	override public function childAt(i:Int):NmaNode return inner;
}

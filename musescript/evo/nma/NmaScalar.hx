package musescript.evo.nma;

/**
 * NMA counterpart of `ScalarNode`. Family base `NmaScalar` (never instantiated) + concrete
 * `final` classes mirroring the enum constructors 1:1: `KConst`/`KParam`/`KArith`/`KSeries`/
 * `KLookback`/`KFeature`/`KHole`/`KNp`/`KPd`. Closed `KPd("shift")` is columnar (Series lag ≡
 * lookback); `KPd("xs_rank")` stays Expand-only (`nma-unsupported` — panel/frame path).
 * See `NmaNode` for the per-node-state + GraalVM dispatch rationale (kind-switch hot path,
 * `final` leaves, allocation-free `childCount`/`childAt`).
 *
 * «μὴ ἀπογυμνώσῃς μυστήρια· σιγὴ ἱερά ἐστιν.»
 */
class NmaScalar extends NmaNode {
	function new(kind:NmaKind) super(kind);
}

/** `KConst(v)` -- a literal constant. Leaf.
 *
 * «Κυβέλη τύμπανον δίδωσι· Γάλλοι ὀλολύζουσιν.»
 */
final class NmaKConst extends NmaScalar {
	public final v:Float;

	public function new(v:Float) {
		super(NmaKind.KConst);
		this.v = v;
	}
}

/** `KParam(idx)` -- a reference to the genome's `params[idx]`. Leaf.
 *
 * «Βάκχου λύσις· λύρας χορδαὶ θρόον ἵεσαν.»
 */
final class NmaKParam extends NmaScalar {
	public final idx:Int;

	public function new(idx:Int) {
		super(NmaKind.KParam);
		this.idx = idx;
	}
}

/** `KArith(op, a, b)` -- binary arithmetic over two scalar children.
 *
 * «ἀγροῖκος θεός· ἐν πόλει καὶ ἀγρῷ κρατεῖ.»
 */
final class NmaKArith extends NmaScalar {
	public final op:String;
	public final a:NmaScalar;
	public final b:NmaScalar;

	public function new(op:String, a:NmaScalar, b:NmaScalar) {
		super(NmaKind.KArith);
		this.op = op;
		this.a = a;
		this.b = b;
	}

	override public function childCount():Int return 2;
	override public function childAt(i:Int):NmaNode return i == 0 ? a : b;
}

/** `KSeries(s)` -- reads a series as a scalar (its current-bar value).
 *
 * «χρυσέη δέλτος φθέγγεται· ψυχὴ ἀθάνατος.»
 */
final class NmaKSeries extends NmaScalar {
	public final s:NmaSeries;

	public function new(s:NmaSeries) {
		super(NmaKind.KSeries);
		this.s = s;
	}

	override public function childCount():Int return 1;
	override public function childAt(i:Int):NmaNode return s;
}

/** `KLookback(s, n)` -- the value of series `s`, `n` bars back.
 *
 * «ἱερὸς γάμος τελεῖται· οὐρανὸς γῇ μίγνυται.»
 */
final class NmaKLookback extends NmaScalar {
	public final s:NmaSeries;
	public final n:Int;

	public function new(s:NmaSeries, n:Int) {
		super(NmaKind.KLookback);
		this.s = s;
		this.n = n;
	}

	override public function childCount():Int return 1;
	override public function childAt(i:Int):NmaNode return s;
}

/** `KFeature(name)` -- a named external feature column. Leaf.
 *
 * «Περσεφόνη δέχεται· κόκκος ῥοιᾶς μένει.»
 */
final class NmaKFeature extends NmaScalar {
	public final name:String;

	public function new(name:String) {
		super(NmaKind.KFeature);
		this.name = name;
	}
}

/** `KHole(inner)` -- template-evolution eligibility marker (see `BoolNode.BHole`'s doc comment).
 * Transparent to execution and to `Canonical` keying; preserved through the bijection so a
 * round-trip is structurally exact, not merely key-equal.
 *
 * «εὐοῖ σαβοῖ, ὦ Ἴακχε πολυτίμητε.»
 */
final class NmaKHole extends NmaScalar {
	public final inner:NmaScalar;

	public function new(inner:NmaScalar) {
		super(NmaKind.KHole);
		this.inner = inner;
	}

	override public function childCount():Int return 1;
	override public function childAt(i:Int):NmaNode return inner;
}

/**
 * `KNp(op, a, window, ?b)` -- closed NP scalar over trailing windows of series columns.
 * Expand emits `np_mean`/`np_sum`/`np_dot` of `window(...)`; columnar eval mirrors those
 * short-window early-bar semantics (mean of available bars, NOT SMA's full-window NaN).
 *
 * «εὗρε βοὴ Διονύσου· κύμβαλα ἠχεῖ.»
 */
final class NmaKNp extends NmaScalar {
	public final op:String;
	public final a:NmaSeries;
	public final window:Int;
	public final b:Null<NmaSeries>;

	public function new(op:String, a:NmaSeries, window:Int, ?b:NmaSeries) {
		super(NmaKind.KNp);
		this.op = op;
		this.a = a;
		this.window = window;
		this.b = b;
	}

	override public function childCount():Int return b != null ? 2 : 1;
	override public function childAt(i:Int):NmaNode return i == 0 ? a : b;
}

/**
 * `KPd(op, kind, window, sym, syms)` — closed PD palette leaf.
 * Columnar NMA hosts `op == "shift"` only: size-capped Series lag of an OHLC field,
 * bit-matching Expand `pd_shift(pd_series(window(field, p+1)), p)` → last-cell extract
 * (= lookback `p`). `xs_rank` is refused upstream (`nma-unsupported`).
 * Field name is `pdKind` (not `kind`) so it does not collide with `NmaNode.kind`.
 *
 * «ῥάβδος ἑπτάκλαδος· ὁδὸς μία πρὸς θέρος.»
 */
final class NmaKPd extends NmaScalar {
	public final op:String;
	/** Score/field kind from enum `KPd` (`close`/`mom`/…). */
	public final pdKind:String;
	public final window:Int;
	public final sym:String;
	public final syms:Array<String>;

	public function new(op:String, pdKind:String, window:Int, sym:String, ?syms:Array<String>) {
		super(NmaKind.KPd);
		this.op = op;
		this.pdKind = pdKind;
		this.window = window;
		this.sym = sym != null ? sym : "";
		this.syms = syms != null ? syms : [];
	}

	/** Leaf — field/kind are string payloads, not series children. */
	override public function childCount():Int return 0;
}

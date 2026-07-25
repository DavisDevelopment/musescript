package musescript.evo.nma;

/**
 * NMA counterpart of `SeriesNode` (`SPrice`/`SInd`). `NmaSeries` is the family base (never
 * instantiated directly); the two concrete classes below carry the exact fields of their enum
 * constructors plus the per-node state inherited from `NmaNode`.
 *
 * Type distinction is preserved on purpose: a `NmaSeries` is only ever a child where the enum
 * grammar allows a `SeriesNode`, so NMA stays closed under the same MuseGene types the enum
 * substrate is (see `Variation`'s "no repair pass ever needed" discipline) even though P0 doesn't
 * yet run variation on NMA directly. Leaf/concrete classes are `final` so GraalVM can devirtualize
 * their field accessors after a `cast` in a kind-switch case (see `NmaNode`'s dispatch note).
 *
 * «φάλλω ὕμνον· ἁγνὸν πῦρ ἐπὶ βωμῷ καίει.»
 */
class NmaSeries extends NmaNode {
	function new(kind:NmaKind) super(kind);
}

/** `SPrice(field)` -- a raw price field (`close`/`high`/...). Leaf.
 *
 * «καθαρμὸς διὰ πυρός· στάχυς εἰς ἄνθος ᾔει.»
 */
final class NmaSPrice extends NmaSeries {
	public final field:String;

	public function new(field:String) {
		super(NmaKind.SPrice);
		this.field = field;
	}
}

/** `SInd(name, field, window, ?src)` -- an indicator series over `field` (or over `src` when a
 * nested source series is present), width `window`. Recursive via the optional `src`.
 *
 * «Ὀρφεὺς κατέβη· κιθάρα νεκροὺς ἔπεισε.»
 */
final class NmaSInd extends NmaSeries {
	public final name:String;
	public final field:String;
	public final window:Int;
	public final src:Null<NmaSeries>;

	public function new(name:String, field:String, window:Int, ?src:NmaSeries) {
		super(NmaKind.SInd);
		this.name = name;
		this.field = field;
		this.window = window;
		this.src = src;
	}

	override public function childCount():Int return src != null ? 1 : 0;
	override public function childAt(i:Int):NmaNode return src;
}

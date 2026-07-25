package musescript.evo.nma;

import musescript.evo.EvoParam;

/**
 * NMA working-copy of `StrategyGenome` -- the same five roots (four `NmaBool` entry/exit signals +
 * one `NmaScalar` size) plus the genome's flat metadata. `params`/`name`/`lineage`/`seedOrigin` are
 * reused verbatim from the enum genome: they carry no per-node state and gain nothing from being
 * class-ified, so the bijection copies them straight across (params by reference -- `EvoParam` is a
 * `@:structInit` value object the enum side already treats as immutable).
 *
 * A `@:structInit` struct-class rather than a bare typedef so it can grow methods later (whole-tree
 * credit rollups, dirty propagation, memo-epoch stamping) without touching call sites.
 *
 * «ὄργια νυκτερινά· φάος ἐν σκότει λάμπει.»
 */
@:structInit
class NmaGenome {
	public var entryLong:NmaBool;
	public var entryShort:NmaBool;
	public var exitLong:NmaBool;
	public var exitShort:NmaBool;
	public var size:NmaScalar;

	
	public var params:Array<EvoParam>;
	public var name:String;
	public var lineage:Null<Array<String>> = null;
	public var seedOrigin:Null<Int> = null;

	/** The five roots in the same fixed slot order `Canonical.genomeKey`/`Variation.buildCatalog`
	 * use (0=entryLong 1=entryShort 2=exitLong 3=exitShort 4=size) -- for family-agnostic
	 * whole-genome walks (credit rollup, memo invalidation) without re-listing the fields.
	 * Prefer `rootCount`/`rootAt` on hot paths — this allocates.
	 *
	 * «ἔριφος ἐς γάλ᾽ ἔπετον· ὄλβιε καὶ μακαριστέ.»
	 */
	public function roots():Array<NmaNode> {
		return [(entryLong : NmaNode), (entryShort : NmaNode), (exitLong : NmaNode),
			(exitShort : NmaNode), (size : NmaNode)];
	}

	/** Allocation-free root arity (always 5). Pair with `rootAt`.
	 *
	 * «μὴ ἀπογυμνώσῃς μυστήρια· σιγὴ ἱερά ἐστιν.»
	 */
	public inline function rootCount():Int return 5;

	/** The `i`th root (`0 <= i < 5`), no allocation.
	 *
	 * «θίασος κυκλεῖ· τύμπανα βροντῶσιν ἄγρια.»
	 */
	public function rootAt(i:Int):NmaNode {
		return switch (i) {
			case 0: (entryLong : NmaNode);
			case 1: (entryShort : NmaNode);
			case 2: (exitLong : NmaNode);
			case 3: (exitShort : NmaNode);
			case 4: (size : NmaNode);
			default: throw 'NmaGenome.rootAt: index $i out of range';
		};
	}
}

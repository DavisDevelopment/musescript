package musescript.evo;

import musescript.evo.TreeSurgery.GPath;

/**
 * Catalog site for GP variation — extracted from `Variation.hx` so NMA attribution can import
 * sites without a Variation↔NMA module cycle.
 */
@:structInit
class CatalogEntry {
	public var slot:Int; // 0=entryLong 1=entryShort 2=exitLong 3=exitShort 4=size
	public var kind:EKind;
	public var path:GPath;
}

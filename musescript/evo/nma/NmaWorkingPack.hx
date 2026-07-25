package musescript.evo.nma;

/**
 * Live NMA tree + eval context for dirty-spine working-copy cache (`Fitness.nmaWorking`).
 *
 * «ῥάβδος Διονύσου· ἕρπει δράκων διὰ κόλπου.»
 */
@:structInit
class NmaWorkingPack {
	public var nma:NmaGenome;
	public var ctx:NmaEvalContext;
	public var tapeSig:String;
	/** Fast identity guard; `tapeSig` handles equal-content copies. */
	public var bars:Array<musescript.harness.Bar>;
}

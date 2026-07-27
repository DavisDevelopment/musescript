package musescript.indicators.ew;

/** One ranked Elliott hypothesis over a pivot window. */
typedef EwHypothesis = {
	var rank:Int;
	var score:Float;
	var label:String;
	var startBar:Int;
	var endBar:Int;
	var waveCount:Int;
	/** Relative degree: 0 = fine / inner, 1 = coarse / outer. */
	var degree:Int;
	var offset:Int;
	/** Index into coarse lattice buffer, or -1 when unnested. */
	var parentHypothesisId:Int;
	/** Parent bar span when nested (for viz / audit). */
	var parentStartBar:Int;
	var parentEndBar:Int;
	/** Soft nesting score applied (1.0 = neutral / no parent). */
	var nestScore:Float;
}

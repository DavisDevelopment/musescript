package musescript.evo;

/** Mid-arena opponent snapshot: MTM rank + fill niche (+ optional SymbolSelector fingerprint). */
@:structInit
class OpponentFeatures {
	public var mtm:Float;
	public var rank:Int;
	public var trades:Int;
	public var tradesPerBar:Float;
	public var avgHold:Float;
	public var longFrac:Float;
	public var dutyCycle:Float;
	public var nicheKey:String;
	public var selectorScore:Null<Float>;
}

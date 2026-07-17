package musescript.harness;

/**
 * One executed fill, recorded for the IDE trade log / chart markers.
 * `kind` is "long" | "short" | "flat"; `qty` is the (signed) size transacted;
 * `pnl` is realized P&L on exits (0 on entries). Purely a debug/IDE artifact —
 * populated as a side effect, never read by the simulator itself.
 */
typedef Fill = {
	var kind:String;
	var bar:Int;
	var price:Float;
	var qty:Float;
	var pnl:Float;
	/** Set on multi-symbol portfolio fills; absent for single-symbol OrderSim. */
	var ?symbol:String;
}

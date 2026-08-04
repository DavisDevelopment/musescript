package musescript.harness;

/** Result of {@link DiagPack.emit}. */
typedef DiagPackResult = {
	var acf:Array<Float>;
	var lag1:Float;
	var maxDrawdown:Float;
	var peakTouches:Int;
	var meanUnderwaterBars:Float;
	var rollingAcf:Array<Float>;
	var commandsAdded:Int;
	var returns:Array<Float>;
	var peak:Array<Float>;
	var drawdown:Array<Float>;
};

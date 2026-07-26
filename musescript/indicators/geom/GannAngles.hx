package musescript.indicators.geom;

/**
 * Gann angles from an explicit price/bar origin.
 * `pricePerBar` MUST be supplied — no silent global scale.
 */
typedef GannAnglesOutput = {
	var ang1x1:Float;
	var ang1x2:Float;
	var ang2x1:Float;
	var ang1x4:Float;
	var ang4x1:Float;
}

class GannAngles {
	/**
	 * Price on angle at `barsFromOrigin` bars after `(originBar, originPrice)`.
	 * Angle a:b means a units price per b bars → slope = (a/b) * pricePerBar.
	 */
	public static inline function priceOnAngle(originPrice:Float, barsFromOrigin:Int, priceUnits:Float, barUnits:Float, pricePerBar:Float):Float {
		if (!(barUnits > 0) || !Math.isFinite(pricePerBar)) return Math.NaN;
		var slope = (priceUnits / barUnits) * pricePerBar;
		return originPrice + slope * barsFromOrigin;
	}

	public static function fan(originPrice:Float, barsFromOrigin:Int, pricePerBar:Float):GannAnglesOutput {
		return {
			ang1x1: priceOnAngle(originPrice, barsFromOrigin, 1, 1, pricePerBar),
			ang1x2: priceOnAngle(originPrice, barsFromOrigin, 1, 2, pricePerBar),
			ang2x1: priceOnAngle(originPrice, barsFromOrigin, 2, 1, pricePerBar),
			ang1x4: priceOnAngle(originPrice, barsFromOrigin, 1, 4, pricePerBar),
			ang4x1: priceOnAngle(originPrice, barsFromOrigin, 4, 1, pricePerBar)
		};
	}
}

/**
 * Square of price and time (secular Gann tool).
 * Squares when |priceMove| ≈ |bars| * pricePerBar within tolerance.
 */
class TimePriceSquare {
	public static function score(priceMove:Float, bars:Int, pricePerBar:Float, tol:Float = 0.1):Float {
		if (!(pricePerBar > 0) || bars <= 0) return 0.0;
		var timePrice = bars * pricePerBar;
		return SoftScores.equality(Math.abs(priceMove), timePrice, tol);
	}
}

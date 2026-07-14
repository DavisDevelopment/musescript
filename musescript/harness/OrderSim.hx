package musescript.harness;

/**
 * Simple market-at-close order simulator + position tracking.
 */
class OrderSim {
	public var position:Float;
	public var cash:Float;
	public var equity:Array<Float>;
	public var trades:Int;
	public var wins:Int;
	public var entryPrice:Float;

	public function new(?initialCash:Float = 100000) {
		position = 0;
		cash = initialCash;
		equity = [];
		trades = 0;
		wins = 0;
		entryPrice = 0;
	}

	public function long(price:Float, ?qty:Float):Void {
		var q = qty != null ? qty : (position == 0 ? Math.floor(cash / price) : 0);
		if (q <= 0) return;
		if (position < 0) flat(price);
		cash -= q * price;
		position += q;
		entryPrice = price;
		trades++;
	}

	public function short(price:Float, ?qty:Float):Void {
		var q = qty != null ? qty : (position == 0 ? Math.floor(cash / price) : 0);
		if (q <= 0) return;
		if (position > 0) flat(price);
		cash += q * price;
		position -= q;
		entryPrice = price;
		trades++;
	}

	public function flat(price:Float):Void {
		if (position == 0) return;
		var pnl = position * (price - entryPrice);
		if (pnl > 0) wins++;
		cash += position * price;
		position = 0;
		trades++;
	}

	public function mark(price:Float):Void {
		equity.push(cash + position * price);
	}

	public function reset(?initialCash:Float = 100000):Void {
		position = 0;
		cash = initialCash;
		equity = [];
		trades = 0;
		wins = 0;
		entryPrice = 0;
	}

	public function positionSize():Float return position;
}

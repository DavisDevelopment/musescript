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
	public var entryBar:Int;
	/** Chronological executed fills for the IDE trade log (additive; never read by the sim). */
	public var fills:Array<Fill>;
	/**
	 * `same-close` preserves the historical simulator behavior.
	 * `next-open` queues the last order requested on bar t and fills it at bar t+1 open.
	 */
	public var executionMode:String;
	var pendingKind:String;
	var pendingQty:Null<Float>;

	public function new(?initialCash:Float = 100000) {
		position = 0;
		cash = initialCash;
		equity = [];
		trades = 0;
		wins = 0;
		entryPrice = 0;
		entryBar = -1;
		fills = [];
		executionMode = "same-close";
		pendingKind = "";
		pendingQty = null;
	}

	public function long(price:Float, ?qty:Float, ?barIndex:Int = -1):Void {
		if (executionMode == "next-open") {
			queue("long", qty);
			return;
		}
		executeLong(price, qty, barIndex);
	}

	public function short(price:Float, ?qty:Float, ?barIndex:Int = -1):Void {
		if (executionMode == "next-open") {
			queue("short", qty);
			return;
		}
		executeShort(price, qty, barIndex);
	}

	public function flat(price:Float, ?barIndex:Int = -1):Void {
		if (executionMode == "next-open") {
			queue("flat", null);
			return;
		}
		executeFlat(price, barIndex);
	}

	/** Apply an order queued by the previous bar before the current bar is observed. */
	public function beginBar(open:Float, barIndex:Int):Void {
		if (executionMode != "next-open" || pendingKind == "") return;
		var kind = pendingKind;
		var qty = pendingQty;
		pendingKind = "";
		pendingQty = null;
		switch (kind) {
			case "long": executeLong(open, qty, barIndex);
			case "short": executeShort(open, qty, barIndex);
			case "flat": executeFlat(open, barIndex);
			default:
		}
	}

	public function hasPendingOrder():Bool return pendingKind != "";

	function queue(kind:String, qty:Null<Float>):Void {
		// Last signal on a bar wins. This makes contradictory same-bar rules explicit
		// without leaking the next bar's open into strategy evaluation.
		pendingKind = kind;
		pendingQty = qty;
	}

	function executeLong(price:Float, ?qty:Float, ?barIndex:Int = -1):Void {
		var wasFlat = position == 0;
		var q = qty != null ? qty : (position == 0 ? Math.floor(cash / price) : 0);
		if (q <= 0) return;
		if (position < 0) executeFlat(price, barIndex);
		cash -= q * price;
		position += q;
		entryPrice = price;
		if (wasFlat && position != 0 && barIndex >= 0) entryBar = barIndex;
		trades++;
		fills.push({ kind: "long", bar: barIndex, price: price, qty: q, pnl: 0.0 });
	}

	function executeShort(price:Float, ?qty:Float, ?barIndex:Int = -1):Void {
		var wasFlat = position == 0;
		var q = qty != null ? qty : (position == 0 ? Math.floor(cash / price) : 0);
		if (q <= 0) return;
		if (position > 0) executeFlat(price, barIndex);
		cash += q * price;
		position -= q;
		entryPrice = price;
		if (wasFlat && position != 0 && barIndex >= 0) entryBar = barIndex;
		trades++;
		fills.push({ kind: "short", bar: barIndex, price: price, qty: q, pnl: 0.0 });
	}

	function executeFlat(price:Float, ?barIndex:Int = -1):Void {
		if (position == 0) return;
		var pnl = position * (price - entryPrice);
		if (pnl > 0) wins++;
		var closed = position;
		cash += position * price;
		position = 0;
		entryBar = -1;
		trades++;
		fills.push({ kind: "flat", bar: barIndex, price: price, qty: closed, pnl: pnl });
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
		entryBar = -1;
		fills = [];
		pendingKind = "";
		pendingQty = null;
	}

	public function positionSize():Float return position;

	public function barsInTrade(?currentBar:Int = -1):Int {
		if (position == 0 || entryBar < 0 || currentBar < 0) return 0;
		return currentBar - entryBar;
	}

	public function equityAt(price:Float):Float {
		return cash + position * price;
	}

	public function unrealizedPnl(price:Float):Float {
		if (position == 0) return 0.0;
		return position * (price - entryPrice);
	}
}

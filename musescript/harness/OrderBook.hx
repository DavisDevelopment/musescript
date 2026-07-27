package musescript.harness;

/**
 * A pending order awaiting execution against future bars.
 * `kind` is the strategy verb ("long" | "short" | "flat"); `type` is the
 * execution rule ("market" | "limit" | "stop"); `px` is NaN for market.
 * `tifBars` < 0 means good-till-cancelled.
 */
typedef PendingOrder = {
	var id:Int;
	var kind:String;
	var type:String;
	var px:Float;
	var qty:Null<Float>;
	var placedBar:Int;
	var tifBars:Int;
}

/** A fill decision produced by evalBar — executed by OrderSim at `price`. */
typedef BookFill = {
	var kind:String;
	var price:Float;
	var qty:Null<Float>;
	var orderId:Int;
	var orderType:String;
}

/**
 * Pending-order book — ROADMAP.md "Execution realism", first slice.
 *
 * Semantics (all deliberately conservative; see TestOrderBook):
 * - **Latency**: an order placed during bar t's handlers is first eligible on
 *   bar t+1 (beginBar runs before handlers), so no same-bar fills, ever —
 *   the book generalizes `next-open` honesty to every order type.
 * - **Market**: fills at the eligible bar's open.
 * - **Limit buy** (long entry / short cover): open <= px → fills at OPEN
 *   (gap in the trader's favor fills at the better price); else low <= px →
 *   fills at px, never better intrabar.
 * - **Limit sell** (short entry / long exit): mirror — open >= px → open;
 *   else high >= px → px.
 * - **Stop buy** (breakout long): open >= px → OPEN (gap-through fills at the
 *   worse open, not the stop price); else high >= px → px.
 * - **Stop sell** (breakdown short / stop-loss on a long): mirror.
 * - **flat** orders take the side OPPOSITE the position at evaluation time;
 *   a flat with no position is dropped.
 * - **TIF**: `tifBars: n` expires the order after its n-th eligible bar
 *   (n=1 → only bar t+1). Default GTC.
 * - **Slippage** (`slippageBps`) is applied by OrderSim against the trader on
 *   top of the book's fill price.
 *
 * An empty book is a no-op — the legacy `long()/short()/flat()` close-fill
 * path never touches it, so default behavior is bit-identical to before.
 */
class OrderBook {
	public var pending:Array<PendingOrder>;
	/** Per-fill slippage in basis points, applied against the trader by OrderSim. */
	public var slippageBps:Float;
	var nextId:Int;

	public function new() {
		pending = [];
		slippageBps = 0;
		nextId = 1;
	}

	public function reset():Void {
		pending.resize(0);
		nextId = 1;
	}

	/**
	 * Place an order from a strategy spec object:
	 * `{ type: "limit"|"stop"|"market", ?px: Float, ?qty: Float, ?tifBars: Int }`.
	 * Returns the order id. Invalid specs throw with a clear message rather
	 * than silently becoming market orders.
	 */
	public function place(kind:String, spec:Dynamic, placedBar:Int):Int {
		var type = field(spec, "type", "market");
		if (type != "market" && type != "limit" && type != "stop")
			throw 'order: unknown type "$type" (expected market | limit | stop)';
		var px = Math.NaN;
		if (type != "market") {
			var raw:Dynamic = Reflect.field(spec, "px");
			if (raw == null) throw 'order: $type order requires px';
			px = (raw : Float);
			if (Math.isNaN(px) || !Math.isFinite(px) || px <= 0)
				throw 'order: $type px must be a positive finite number (got $px)';
		}
		var qty:Null<Float> = null;
		var rawQty:Dynamic = Reflect.field(spec, "qty");
		if (rawQty != null) qty = (rawQty : Float);
		var tif = -1;
		var rawTif:Dynamic = Reflect.field(spec, "tifBars");
		if (rawTif != null) tif = Std.int((rawTif : Float));
		var id = nextId++;
		pending.push({ id: id, kind: kind, type: type, px: px, qty: qty, placedBar: placedBar, tifBars: tif });
		return id;
	}

	public function cancelAll():Int {
		var n = pending.length;
		pending = [];
		return n;
	}

	public function cancel(id:Int):Bool {
		for (i in 0...pending.length)
			if (pending[i].id == id) {
				pending.splice(i, 1);
				return true;
			}
		return false;
	}

	public function pendingCount():Int return pending.length;

	/**
	 * Evaluate the book against a new bar. Returns fills in placement order;
	 * filled and expired orders are removed. `position` decides a flat
	 * order's side. Orders placed on `barIndex` itself are not eligible
	 * (strategy handlers run after beginBar — see latency note above).
	 */
	public function evalBar(open:Float, high:Float, low:Float, barIndex:Int, position:Float):Array<BookFill> {
		if (pending.length == 0) return [];
		var fills:Array<BookFill> = [];
		var keep:Array<PendingOrder> = [];
		for (o in pending) {
			if (o.placedBar >= barIndex) { // not yet eligible
				keep.push(o);
				continue;
			}
			if (o.tifBars >= 0 && barIndex > o.placedBar + o.tifBars)
				continue; // expired
			var isBuy = switch (o.kind) {
				case "long": true;
				case "short": false;
				case "flat":
					if (position == 0) continue; // nothing to close — drop
					position < 0; // closing a short buys
				default: continue;
			};
			var px = fillPrice(o.type, isBuy, o.px, open, high, low);
			if (Math.isNaN(px)) {
				keep.push(o);
				continue;
			}
			fills.push({ kind: o.kind, price: px, qty: o.qty, orderId: o.id, orderType: o.type });
		}
		pending = keep;
		return fills;
	}

	/** NaN = no fill this bar. See the class doc for the conservative gap rules. */
	static function fillPrice(type:String, isBuy:Bool, px:Float, open:Float, high:Float, low:Float):Float {
		return switch (type) {
			case "market":
				open;
			case "limit":
				if (isBuy) {
					if (open <= px) open;
					else if (low <= px) px;
					else Math.NaN;
				} else {
					if (open >= px) open;
					else if (high >= px) px;
					else Math.NaN;
				}
			case "stop":
				if (isBuy) {
					if (open >= px) open;
					else if (high >= px) px;
					else Math.NaN;
				} else {
					if (open <= px) open;
					else if (low <= px) px;
					else Math.NaN;
				}
			default:
				Math.NaN;
		};
	}

	static function field(o:Dynamic, name:String, def:String):String {
		var v:Dynamic = Reflect.field(o, name);
		return v == null ? def : Std.string(v);
	}
}

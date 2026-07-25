package musescript.harness;

import musescript.indicators.GrowableVec;

/**
 * Simple market-at-close order simulator + position tracking.
 */
class OrderSim {
	public var position:Float;
	public var cash:Float;
	/** Accumulates once per bar (`mark()`) to full backtest length -- a `GrowableVec<Float>`
	 * (see GrowableVec.hx), not a plain `Array<Float>`, for unboxed pushes on the JVM target.
	 * `Metrics`/`BacktestResult`/JSON-serialization consumers need a real `Array<Float>` --
	 * call `.toArray()` at THOSE boundaries rather than materializing here on every push. */
	public var equity:GrowableVec<Float>;
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
	/**
	 * Pending limit/market/stop order book (ROADMAP "Execution realism").
	 * Empty unless a strategy places spec-object orders — see `submit`; the
	 * legacy close-fill verbs never touch it.
	 */
	public var book:OrderBook;
	/**
	 * Opt-in bankruptcy kill-switch for corpus-evo's `--equity-floor` (see the MurmurationSim x
	 * corpus-evo integration plan's Phase 1 "bankruptcy difficulty crank"). `0.0` (default) is
	 * disabled -- exactly today's behavior for every existing caller. When set positive, `mark()`
	 * latches `bankrupt = true` the first time equity crosses at or below it; the flag is
	 * STICKY for the rest of the run (a genome that claws back above the floor after touching it
	 * is still charged the bankruptcy -- that's the whole point of a solvency gate, not a
	 * point-in-time equity check). Trading itself is NOT blocked once bankrupt -- `mark()` still
	 * only OBSERVES equity, same as always; a caller that wants the floor to actually gate fitness
	 * reads `bankrupt` after the run (see Fitness.evaluate's `FitnessResult.bankrupt`).
	 */
	public var equityFloor:Float = 0.0;
	public var bankrupt:Bool = false;
	var pendingKind:String;
	/** `NaN` means "no explicit qty, auto-size on fill" -- see `long`/`short`'s own doc comment
	 * on why the omitted-qty sentinel is NaN (a genuine unboxed Float value) rather than null
	 * (which forces every JVM-target call into `long`/`short`/`executeLong`/`executeShort` to box
	 * qty as `java.lang.Double`, defeating escape analysis on this exact per-bar hot path -- see
	 * PLAN_EVO_SPEED.md / the JIT audit that found this). */
	var pendingQty:Float;

	public function new(?initialCash:Float = 100000) {
		position = 0;
		cash = initialCash;
		equity = new GrowableVec<Float>();
		trades = 0;
		wins = 0;
		entryPrice = 0;
		entryBar = -1;
		fills = [];
		executionMode = "same-close";
		book = new OrderBook();
		pendingKind = "";
		pendingQty = Math.NaN;
	}

	/**
	 * Single entry point for the strategy verbs (`long`/`short`/`flat`) across
	 * every execution tier. `arg` is either a plain qty (legacy immediate
	 * close-fill path, bit-identical to historical behavior) or an order-spec
	 * object `{ type: "limit"|"stop"|"market", ?px, ?qty, ?tifBars }`, which
	 * goes to the pending book and fills on FUTURE bars only.
	 */
	public function submit(kind:String, arg:Dynamic, closePx:Float, ?barIndex:Int = -1):Void {
		if (arg != null && Reflect.hasField(arg, "type")) {
			book.place(kind, arg, barIndex);
			return;
		}
		var qty:Float = arg == null ? Math.NaN : (arg : Float);
		switch (kind) {
			case "long": long(closePx, qty, barIndex);
			case "short": short(closePx, qty, barIndex);
			case "flat" | "close": flat(closePx, barIndex);
			default:
		}
	}

	/** `qty` NaN means auto-size on fill; `barIndex` -1 means "unknown" -- see `pendingQty`'s doc
	 * comment for why both are plain (unboxed on the JVM target) primitives now instead of
	 * `Null<Float>`/optional `Int`. */
	public function long(price:Float, qty:Float, barIndex:Int):Void {
		if (executionMode == "next-open") {
			queue("long", qty);
			return;
		}
		executeLong(price, qty, barIndex);
	}

	public function short(price:Float, qty:Float, barIndex:Int):Void {
		if (executionMode == "next-open") {
			queue("short", qty);
			return;
		}
		executeShort(price, qty, barIndex);
	}

	public function flat(price:Float, barIndex:Int):Void {
		if (executionMode == "next-open") {
			queue("flat", Math.NaN);
			return;
		}
		executeFlat(price, barIndex);
	}

	/**
	 * Apply orders queued by previous bars before the current bar's handlers
	 * run: first the legacy next-open queue, then the pending book (evaluated
	 * against this bar's full range with `high`/`low`; callers that predate
	 * the book pass open only, which restricts book fills to gap/market cases
	 * — the engine passes the full range).
	 */
	public function beginBar(open:Float, barIndex:Int, ?high:Float, ?low:Float):Void {
		if (executionMode == "next-open" && pendingKind != "") {
			var kind = pendingKind;
			var qty = pendingQty;
			pendingKind = "";
			pendingQty = Math.NaN;
			switch (kind) {
				case "long": executeLong(open, qty, barIndex);
				case "short": executeShort(open, qty, barIndex);
				case "flat": executeFlat(open, barIndex);
				default:
			}
		}
		if (book.pendingCount() > 0) {
			var h = high != null ? high : open;
			var l = low != null ? low : open;
			// `f.price` is passed RAW (unslipped) -- executeLong/executeShort/executeFlat now
			// apply `slip()` themselves (see their doc comment), so slipping it here TOO would
			// double-charge every book-path fill (caught by testSlippageAppliedAgainstTrader
			// expecting exactly one slip application, not two compounded).
			for (f in book.evalBar(open, h, l, barIndex, position)) {
				switch (f.kind) {
					case "long": executeLong(f.price, f.qty, barIndex);
					case "short": executeShort(f.price, f.qty, barIndex);
					case "flat": executeFlat(f.price, barIndex);
					default:
				}
			}
		}
	}

	/** Slippage against the trader: buys pay more, sells receive less. */
	inline function slip(price:Float, isBuy:Bool):Float {
		var k = book.slippageBps / 10000.0;
		return isBuy ? price * (1 + k) : price * (1 - k);
	}

	public function hasPendingOrder():Bool return pendingKind != "";

	function queue(kind:String, qty:Float):Void {
		// Last signal on a bar wins. This makes contradictory same-bar rules explicit
		// without leaking the next bar's open into strategy evaluation.
		pendingKind = kind;
		pendingQty = qty;
	}

	// `executeLong`/`executeShort`/`executeFlat` are the LEGACY immediate-fill path -- what every
	// `long(qty)`/`short(qty)`/`flat()` strategy verb actually calls (via `submit`/`long`/`short`/
	// `flat` above), as opposed to the pending-order-book path (`beginBar`'s `book.evalBar` loop),
	// which already applied `slip()` against spec-object limit/stop/market orders. Until now this
	// path charged NO cost at all -- zero slippage, zero commission, fills at the bare price --
	// which is the overwhelmingly common path (essentially every existing MuseScript strategy,
	// and every musescript.evo genome, trades via the plain verbs, not spec-object orders). `slip`
	// reuses the SAME `book.slippageBps` knob the order-book path already has (default 0, so this
	// is a zero-behavior-change fix for every caller that never sets it -- see OrderBook.hx), just
	// widened to cover the path basically everyone actually uses.
	// `entryPrice` is a WEIGHTED-AVERAGE cost basis across every same-direction fill (pyramiding),
	// not just the latest one -- previously it was silently overwritten by each new fill, so
	// unrealizedPnl/unrealized_pnl_pct/bars_in_trade-based risk-managed exits (this session's
	// growRiskExit vocabulary) would score P&L against the WRONG basis the moment a strategy (or
	// an evolved genome, before Expand.hx's position()-guard) pyramided into an existing position.
	// Confirmed empirically: long(1)@100, long(1)@110, long(1)@120 previously left entryPrice=120
	// (unrealizedPnl at 120 == 0) instead of the true average 110 (unrealizedPnl at 120 == 30).
	/**
	 * Capital constraint: a requested `qty` is clamped to what current `cash` can actually afford
	 * at `price` -- previously ONLY the "size unspecified" default (`Math.floor(cash / price)`,
	 * still the fallback when `qty` is NaN) enforced this; an EXPLICIT qty (what every genome-
	 * evolved strategy's `long(size)`/`short(size)` always passes, via Expand.hx) bypassed it
	 * entirely. A real corpus-evo champion exploited exactly this: `size` grew into a raw
	 * `volume` scalar (the bar's own share-volume field), letting a single trade request literally
	 * millions of shares against a $100k starting account and post a fictional multi-BILLION-
	 * dollar equity swing off a tiny favorable price move. This doesn't just block that one shape
	 * (a grammar restriction on what `size` can grow into would only do that) -- it makes ANY
	 * unrealistically-sized position, however evolution or a hand-written strategy arrives at it,
	 * structurally impossible to execute, the same way a real broker's margin check would.
	 */
	static function affordableQty(cash:Float, price:Float):Float {
		return Math.max(0, Math.floor(cash / price));
	}

	/**
	 * Real risk cap for an EXPLICIT qty request -- as opposed to `affordableQty` above, which
	 * still governs the bare-`long()`/`short()` "size unspecified, deploy everything" convention
	 * (a deliberate, legitimate choice a hand-written strategy can make on purpose, e.g.
	 * corpus/strategies/00_buy_hold.ms). Found via a SECOND, subtler corpus-evo exploit past the
	 * plain affordability clamp above: `size = volume` (or any similarly oversized expression)
	 * ALWAYS exceeds `affordableQty`, so it ALWAYS got clamped to exactly 100% of current cash --
	 * meaning that genome was betting EVERYTHING on every single trade, every time (a $500k
	 * starting basket compounded to $141M over just 19 trades this way), which a real risk-managed
	 * account would never allow regardless of whether any ONE trade happens to be individually
	 * affordable. Caps what an oversized EXPLICIT request can be clamped DOWN TO -- 25% of current
	 * cash, a real risk-management convention (never risk more than a modest slice of capital on
	 * one position). A NORMAL explicit qty (`long(1)`, `long(2)`, ...) is essentially always well
	 * under 25% of a $100k+ account regardless of price, so this is a no-op for every legitimate
	 * strategy shape -- it only ever binds on an already-unreasonable request.
	 */
	static inline var MAX_POSITION_FRACTION = 0.25;

	static function riskCappedQty(cash:Float, price:Float):Float {
		return Math.max(0, Math.floor((cash * MAX_POSITION_FRACTION) / price));
	}

	function executeLong(price:Float, qty:Float, barIndex:Int):Void {
		var wasFlat = position == 0;
		var requested = !Math.isNaN(qty) ? qty : (position == 0 ? Math.floor(cash / price) : 0);
		var cap = !Math.isNaN(qty) ? riskCappedQty(cash, price) : affordableQty(cash, price);
		var q = Math.min(requested, cap);
		if (q <= 0) return;
		if (position < 0) executeFlat(price, barIndex); // closes the short first; position becomes 0
		var px = slip(price, true); // opening/adding to a long is a buy
		var priorQty = position; // 0 if flat/just-closed-a-short, else the existing LONG qty
		entryPrice = priorQty > 0 ? (entryPrice * priorQty + px * q) / (priorQty + q) : px;
		cash -= q * px;
		position += q;
		if (wasFlat && position != 0 && barIndex >= 0) entryBar = barIndex;
		trades++;
		fills.push({ kind: "long", bar: barIndex, price: px, qty: q, pnl: 0.0 });
	}

	function executeShort(price:Float, qty:Float, barIndex:Int):Void {
		var wasFlat = position == 0;
		var requested = !Math.isNaN(qty) ? qty : (position == 0 ? Math.floor(cash / price) : 0);
		// Same capital clamp as executeLong -- see riskCappedQty's doc comment. Shorting uses the
		// SAME rough cash/price margin proxy the pre-existing NaN-qty default already used for
		// shorts, not a new assumption.
		var cap = !Math.isNaN(qty) ? riskCappedQty(cash, price) : affordableQty(cash, price);
		var q = Math.min(requested, cap);
		if (q <= 0) return;
		if (position > 0) executeFlat(price, barIndex); // closes the long first; position becomes 0
		var px = slip(price, false); // opening/adding to a short is a sell
		var priorQty = -position; // 0 if flat/just-closed-a-long, else the existing SHORT qty magnitude
		entryPrice = priorQty > 0 ? (entryPrice * priorQty + px * q) / (priorQty + q) : px;
		cash += q * px;
		position -= q;
		if (wasFlat && position != 0 && barIndex >= 0) entryBar = barIndex;
		trades++;
		fills.push({ kind: "short", bar: barIndex, price: px, qty: q, pnl: 0.0 });
	}

	function executeFlat(price:Float, barIndex:Int):Void {
		if (position == 0) return;
		var px = slip(price, position < 0); // closing a short covers (buy); closing a long sells
		var pnl = position * (px - entryPrice);
		if (pnl > 0) wins++;
		var closed = position;
		cash += position * px;
		position = 0;
		entryBar = -1;
		trades++;
		fills.push({ kind: "flat", bar: barIndex, price: px, qty: closed, pnl: pnl });
	}

	public function mark(price:Float):Void {
		var e = cash + position * price;
		equity.push(e);
		if (equityFloor > 0 && e <= equityFloor) bankrupt = true;
	}

	public function reset(?initialCash:Float = 100000):Void {
		position = 0;
		cash = initialCash;
		equity = new GrowableVec<Float>();
		trades = 0;
		wins = 0;
		entryPrice = 0;
		entryBar = -1;
		fills = [];
		book.reset();
		pendingKind = "";
		pendingQty = Math.NaN;
		bankrupt = false;
		// equityFloor is deliberately NOT reset here -- it's a caller-configured limit (set once
		// after construction/reset by whoever wants the kill-switch active), not per-run state.
	}

	public function positionSize():Float return position;

	public function barsInTrade(currentBar:Int):Int {
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

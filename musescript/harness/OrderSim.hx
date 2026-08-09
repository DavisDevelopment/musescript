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
	 * When false, `fills` is left empty and the per-fill records are never allocated. For callers
	 * that only want the scalar outcome -- `trades`, `wins`, the equity curve, `bankrupt` -- which
	 * are all maintained independently of this list. Attribution is the motivating case: a column
	 * swap runs a whole simulation to read one Sharpe out of it, and at ~15 swaps per child it was
	 * allocating a `Fill` structure per execution that nothing would ever look at.
	 *
	 * Default true, so every existing caller keeps the trade log it has always had.
	 */
	public var recordFills:Bool = true;
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
	/**
	 * When false, `mark` does not push the equity curve — it streams bar-to-bar returns into
	 * `markReturns` instead. Score-only NMA paths (`scorePrepared`, default evo with
	 * `equityCurveNeeded=false`) never read the curve, and JFR previously put GrowableVec growth
	 * / push traffic under `mark` on the hot profile. Default true so every existing caller keeps
	 * the curve it has always had.
	 */
	public var trackCurve:Bool = true;
	/** Equity after the most recent `mark` (also the curve's last point when `trackCurve`). */
	public var lastMark:Float = 0.0;
	/** Return stream for `!trackCurve` — same values `Metrics.returnsFromEquity` would emit. Lazy. */
	public var markReturns:Null<GrowableVec<Float>> = null;
	/** Per-tag fire counts from string-labelled order calls (`flat("profit_lock")`). Surfaced in the
	 * result JSON as `exitTags` so a strategy author can see which exit/entry layers actually trigger
	 * -- an absent or 0-count tag is a silent no-op layer. */
	public var tagFires:Map<String, Int> = new Map();
	var pendingKind:String;
	/** `NaN` means "no explicit qty, auto-size on fill" -- see `long`/`short`'s own doc comment
	 * on why the omitted-qty sentinel is NaN (a genuine unboxed Float value) rather than null
	 * (which forces every JVM-target call into `long`/`short`/`executeLong`/`executeShort` to box
	 * qty as `java.lang.Double`, defeating escape analysis on this exact per-bar hot path -- see
	 * PLAN_EVO_SPEED.md / the JIT audit that found this). */
	var pendingQty:Float;
	var markPrev:Float = 0.0;
	var markHavePrev:Bool = false;

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
	 * close-fill path, bit-identical to historical behavior), an order-spec
	 * object `{ type: "limit"|"stop"|"market", ?px, ?qty, ?tifBars, ?groupId,
	 * ?onFill }` (pending book, future bars only), a bracket sugar object
	 * `{ ?type, ?px, ?qty, bracket: { ?stop/{px|dist}, ?limit/{px|dist},
	 * link: "oco" } }` (entry + OCO exit flats), or — for `flat` only —
	 * `{ qty }` / `{ frac }` for immediate partial scale-out (no `type` key).
	 */
	/** If `arg` is a string LABEL, bump its per-tag fire count and return true (so the caller treats
	 * it as no order spec / auto-size). The single choke point every order surface routes tags through
	 * -- direct `orders.flat(...)` closures on the compiled path bypass `submit`, so they call this too. */
	public function noteTag(arg:Dynamic):Bool {
		if (!Std.isOfType(arg, String)) return false;
		var t:String = cast arg;
		tagFires.set(t, (tagFires.exists(t) ? tagFires.get(t) : 0) + 1);
		return true;
	}

	public function submit(kind:String, arg:Dynamic, closePx:Float, ?barIndex:Int = -1):Void {
		// A STRING arg is an exit/entry LABEL, not an order spec: record that this tagged layer fired
		// (per-tag fire counts surface in the result JSON) and fall through to a normal auto-sized
		// order. Diagnoses "silent no-op exit layers" -- a tag with count 0/absent never triggered.
		if (noteTag(arg)) arg = null;
		// Bracket sugar: expand before the plain typed-spec path (entry may also carry type/px).
		if (arg != null && Reflect.hasField(arg, "bracket")) {
			placeBracket(kind, arg, closePx, barIndex);
			return;
		}
		if (arg != null && Reflect.hasField(arg, "type")) {
			book.place(kind, arg, barIndex);
			return;
		}
		// Immediate partial flat: `flat({qty:n})` / `flat({frac:f})` — no `type`, so not a book order.
		if ((kind == "flat" || kind == "close") && arg != null && isPartialFlatSpec(arg)) {
			var q = resolvePartialFlatQty(arg, position);
			flat(closePx, barIndex, q);
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

	/**
	 * Expand `long|short({ …, bracket: { stop?, limit?, link: "oco" } })` into
	 * a pending entry plus OCO exit flats. Absolute `px` or relative `dist`
	 * (from `closePx` at place time): long stop = ref−dist / limit = ref+dist;
	 * short mirrors. Entry has no cancel_group; stop+limit share one groupId.
	 * Book latency unchanged (first eligible bar t+1).
	 */
	function placeBracket(kind:String, arg:Dynamic, closePx:Float, barIndex:Int):Void {
		if (kind != "long" && kind != "short")
			throw 'bracket: only long/short support bracket sugar (got $kind)';
		var bracket:Dynamic = Reflect.field(arg, "bracket");
		if (bracket == null)
			throw "bracket: bracket object is required";
		var rawLink:Dynamic = Reflect.field(bracket, "link");
		var link = rawLink == null ? "oco" : Std.string(rawLink);
		if (link != "oco")
			throw 'bracket: unknown link "$link" (expected oco)';
		var stopLeg:Dynamic = Reflect.field(bracket, "stop");
		var limitLeg:Dynamic = Reflect.field(bracket, "limit");
		if (stopLeg == null && limitLeg == null)
			throw "bracket: need at least one of stop | limit";

		var isLong = kind == "long";
		var entryType = "market";
		var rawType:Dynamic = Reflect.field(arg, "type");
		if (rawType != null) entryType = Std.string(rawType);
		var entrySpec:Dynamic = { type: entryType };
		var rawQty:Dynamic = Reflect.field(arg, "qty");
		var qty:Null<Float> = null;
		if (rawQty != null) {
			qty = (rawQty : Float);
			Reflect.setField(entrySpec, "qty", qty);
		}
		var rawPx:Dynamic = Reflect.field(arg, "px");
		if (rawPx != null) Reflect.setField(entrySpec, "px", rawPx);
		var rawTif:Dynamic = Reflect.field(arg, "tifBars");
		if (rawTif != null) Reflect.setField(entrySpec, "tifBars", rawTif);
		book.place(kind, entrySpec, barIndex);

		var gid = book.allocGroupId();
		if (stopLeg != null) {
			var stopPx = resolveBracketLegPx(stopLeg, closePx, isLong, true);
			var stopSpec:Dynamic = {
				type: "stop", px: stopPx, groupId: gid, onFill: "cancel_group"
			};
			if (qty != null) Reflect.setField(stopSpec, "qty", qty);
			book.place("flat", stopSpec, barIndex);
		}
		if (limitLeg != null) {
			var limPx = resolveBracketLegPx(limitLeg, closePx, isLong, false);
			var limSpec:Dynamic = {
				type: "limit", px: limPx, groupId: gid, onFill: "cancel_group"
			};
			if (qty != null) Reflect.setField(limSpec, "qty", qty);
			book.place("flat", limSpec, barIndex);
		}
	}

	/** Resolve `{ px }` or `{ dist }` for a bracket exit leg against place-time ref. */
	static function resolveBracketLegPx(leg:Dynamic, refPx:Float, isLong:Bool, isStop:Bool):Float {
		var rawPx:Dynamic = Reflect.field(leg, "px");
		var rawDist:Dynamic = Reflect.field(leg, "dist");
		if (rawPx != null && rawDist != null)
			throw "bracket: leg needs exactly one of px | dist (got both)";
		if (rawPx != null) {
			var px:Float = rawPx;
			if (Math.isNaN(px) || !Math.isFinite(px) || px <= 0)
				throw 'bracket: px must be a positive finite number (got $px)';
			return px;
		}
		if (rawDist != null) {
			var dist:Float = rawDist;
			if (Math.isNaN(dist) || !Math.isFinite(dist) || dist <= 0)
				throw 'bracket: dist must be a positive finite number (got $dist)';
			if (Math.isNaN(refPx) || !Math.isFinite(refPx) || refPx <= 0)
				throw 'bracket: cannot resolve dist without a positive ref price (got $refPx)';
			var px = if (isLong)
				(isStop ? refPx - dist : refPx + dist)
			else
				(isStop ? refPx + dist : refPx - dist);
			if (px <= 0)
				throw 'bracket: resolved px $px is not positive (ref=$refPx dist=$dist)';
			return px;
		}
		throw "bracket: leg needs exactly one of px | dist";
	}

	static function isPartialFlatSpec(arg:Dynamic):Bool {
		if (Std.isOfType(arg, String) || Std.isOfType(arg, Float) || Std.isOfType(arg, Int) || Std.isOfType(arg, Bool))
			return false;
		return Reflect.hasField(arg, "qty") || Reflect.hasField(arg, "frac");
	}

	/** Shares to close from `{qty}` or `{frac}` given current signed `position`. */
	static function resolvePartialFlatQty(arg:Dynamic, position:Float):Float {
		var abs = Math.abs(position);
		if (abs == 0) return 0;
		var rawQty:Dynamic = Reflect.field(arg, "qty");
		if (rawQty != null) {
			var q:Float = rawQty;
			if (Math.isNaN(q) || !Math.isFinite(q) || q <= 0)
				throw 'flat: qty must be a positive finite number (got $q)';
			return Math.min(q, abs);
		}
		var rawFrac:Dynamic = Reflect.field(arg, "frac");
		if (rawFrac != null) {
			var f:Float = rawFrac;
			if (Math.isNaN(f) || !Math.isFinite(f) || f <= 0 || f > 1)
				throw 'flat: frac must be in (0, 1] (got $f)';
			return abs * f;
		}
		return abs;
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

	/** `qty` NaN = close the full position (legacy). Otherwise close min(|position|, qty). */
	public function flat(price:Float, barIndex:Int, ?qty:Float):Void {
		var q = qty == null ? Math.NaN : qty;
		if (executionMode == "next-open") {
			queue("flat", q);
			return;
		}
		executeFlat(price, barIndex, q);
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
				case "flat": executeFlat(open, barIndex, qty);
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
					case "long": executeLong(f.price, f.qty == null ? Math.NaN : f.qty, barIndex);
					case "short": executeShort(f.price, f.qty == null ? Math.NaN : f.qty, barIndex);
					case "flat": executeFlat(f.price, barIndex, f.qty == null ? Math.NaN : f.qty);
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
	 *
	 * muse.np helpers (`vol_target_qty` / `mask_qty`) return **requested** qty only; they do not
	 * bypass this clamp. Prefer them for evo-safe sizing, but `size = volume` remains sim-capped.
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
		if (recordFills) fills.push({ kind: "long", bar: barIndex, price: px, qty: q, pnl: 0.0 });
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
		if (recordFills) fills.push({ kind: "short", bar: barIndex, price: px, qty: q, pnl: 0.0 });
	}

	/**
	 * Close `qty` shares of the current position (NaN/`abs(position)` = full flat).
	 * Partial closes keep the remainder's cost basis; `entryBar` clears only when fully flat.
	 */
	function executeFlat(price:Float, barIndex:Int, ?qty:Float):Void {
		if (position == 0) return;
		var absPos = Math.abs(position);
		var closeAbs = absPos;
		if (qty != null && !Math.isNaN(qty)) {
			if (qty <= 0) return;
			closeAbs = Math.min(qty, absPos);
		}
		if (closeAbs <= 0) return;
		var px = slip(price, position < 0); // closing a short covers (buy); closing a long sells
		var signedClose = position > 0 ? closeAbs : -closeAbs;
		var pnl = signedClose * (px - entryPrice);
		if (pnl > 0) wins++;
		cash += signedClose * px;
		position -= signedClose;
		if (position == 0) entryBar = -1;
		trades++;
		if (recordFills) fills.push({ kind: "flat", bar: barIndex, price: px, qty: signedClose, pnl: pnl });
	}

	/**
	 * Pre-size the equity curve (or the thin-mark return stream) for a run of known length.
	 * `equity` otherwise starts at the `GrowableVec` default of 8 and capacity-doubles its way
	 * up, so a 320-bar sim allocates six throwaway `double[]` (1008 slots) and six `arraycopy`s
	 * to reach one 512-slot array — per sim, and the NMA path builds one per evaluation AND one
	 * per attribution column swap. JFR put every byte of `GrowableFloatImpl.grow` on this
	 * codebase's hot profile under `mark`.
	 *
	 * Capacity only: contents, length and every reader are unchanged. Callable only before the
	 * first `mark`. After `clear()` a recycled sim reuses its backing store via `ensureCapacity`.
	 */
	public function reserveEquity(bars:Int):Void {
		if (bars <= 0) return;
		if (trackCurve) {
			if (equity.length == 0) equity.ensureCapacity(bars);
		} else {
			if (markReturns == null) markReturns = new GrowableVec<Float>(bars > 1 ? bars - 1 : 8);
			else if (markReturns.length == 0 && bars > 1) markReturns.ensureCapacity(bars - 1);
		}
	}

	public function mark(price:Float):Void {
		var e = cash + position * price;
		lastMark = e;
		if (trackCurve) {
			equity.push(e);
		} else {
			var rets = markReturns;
			if (rets == null) {
				rets = new GrowableVec<Float>();
				markReturns = rets;
			}
			if (markHavePrev) {
				rets.push(markPrev > 0 ? (e - markPrev) / markPrev : 0.0);
			} else {
				markHavePrev = true;
			}
			markPrev = e;
		}
		if (equityFloor > 0 && e <= equityFloor) bankrupt = true;
	}

	/**
	 * Sample Sharpe of `markReturns` — identical algorithm to `Metrics.sharpe(_, 0)`, so
	 * `!trackCurve` stays bit-exact with the equity → returns → sharpe path.
	 *
	 * Omitted override reads `Metrics.periodsPerYear` (default 252). If you change the
	 * arithmetic here, change `Metrics.sharpe` and `NmaFitness.sharpeOfEquity` identically —
	 * `TestEvoVariation.testSharpeImplementationsAgreeBitExactly` asserts all three match.
	 */
	public function sharpeOnline(?periodsPerYearOverride:Null<Float>):Float {
		var py = periodsPerYearOverride != null ? periodsPerYearOverride : Metrics.periodsPerYear;
		var rets = markReturns;
		if (rets == null) return 0;
		var n = rets.length;
		if (n < 2) return 0;
		var mean = 0.0;
		var i = 0;
		while (i < n) {
			mean += rets.at(i);
			i++;
		}
		mean /= n;
		var var_ = 0.0;
		i = 0;
		while (i < n) {
			var d = rets.at(i) - mean;
			var_ += d * d;
			i++;
		}
		var_ /= n - 1;
		var std = Math.sqrt(var_);
		if (std == 0) return 0;
		return (mean / std) * Math.sqrt(py);
	}

	public function reset(?initialCash:Float = 100000):Void {
		position = 0;
		cash = initialCash;
		equity.clear();
		if (markReturns != null) markReturns.clear();
		trades = 0;
		wins = 0;
		entryPrice = 0;
		entryBar = -1;
		fills.resize(0);
		book.reset();
		pendingKind = "";
		pendingQty = Math.NaN;
		bankrupt = false;
		lastMark = 0.0;
		markPrev = 0.0;
		markHavePrev = false;
		// equityFloor / trackCurve / recordFills / executionMode / book.slippageBps are
		// deliberately NOT reset — caller-configured for the run, not per-bar state.
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

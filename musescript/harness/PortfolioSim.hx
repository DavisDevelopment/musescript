package musescript.harness;

import musescript.indicators.GrowableVec;

/**
 * Multi-symbol positions + shared cash. Companion to single-symbol `OrderSim`.
 * Strategies drive it via `buy`/`sell_all`/`rebalance_equal` / `target_weight`,
 * bags (`portfolio_apply` / …), or per-symbol pending books via `submit` /
 * `beginBar` (same latency honesty as `OrderSim` — place at t, eligible t+1).
 *
 * Positions are signed: &gt;0 long, &lt;0 short. Equity = cash + Σ qty·price.
 *
 * **OCO / `groupId`**: portfolio-global namespace. Orders placed through `submit`
 * that share a `groupId` with `onFill: "cancel_group"` cancel siblings on *any*
 * symbol when the first leg fills (`beginBar` fans out after each book's
 * `evalBar`, before the next symbol — sorted order keeps same-bar competition
 * deterministic). Independent multi-name OCOs must use distinct ids
 * (`allocGroupId()`). Bracket sugar allocates one shared exit id per place.
 */
class PortfolioSim {
	public var cash:Float;
	/** Round-trip-agnostic per-side trading cost in basis points of traded notional
	    (commission + spread/slippage proxy). Charged on every executed delta. 0 = frictionless. */
	public var tradingCostBps:Float = 0.0;
	/**
	 * Per-fill slippage in basis points applied against the trader on pending-book
	 * fills (buys pay more, sells receive less). Mirrors `OrderBook.slippageBps` /
	 * `OrderSim`; default 0. Immediate `buy`/`rebalance` use `tradingCostBps` only.
	 */
	public var slippageBps:Float = 0.0;
	public var positions:Map<String, Float>;
	public var entryPrices:Map<String, Float>;
	public var entryBars:Map<String, Int>;
	/** See `OrderSim.equity`'s doc comment -- `GrowableVec<Float>`, not `Array<Float>`. */
	public var equity:GrowableVec<Float>;
	public var trades:Int;
	public var wins:Int;
	public var fills:Array<Fill>;
	public var lastPrices:Map<String, Float>;
	/** Per-symbol pending limit/stop/market books (lazy). */
	public var books:Map<String, OrderBook>;
	/** Portfolio-wide OCO group counter (`allocGroupId`). */
	var nextGroupId:Int;

	public function new(?initialCash:Float = 100000) {
		cash = initialCash;
		positions = new Map();
		entryPrices = new Map();
		entryBars = new Map();
		equity = new GrowableVec<Float>();
		trades = 0;
		wins = 0;
		fills = [];
		lastPrices = new Map();
		books = new Map();
		nextGroupId = 1;
	}

	public function reset(?initialCash:Float = 100000):Void {
		cash = initialCash;
		positions = new Map();
		entryPrices = new Map();
		entryBars = new Map();
		equity = new GrowableVec<Float>();
		trades = 0;
		wins = 0;
		fills = [];
		lastPrices = new Map();
		books = new Map();
		nextGroupId = 1;
		// slippageBps / tradingCostBps are caller-configured for the run, not reset.
	}

	/** Fresh portfolio-global group id for cross-symbol / bracket OCO sets. */
	public function allocGroupId():Int {
		return nextGroupId++;
	}

	/** Bump allocator past an explicit user `groupId` so later allocs never collide. */
	function observeGroupId(gid:Int):Void {
		if (gid >= nextGroupId) nextGroupId = gid + 1;
	}

	/** Lazy per-symbol pending book. */
	public function bookOf(sym:String):OrderBook {
		var b = books.get(sym);
		if (b == null) {
			b = new OrderBook();
			b.slippageBps = slippageBps;
			books.set(sym, b);
		}
		return b;
	}

	public function pendingCount(?sym:String):Int {
		if (sym != null && sym != "") {
			var b = books.get(sym);
			return b == null ? 0 : b.pendingCount();
		}
		var n = 0;
		for (_ => b in books) n += b.pendingCount();
		return n;
	}

	public function cancelAll(?sym:String):Int {
		if (sym != null && sym != "") {
			var b = books.get(sym);
			return b == null ? 0 : b.cancelAll();
		}
		var n = 0;
		for (_ => b in books) n += b.cancelAll();
		return n;
	}

	public function cancel(sym:String, id:Int):Bool {
		var b = books.get(sym);
		return b == null ? false : b.cancel(id);
	}

	/**
	 * Cancel every pending order with `groupId`.
	 * When `sym` is null/empty, cancels across all symbol books (portfolio-global OCO).
	 */
	public function cancelGroup(groupId:Int, ?sym:String):Int {
		if (sym != null && sym != "") {
			var b = books.get(sym);
			return b == null ? 0 : b.cancelGroup(groupId);
		}
		var n = 0;
		for (_ => b in books) n += b.cancelGroup(groupId);
		return n;
	}

	/**
	 * Panel pending / immediate order entry (mirrors `OrderSim.submit` per symbol).
	 * `arg` is qty (immediate), order-spec `{ type, ?px, ?qty, ?tifBars, ?groupId, ?onFill }`,
	 * bracket sugar, or — for flat — `{ qty }` / `{ frac }` scale-out.
	 * Explicit `groupId` values are portfolio-global (see class doc).
	 */
	public function submit(kind:String, sym:String, arg:Dynamic, closePx:Float, ?barIndex:Int = -1):Void {
		if (sym == null || sym == "") return;
		if (arg != null && Reflect.hasField(arg, "bracket")) {
			placeBracket(kind, sym, arg, closePx, barIndex);
			return;
		}
		if (arg != null && Reflect.hasField(arg, "type")) {
			bookOf(sym).place(kind, arg, barIndex);
			var rawGid:Dynamic = Reflect.field(arg, "groupId");
			if (rawGid != null) observeGroupId(Std.int((rawGid : Float)));
			return;
		}
		if ((kind == "flat" || kind == "close") && arg != null && isPartialFlatSpec(arg)) {
			var q = resolvePartialFlatQty(arg, positionOf(sym));
			executeFlatSym(sym, closePx, barIndex, q);
			return;
		}
		var qty:Float = arg == null ? Math.NaN : (arg : Float);
		switch (kind) {
			case "long": executeLongSym(sym, closePx, qty, barIndex);
			case "short": executeShortSym(sym, closePx, qty, barIndex);
			case "flat" | "close": executeFlatSym(sym, closePx, barIndex, qty);
			default:
		}
	}

	/**
	 * Evaluate pending books against this session's per-symbol OHLC before strategy
	 * handlers run. Symbol iteration is sorted for deterministic cash competition.
	 * Missing / NaN opens skip that symbol's book for the bar (order stays pending).
	 * After each book's fills, `cancel_group` fans out to every other symbol so
	 * cross-symbol OCO siblings never fill later in the same bar.
	 */
	public function beginBar(
		opens:Map<String, Float>,
		highs:Map<String, Float>,
		lows:Map<String, Float>,
		barIndex:Int
	):Void {
		if (!books.keys().hasNext()) return;
		var syms:Array<String> = [];
		for (s in books.keys()) syms.push(s);
		syms.sort(Reflect.compare);
		for (sym in syms) {
			var book = books.get(sym);
			if (book == null || book.pendingCount() == 0) continue;
			var o = mapPx(opens, sym);
			if (!(o > 0) || Math.isNaN(o)) continue;
			var h = mapPx(highs, sym);
			var l = mapPx(lows, sym);
			if (!(h > 0) || Math.isNaN(h)) h = o;
			if (!(l > 0) || Math.isNaN(l)) l = o;
			// Slip is applied in execute*Sym (same double-charge guard as OrderSim.beginBar).
			var bookFills = book.evalBar(o, h, l, barIndex, positionOf(sym));
			for (f in bookFills) {
				if (f.onFill == "cancel_group" && f.groupId != null)
					cancelGroup(f.groupId);
			}
			for (f in bookFills) {
				var rawQty = f.qty == null ? Math.NaN : f.qty;
				switch (f.kind) {
					case "long": executeLongSym(sym, f.price, rawQty, barIndex);
					case "short": executeShortSym(sym, f.price, rawQty, barIndex);
					case "flat": executeFlatSym(sym, f.price, barIndex, rawQty);
					default:
				}
			}
		}
	}

	/** Slippage against the trader on book fills. */
	inline function slip(price:Float, isBuy:Bool):Float {
		var k = slippageBps / 10000.0;
		return isBuy ? price * (1 + k) : price * (1 - k);
	}

	function executeLongSym(sym:String, price:Float, qty:Float, barIndex:Int):Void {
		if (!(price > 0) || Math.isNaN(price)) return;
		var px = slip(price, true);
		if (positionOf(sym) < 0) realizeToFlat(sym, px, barIndex);
		var cur = positionOf(sym);
		var requested = !Math.isNaN(qty) ? qty : (cur == 0 ? Math.floor(cash / px) : 0);
		if (requested <= 0) return;
		var afford = Math.floor(cash / px);
		var q = Math.min(requested, afford);
		if (q <= 0) return;
		setTargetQty(sym, cur + q, px, barIndex);
	}

	function executeShortSym(sym:String, price:Float, qty:Float, barIndex:Int):Void {
		if (!(price > 0) || Math.isNaN(price)) return;
		var px = slip(price, false);
		if (positionOf(sym) > 0) realizeToFlat(sym, px, barIndex);
		var cur = positionOf(sym);
		var requested = !Math.isNaN(qty) ? qty : (cur == 0 ? Math.floor(cash / px) : 0);
		if (requested <= 0) return;
		// Same affordability proxy as OrderSim shorts / PortfolioSim cash margin.
		var afford = Math.floor(cash / px);
		var q = Math.min(requested, afford);
		if (q <= 0) return;
		setTargetQty(sym, cur - q, px, barIndex);
	}

	function executeFlatSym(sym:String, price:Float, barIndex:Int, ?qty:Float):Void {
		var pos = positionOf(sym);
		if (pos == 0) return;
		if (!(price > 0) || Math.isNaN(price)) return;
		var px = slip(price, pos < 0);
		var absPos = Math.abs(pos);
		var closeAbs = absPos;
		if (qty != null && !Math.isNaN(qty)) {
			if (qty <= 0) return;
			closeAbs = Math.min(qty, absPos);
		}
		if (closeAbs <= 0) return;
		var tgt = pos > 0 ? pos - closeAbs : pos + closeAbs;
		setTargetQty(sym, tgt, px, barIndex);
	}

	/** Bracket sugar — same rules as `OrderSim.placeBracket`; exit legs share a portfolio-global groupId. */
	function placeBracket(kind:String, sym:String, arg:Dynamic, closePx:Float, barIndex:Int):Void {
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
		var book = bookOf(sym);
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

		var gid = allocGroupId();
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

	static function mapPx(m:Map<String, Float>, sym:String):Float {
		if (m == null || !m.exists(sym)) return Math.NaN;
		return m.get(sym);
	}

	public function positionOf(sym:String):Float {
		return positions.exists(sym) ? positions.get(sym) : 0.0;
	}

	public function entryOf(sym:String):Float {
		return entryPrices.exists(sym) ? entryPrices.get(sym) : 0.0;
	}

	public function holdings():Array<String> {
		var out:Array<String> = [];
		for (sym => qty in positions) if (qty != 0) out.push(sym);
		out.sort(Reflect.compare);
		return out;
	}

	public function buy(sym:String, price:Float, ?qty:Float, ?barIndex:Int = -1):Void {
		if (sym == null || sym == "" || !(price > 0) || Math.isNaN(price)) return;
		var q = qty != null ? qty : Math.floor(cash / price);
		if (q <= 0) return;
		setTargetQty(sym, positionOf(sym) + q, price, barIndex);
	}

	public function sellAll(sym:String, price:Float, ?barIndex:Int = -1):Void {
		if (sym == null || sym == "") return;
		if (!(price > 0) || Math.isNaN(price)) {
			price = lastPrices.exists(sym) ? lastPrices.get(sym) : entryOf(sym);
		}
		setTargetQty(sym, 0, price, barIndex);
	}

	/**
	 * Equal-weight long `syms` (flatten names not in the set). Uses floor shares
	 * so cash is never overdrawn; residual stays in cash.
	 */
	public function rebalanceEqual(syms:Array<String>, prices:Map<String, Float>, ?barIndex:Int = -1):Void {
		var weights = new Map<String, Float>();
		var live:Array<String> = [];
		if (syms != null) {
			for (s in syms) {
				if (s == null || s == "") continue;
				var px = prices != null && prices.exists(s) ? prices.get(s) : Math.NaN;
				if (!(px > 0) || Math.isNaN(px)) continue;
				if (!weights.exists(s)) {
					weights.set(s, 1.0);
					live.push(s);
				}
			}
		}
		if (live.length > 0) {
			var w = 1.0 / live.length;
			for (s in live) weights.set(s, w);
		}
		applyBag(weights, prices, barIndex, true);
	}

	/** Set absolute portfolio weight for one name (signed; clamp magnitude to 1). */
	public function targetWeight(sym:String, weight:Float, prices:Map<String, Float>, ?barIndex:Int = -1):Void {
		if (sym == null || sym == "") return;
		var px = prices != null && prices.exists(sym) ? prices.get(sym) : Math.NaN;
		if (!(px > 0) || Math.isNaN(px)) return;
		var w = weight;
		if (Math.isNaN(w)) w = 0;
		if (w > 1) w = 1;
		if (w < -1) w = -1;
		var eq = equityAt(prices);
		var mag = Math.floor(Math.abs(eq * w / px));
		var targetQty = w >= 0 ? mag : -mag;
		setTargetQty(sym, targetQty, px, barIndex);
	}

	/**
	 * Drive the book toward `weights` (signed portfolio fractions).
	 * `replace=true` flattens names absent from the weight map; `false` only
	 * touches names present in `weights` (additive sleeve semantics).
	 */
	public function applyBag(
		weights:Map<String, Float>,
		prices:Map<String, Float>,
		?barIndex:Int = -1,
		replace:Bool = true
	):Void {
		if (weights == null) weights = new Map();
		if (replace) {
			for (sym in holdings()) {
				if (!weights.exists(sym) || weights.get(sym) == 0) {
					var px = resolvePrice(sym, prices);
					setTargetQty(sym, 0, px, barIndex);
				}
			}
		}
		var eq = equityAt(prices);
		for (sym => w in weights) {
			if (w == 0 || Math.isNaN(w)) {
				if (replace) {
					var px0 = resolvePrice(sym, prices);
					setTargetQty(sym, 0, px0, barIndex);
				}
				continue;
			}
			var px = resolvePrice(sym, prices);
			if (!(px > 0) || Math.isNaN(px)) continue;
			var ww = w;
			if (ww > 1) ww = 1;
			if (ww < -1) ww = -1;
			var mag = Math.floor(Math.abs(eq * ww / px));
			var targetQty = ww >= 0 ? mag : -mag;
			setTargetQty(sym, targetQty, px, barIndex);
			eq = equityAt(prices);
		}
	}

	function resolvePrice(sym:String, prices:Map<String, Float>):Float {
		var px = prices != null && prices.exists(sym) ? prices.get(sym) : Math.NaN;
		if (!(px > 0) || Math.isNaN(px))
			px = lastPrices.exists(sym) ? lastPrices.get(sym) : entryOf(sym);
		return px;
	}

	/**
	 * Transition `sym` to exactly `targetQty` shares (signed) at `price`.
	 * Handles long↔flat↔short transitions and average entry accounting.
	 */
	public function setTargetQty(sym:String, targetQty:Float, price:Float, ?barIndex:Int = -1):Void {
		if (sym == null || sym == "") return;
		if (!(price > 0) || Math.isNaN(price)) return;
		var cur = positionOf(sym);
		var tgt = Math.isNaN(targetQty) ? 0.0 : targetQty;
		if (tgt == cur) return;

		// Crossing through zero: flatten first, then open the other side.
		if (cur != 0 && tgt != 0 && (cur > 0) != (tgt > 0)) {
			realizeToFlat(sym, price, barIndex);
			cur = 0;
		}
		if (tgt == cur) return;

		if (tgt > cur) {
			// Need to buy (add long or cover short)
			var q = tgt - cur;
			if (cur >= 0) {
				// opening/adding long — cash constrained
				var afford = Math.floor(cash / price);
				if (afford < q) {
					q = afford;
					if (q <= 0) return;
					tgt = cur + q;
				}
			}
			var entryBefore = entryOf(sym);
			cash -= q * price;
			if (tradingCostBps > 0) cash -= q * price * tradingCostBps / 10000.0;
			var next = cur + q;
			positions.set(sym, next);
			if (cur == 0) {
				entryPrices.set(sym, price);
				if (barIndex >= 0) entryBars.set(sym, barIndex);
			} else if (cur > 0) {
				entryPrices.set(sym, (entryBefore * cur + price * q) / next);
			} else if (next == 0) {
				entryBars.remove(sym);
				entryPrices.remove(sym);
			}
			// covering short: keep entry until flat (cleared above when next==0)
			var pnl = 0.0;
			if (cur < 0) {
				pnl = q * (entryBefore - price);
				if (pnl > 0) wins++;
			}
			trades++;
			fills.push({
				kind: cur < 0 ? "flat" : "long",
				bar: barIndex,
				price: price,
				qty: q,
				pnl: pnl,
				symbol: sym
			});
			lastPrices.set(sym, price);
		} else {
			// Need to sell (trim long or add short)
			var q = cur - tgt;
			var entryBefore = entryOf(sym);
			cash += q * price;
			if (tradingCostBps > 0) cash -= q * price * tradingCostBps / 10000.0;
			var next = cur - q;
			var pnl = 0.0;
			if (cur > 0) {
				var sellLong = Math.min(q, cur);
				pnl = sellLong * (price - entryBefore);
				if (pnl > 0) wins++;
			}
			positions.set(sym, next);
			if (next == 0) {
				entryBars.remove(sym);
				entryPrices.remove(sym);
			} else if (cur > 0 && next > 0) {
				// trimmed long — keep entry
			} else if (cur <= 0 && next < 0) {
				if (cur == 0) {
					entryPrices.set(sym, price);
					if (barIndex >= 0) entryBars.set(sym, barIndex);
				} else {
					entryPrices.set(sym, (entryBefore * (-cur) + price * q) / (-next));
				}
			} else if (cur > 0 && next < 0) {
				entryPrices.set(sym, price);
				if (barIndex >= 0) entryBars.set(sym, barIndex);
			}
			trades++;
			fills.push({
				kind: cur > 0 && next >= 0 ? "flat" : "short",
				bar: barIndex,
				price: price,
				qty: q,
				pnl: pnl,
				symbol: sym
			});
			lastPrices.set(sym, price);
		}
	}

	function realizeToFlat(sym:String, price:Float, barIndex:Int):Void {
		var prior = positionOf(sym);
		if (prior == 0) return;
		if (prior > 0) {
			var pnl = prior * (price - entryOf(sym));
			if (pnl > 0) wins++;
			cash += prior * price;
			fills.push({ kind: "flat", bar: barIndex, price: price, qty: prior, pnl: pnl, symbol: sym });
		} else {
			var q = -prior;
			var pnl = q * (entryOf(sym) - price);
			if (pnl > 0) wins++;
			cash -= q * price;
			fills.push({ kind: "flat", bar: barIndex, price: price, qty: q, pnl: pnl, symbol: sym });
		}
		positions.set(sym, 0);
		entryBars.remove(sym);
		entryPrices.remove(sym);
		trades++;
		lastPrices.set(sym, price);
	}

	public function weightOf(sym:String, prices:Map<String, Float>):Float {
		var eq = equityAt(prices);
		if (!(eq > 0)) return 0.0;
		var px = resolvePrice(sym, prices);
		if (!(px > 0) || Math.isNaN(px)) return 0.0;
		return positionOf(sym) * px / eq;
	}

	public function equityAt(prices:Map<String, Float>):Float {
		var eq = cash;
		for (sym => qty in positions) {
			if (qty == 0) continue;
			var px = resolvePrice(sym, prices);
			eq += qty * px;
		}
		return eq;
	}

	public function unrealizedPnl(prices:Map<String, Float>):Float {
		var pnl = 0.0;
		for (sym => qty in positions) {
			if (qty == 0) continue;
			var px = resolvePrice(sym, prices);
			if (qty > 0) pnl += qty * (px - entryOf(sym));
			else pnl += (-qty) * (entryOf(sym) - px);
		}
		return pnl;
	}

	public function mark(prices:Map<String, Float>):Void {
		if (prices != null) {
			for (sym => px in prices) {
				if (px > 0 && !Math.isNaN(px)) lastPrices.set(sym, px);
			}
		}
		equity.push(equityAt(prices));
	}

	public function barsInTrade(sym:String, ?currentBar:Int = -1):Int {
		if (positionOf(sym) == 0 || !entryBars.exists(sym) || currentBar < 0) return 0;
		return currentBar - entryBars.get(sym);
	}
}

package musescript.harness;

import musescript.indicators.GrowableVec;

/**
 * Multi-symbol order book + shared cash. Companion to single-symbol `OrderSim`.
 * Strategies drive it via `buy`/`sell_all`/`rebalance_equal` / `target_weight`,
 * or via bags (`portfolio_apply` / `portfolio_add` / …) which call `applyBag`.
 *
 * Positions are signed: &gt;0 long, &lt;0 short. Equity = cash + Σ qty·price.
 */
class PortfolioSim {
	public var cash:Float;
	/** Round-trip-agnostic per-side trading cost in basis points of traded notional
	    (commission + spread/slippage proxy). Charged on every executed delta. 0 = frictionless. */
	public var tradingCostBps:Float = 0.0;
	public var positions:Map<String, Float>;
	public var entryPrices:Map<String, Float>;
	public var entryBars:Map<String, Int>;
	/** See `OrderSim.equity`'s doc comment -- `GrowableVec<Float>`, not `Array<Float>`. */
	public var equity:GrowableVec<Float>;
	public var trades:Int;
	public var wins:Int;
	public var fills:Array<Fill>;
	public var lastPrices:Map<String, Float>;

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

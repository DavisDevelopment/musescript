package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Output of `TdRiskLevel`: the latest buy- and sell-side protective stop
 * levels derived from the most-recently-completed setup in each direction.
 * Either field is NaN until the first setup in that direction completes.
 */
typedef TdRiskLevelOutput = {
	var buyRisk:Float;
	var sellRisk:Float;
}

/**
 * Tom DeMark TD Risk Level — ported from wickra-core's `TdRiskLevel`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_risk_level.rs).
 *
 * Protective-stop levels derived from setup extremes:
 * - Buy risk (stop for a long taken on a completed buy setup) is
 *   `low_extreme_bar.low - true_range(extreme bar)`.
 * - Sell risk (stop for a short taken on a completed sell setup) is
 *   `high_extreme_bar.high + true_range(extreme bar)`.
 * Levels are set the moment a setup completes and persist until the next
 * setup in that direction completes. The setup counting logic is inlined
 * here, mirroring the Rust source — no dependency on td_setup.
 */
class TdRiskLevel implements MuseIndicator<Bar, TdRiskLevelOutput> {
	var lookback:Int;
	var target:Int;
	var closes:Array<Float>;
	var prev:Null<Bar>;
	var buyCount:Int;
	var sellCount:Int;
	/** Extreme (lowest low) bar of the active buy-setup run: {price, trueRange}. */
	var buyExtreme:Null<{price:Float, trueRange:Float}>;
	/** Extreme (highest high) bar of the active sell-setup run. */
	var sellExtreme:Null<{price:Float, trueRange:Float}>;
	var buyRisk:Float;
	var sellRisk:Float;
	var ready:Bool;

	public function new(lookback:Int, target:Int) {
		if (lookback <= 0 || target <= 0) throw "TdRiskLevel: lookback and target must be > 0";
		this.lookback = lookback;
		this.target = target;
		reset();
	}

	/** DeMark's classic configuration: lookback = 4, target = 9. */
	public static function classic():TdRiskLevel return new TdRiskLevel(4, 9);

	/** Configured (lookback, target). */
	public function params():{lookback:Int, target:Int} return {lookback: lookback, target: target};

	static function trueRange(bar:Bar, prev:Null<Bar>):Float {
		var hl = bar.high - bar.low;
		if (prev != null) {
			var hc = Math.abs(bar.high - prev.close);
			var lc = Math.abs(bar.low - prev.close);
			return Math.max(hl, Math.max(hc, lc));
		}
		return hl;
	}

	public function update(bar:Bar):Null<TdRiskLevelOutput> {
		var tr = trueRange(bar, prev);
		if (closes.length > lookback) closes.shift();
		if (closes.length < lookback) {
			closes.push(bar.close);
			prev = bar;
			return null;
		}
		var reference = closes[0];
		closes.push(bar.close);

		if (bar.close < reference) {
			// Buy setup run.
			if (buyExtreme == null || !(buyExtreme.price <= bar.low)) {
				buyExtreme = {price: bar.low, trueRange: tr};
			}
			buyCount = buyCount + 1 > target ? target : buyCount + 1;
			sellCount = 0;
			sellExtreme = null;
			if (buyCount == target) {
				buyRisk = buyExtreme.price - buyExtreme.trueRange;
			}
		} else if (bar.close > reference) {
			// Sell setup run.
			if (sellExtreme == null || !(sellExtreme.price >= bar.high)) {
				sellExtreme = {price: bar.high, trueRange: tr};
			}
			sellCount = sellCount + 1 > target ? target : sellCount + 1;
			buyCount = 0;
			buyExtreme = null;
			if (sellCount == target) {
				sellRisk = sellExtreme.price + sellExtreme.trueRange;
			}
		} else {
			buyCount = 0;
			sellCount = 0;
			buyExtreme = null;
			sellExtreme = null;
		}

		prev = bar;
		ready = true;
		return {buyRisk: buyRisk, sellRisk: sellRisk};
	}

	public function reset():Void {
		closes = [];
		prev = null;
		buyCount = 0;
		sellCount = 0;
		buyExtreme = null;
		sellExtreme = null;
		buyRisk = Math.NaN;
		sellRisk = Math.NaN;
		ready = false;
	}

	public function warmupPeriod():Int return lookback + 1;
	public function isReady():Bool return ready;
	public function name():String return "TDRiskLevel";

	public static function spec():IndicatorSpec {
		return {
			name: "td_risk_level", args: [TWindow, TWindow], ret: TObject([
				{name: "buyRisk", ty: TScalar}, {name: "sellRisk", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var lookback = IndicatorCache.intArg(args, 0, 4);
				var target = IndicatorCache.intArg(args, 1, 9);
				return IndicatorCache.evalBar(h, "td_risk_level:" + lookback + ":" + target,
					{buyRisk: Math.NaN, sellRisk: Math.NaN},
					() -> new TdRiskLevel(lookback, target), (i, b) -> (cast i : TdRiskLevel).update(b));
			}
		};
	}
}

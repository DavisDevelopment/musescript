package musescript.ew.auction;

import musescript.harness.Bar;
import musescript.ew.EwForecastHost;
import musescript.ew.EwForecastHost.EwCountMass;
import musescript.ew.ForecastCloud;
import musescript.ew.ForecastCloud.ForecastCloudUtil;
import musescript.ew.auction.VolumeProfile.VolumeProfileLevels;

/**
 * Forecast host whose latent state is **fair value** from a volume-at-price
 * profile: POC + value-area high/low. Classifies the tape as **balance**
 * (price inside the value area) vs **discovery** (breakout above/below).
 *
 * Cloud mapping:
 * - `priceLo`/`priceHi` ← vaLow / vaHigh
 * - `priceMid` ← POC
 * - `spread` ← vaHigh − vaLow
 * - `probUp` ← soft P(discovery breakout up)
 *
 * Host-kind registration (`"auction"`) is intentionally left to the evo
 * wiring layer — this class is constructable via `new` / `withBars` only.
 */
class AuctionForecastHost implements EwForecastHost {
	public static inline var LABEL_BALANCE:String = "balance";
	public static inline var LABEL_DISCOVERY_UP:String = "discovery_up";
	public static inline var LABEL_DISCOVERY_DOWN:String = "discovery_down";

	var window:Int;
	var bins:Int;
	var valueAreaPct:Float;
	var horizon:Int;
	var key:Null<String>;
	var bars:Array<Bar>;
	var lastClose:Float;
	var lastLevels:Null<VolumeProfileLevels>;
	var lastRegime:String;
	var lastCloudAt:Int;
	var cachedCloud:Null<ForecastCloud>;
	var cachedCounts:Null<Array<EwCountMass>>;

	public function new(
		window:Int = VolumeProfile.DEFAULT_WINDOW,
		bins:Int = VolumeProfile.DEFAULT_BINS,
		valueAreaPct:Float = VolumeProfile.DEFAULT_VALUE_AREA_PCT,
		horizon:Int = 5,
		?phiKey:String
	) {
		this.window = window < 2 ? 2 : window;
		this.bins = bins < 2 ? 2 : bins;
		this.valueAreaPct = (valueAreaPct > 0 && valueAreaPct <= 1.0)
			? valueAreaPct
			: VolumeProfile.DEFAULT_VALUE_AREA_PCT;
		this.horizon = horizon < 1 ? 1 : horizon;
		this.key = phiKey;
		this.bars = [];
		this.lastClose = Math.NaN;
		this.lastLevels = null;
		this.lastRegime = LABEL_BALANCE;
		this.lastCloudAt = -1;
		this.cachedCloud = null;
		this.cachedCounts = null;
	}

	/** Batch factory: feed bars in order, then query `cloudAt` causally. */
	public static function withBars(
		bars:Array<Bar>,
		window:Int = VolumeProfile.DEFAULT_WINDOW,
		bins:Int = VolumeProfile.DEFAULT_BINS,
		valueAreaPct:Float = VolumeProfile.DEFAULT_VALUE_AREA_PCT,
		horizon:Int = 5,
		?phiKey:String
	):AuctionForecastHost {
		var h = new AuctionForecastHost(window, bins, valueAreaPct, horizon, phiKey);
		if (bars != null) {
			for (i in 0...bars.length) h.onBar(bars[i], i);
		}
		return h;
	}

	public inline function windowLen():Int return window;
	public inline function binCount():Int return bins;
	public inline function areaPct():Float return valueAreaPct;
	public inline function forecastHorizon():Int return horizon;
	public inline function lastRegimeLabel():String return lastRegime;
	public inline function lastProfile():Null<VolumeProfileLevels> return lastLevels;

	public function phiKey():Null<String> return key;

	public function onBar(bar:Bar, index:Int):Void {
		if (bar == null) return;
		if (index < 0) return;
		while (bars.length <= index) bars.push(null);
		bars[index] = bar;
		lastClose = bar.close;
		invalidateCache();
	}

	public function cloudAt(t:Int):ForecastCloud {
		ensureAt(t);
		return cachedCloud != null ? cachedCloud : ForecastCloudUtil.empty(horizon);
	}

	public function topCounts(t:Int, kMax:Int):Array<EwCountMass> {
		ensureAt(t);
		var all = cachedCounts != null ? cachedCounts : [];
		if (kMax < 1 || all.length <= kMax) return all.copy();
		return all.slice(0, kMax);
	}

	function ensureAt(t:Int):Void {
		if (lastCloudAt == t && cachedCloud != null) return;
		assemble(t);
	}

	function invalidateCache():Void {
		lastCloudAt = -1;
		cachedCloud = null;
		cachedCounts = null;
	}

	function assemble(t:Int):Void {
		lastCloudAt = t;
		if (t < 0 || t >= bars.length || bars[t] == null) {
			cachedCloud = ForecastCloudUtil.empty(horizon);
			cachedCounts = [];
			lastLevels = null;
			return;
		}
		// Need a full window of present bars ending at t.
		var start = t - window + 1;
		if (start < 0) {
			cachedCloud = ForecastCloudUtil.empty(horizon);
			cachedCounts = [];
			lastLevels = null;
			return;
		}
		for (i in start...(t + 1)) {
			if (bars[i] == null) {
				cachedCloud = ForecastCloudUtil.empty(horizon);
				cachedCounts = [];
				lastLevels = null;
				return;
			}
		}

		var levels = VolumeProfile.fromBars(bars, window, bins, valueAreaPct, t);
		lastLevels = levels;
		if (!Math.isFinite(levels.poc)) {
			cachedCloud = ForecastCloudUtil.empty(horizon);
			cachedCounts = [];
			return;
		}

		var close = bars[t].close;
		lastClose = close;
		var regime = classify(close, levels);
		lastRegime = regime;

		var spread = levels.vaHigh - levels.vaLow;
		if (!(spread >= 0)) spread = 0.0;

		var masses = softMasses(close, levels, regime);
		cachedCounts = [
			massOf(LABEL_BALANCE, masses.balance, levels, 0),
			massOf(LABEL_DISCOVERY_UP, masses.up, levels, 1),
			massOf(LABEL_DISCOVERY_DOWN, masses.down, levels, -1)
		];
		// Prefer current regime first for topCounts consumers.
		cachedCounts.sort(function(a, b) {
			if (a.mass > b.mass) return -1;
			if (a.mass < b.mass) return 1;
			return 0;
		});

		var atr = atrish(t);
		var inv = invalidateFor(regime, levels);
		var dist = Math.NaN;
		if (Math.isFinite(inv) && Math.isFinite(close)) {
			var scale = atr > 0 ? atr : Math.max(1e-12, Math.abs(close) * 0.01);
			dist = Math.abs(close - inv) / scale;
		}

		var pref = cachedCounts.length > 0 ? cachedCounts[0] : null;
		cachedCloud = {
			horizon: horizon,
			priceLo: levels.vaLow,
			priceHi: levels.vaHigh,
			barLo: t,
			barHi: t + horizon,
			priceMid: levels.poc,
			spread: spread,
			probUp: masses.up,
			topMass: pref != null ? pref.mass : 1.0,
			countEntropy: entropy3(masses.balance, masses.up, masses.down),
			invalidatePrice: inv,
			distToInvalidation: dist,
			nestScore: regime == LABEL_BALANCE ? 1.0 : 0.85,
			labelCode: labelCodeOf(regime),
			samples: 1
		};
	}

	/** Balance if close inside [vaLow, vaHigh]; else discovery direction. */
	public static function classify(close:Float, levels:VolumeProfileLevels):String {
		if (!Math.isFinite(close) || !Math.isFinite(levels.vaLow) || !Math.isFinite(levels.vaHigh))
			return LABEL_BALANCE;
		if (close > levels.vaHigh) return LABEL_DISCOVERY_UP;
		if (close < levels.vaLow) return LABEL_DISCOVERY_DOWN;
		return LABEL_BALANCE;
	}

	/**
	 * Soft P(discovery breakout up). Uses close position relative to the value
	 * area plus a light POC-distance tilt — no RNG.
	 */
	static function softMasses(
		close:Float, levels:VolumeProfileLevels, regime:String
	):{balance:Float, up:Float, down:Float} {
		var width = levels.vaHigh - levels.vaLow;
		if (!(width > 0) || !Math.isFinite(close)) {
			return switch (regime) {
				case LABEL_DISCOVERY_UP: {balance: 0.15, up: 0.70, down: 0.15};
				case LABEL_DISCOVERY_DOWN: {balance: 0.15, up: 0.15, down: 0.70};
				default: {balance: 0.70, up: 0.15, down: 0.15};
			};
		}

		// Position: 0 at vaLow, 1 at vaHigh; can exceed [0,1] on breakout.
		var pos = (close - levels.vaLow) / width;
		var escapeUp = pos - 1.0; // >0 outside above
		var escapeDown = 0.0 - pos; // >0 outside below

		var up = 0.0;
		var down = 0.0;
		var balance = 0.0;

		if (regime == LABEL_DISCOVERY_UP) {
			up = 0.55 + 0.35 * clamp01(escapeUp / 0.5);
			balance = 0.25 * (1.0 - clamp01(escapeUp / 0.5));
			down = 1.0 - up - balance;
		} else if (regime == LABEL_DISCOVERY_DOWN) {
			down = 0.55 + 0.35 * clamp01(escapeDown / 0.5);
			balance = 0.25 * (1.0 - clamp01(escapeDown / 0.5));
			up = 1.0 - down - balance;
		} else {
			// Inside VA: balance dominates; tilt by proximity to edges + POC side.
			var edgePressure = Math.abs(pos - 0.5) * 2.0; // 0 mid → 1 at edge
			balance = 0.55 + 0.30 * (1.0 - edgePressure);
			var pocSide = close >= levels.poc ? 1.0 : -1.0;
			var lean = 0.15 + 0.20 * edgePressure;
			if (pocSide > 0) {
				up = lean;
				down = 1.0 - balance - up;
			} else {
				down = lean;
				up = 1.0 - balance - down;
			}
		}

		// Normalize defensively.
		var s = balance + up + down;
		if (!(s > 0)) return {balance: 1.0 / 3, up: 1.0 / 3, down: 1.0 / 3};
		return {balance: balance / s, up: up / s, down: down / s};
	}

	static function massOf(
		label:String, mass:Float, levels:VolumeProfileLevels, dir:Int
	):EwCountMass {
		var inv = if (dir > 0) levels.vaHigh
			else if (dir < 0) levels.vaLow
			else levels.poc;
		return {
			label: label,
			mass: mass,
			score: mass,
			invalidatePrice: inv,
			nestScore: label == LABEL_BALANCE ? 1.0 : 0.85,
			degree: 0
		};
	}

	static function invalidateFor(regime:String, levels:VolumeProfileLevels):Float {
		return switch (regime) {
			case LABEL_DISCOVERY_UP: levels.vaHigh;
			case LABEL_DISCOVERY_DOWN: levels.vaLow;
			default: levels.poc;
		};
	}

	static function entropy3(a:Float, b:Float, c:Float):Float {
		var ent = 0.0;
		inline function add(m:Float) {
			if (m > 0) ent -= m * Math.log(m);
		}
		add(a);
		add(b);
		add(c);
		return ent;
	}

	static inline function clamp01(x:Float):Float {
		if (x < 0) return 0.0;
		if (x > 1) return 1.0;
		return x;
	}

	function atrish(t:Int):Float {
		var n = 0;
		var sum = 0.0;
		var look = window < 14 ? window : 14;
		var from = t - look + 1;
		if (from < 1) from = 1;
		for (i in from...(t + 1)) {
			var cur = bars[i];
			var prev = bars[i - 1];
			if (cur == null || prev == null) continue;
			var a = cur.high - cur.low;
			var b = Math.abs(cur.high - prev.close);
			var c = Math.abs(cur.low - prev.close);
			var tr = a > b ? a : b;
			if (c > tr) tr = c;
			sum += tr;
			n++;
		}
		return n > 0 ? sum / n : Math.NaN;
	}

	public static function labelCodeOf(label:String):Float {
		return switch (label) {
			case LABEL_BALANCE: 1.0;
			case LABEL_DISCOVERY_UP: 2.0;
			case LABEL_DISCOVERY_DOWN: 3.0;
			default: 0.0;
		};
	}
}

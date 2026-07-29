package musescript.ew;

import haxe.Int64;
import haxe.io.FPHelper;
import musescript.harness.Bar;
import musescript.ew.mcmc.DetRng;
import musescript.ew.mcmc.DetMath;
import musescript.ew.auction.AuctionForecastHost;
import musescript.indicators.geom.SwingGraphStack;

/**
 * Cross-target parity proof for forecast hosts (Initiative 2.1 accept criterion):
 * same seed+bars → same cloud bits on JVM vs node/JS.
 *
 * Prints RAW IEEE-754 bit patterns (never decimals). Compiled to BOTH node and JVM
 * and diffed by `tools/forecast_host_parity_ci.*`. Also locked by utest golden
 * `testdata/forecast-host-parity.golden.txt`.
 *
 * Coverage this pass:
 *   - RegimeForecastHost (DetRng/DetMath MH chain) — primary
 *   - AuctionForecastHost (pure IEEE volume profile) — included (cheap + overlay-ready)
 *   - LatticeForecastHost via SwingGraphStack on a synthetic impulse — included
 */
class ForecastHostParityDump {
	static function main() {
		Sys.print(render());
	}

	public static function render():String {
		var buf = new StringBuf();
		var bars = synthBars();

		buf.add("-- RegimeForecastHost cloud (raw f64 bits) --\n");
		// Small sampler budget: CI-fast but still exercises DetRng/DetMath MH path.
		var regime = new RegimeForecastHost(7, 2, 10, 80, 300, 100, 40, 0.97);
		for (i in 0...bars.length) regime.onBar(bars[i], i);
		for (t in [40, 79]) dumpCloud(buf, "regime", t, regime.cloudAt(t));
		var rCounts = regime.topCounts(79, 2);
		for (c in rCounts)
			buf.add("regime.mass." + c.label + "=" + fbits(c.mass) + "\n");

		buf.add("-- AuctionForecastHost cloud (raw f64 bits) --\n");
		var auction = new AuctionForecastHost(20, 50, 0.70, 5);
		for (i in 0...bars.length) auction.onBar(bars[i], i);
		dumpCloud(buf, "auction", 79, auction.cloudAt(79));
		var levels = auction.lastProfile();
		if (levels != null) {
			buf.add("auction.poc=" + fbits(levels.poc) + "\n");
			buf.add("auction.vaHigh=" + fbits(levels.vaHigh) + "\n");
			buf.add("auction.vaLow=" + fbits(levels.vaLow) + "\n");
		}
		buf.add("auction.regime=" + auction.lastRegimeLabel() + "\n");

		buf.add("-- LatticeForecastHost cloud (raw f64 bits) --\n");
		var impulse = impulseBars();
		var stack = new SwingGraphStack(0.03);
		var lattice = LatticeForecastHost.withStack(stack, null, 5);
		for (i in 0...impulse.length) lattice.onBar(impulse[i], i);
		var lt = impulse.length - 1;
		dumpCloud(buf, "lattice", lt, lattice.cloudAt(lt));
		var lCounts = lattice.topCounts(lt, 3);
		buf.add("lattice.nCounts=" + lCounts.length + "\n");
		for (i in 0...lCounts.length) {
			var c = lCounts[i];
			buf.add("lattice[" + i + "].label=" + c.label + "\n");
			buf.add("lattice[" + i + "].mass=" + fbits(c.mass) + "\n");
			buf.add("lattice[" + i + "].inv=" + fbits(c.invalidatePrice) + "\n");
		}

		return buf.toString();
	}

	/** Calm→volatile synthetic closes (DetRng + DetMath.exp) with volume — shared tape. */
	static function synthBars():Array<Bar> {
		var rng = new DetRng(Int64.make(0x11, 0x22));
		var px = 100.0;
		var out:Array<Bar> = [];
		for (i in 0...80) {
			if (i > 0) {
				var sig = i < 40 ? 0.004 : 0.02;
				// DetMath.exp — native Math.exp is NOT byte-identical across JVM/JS.
				px *= DetMath.exp(sig * rng.nextGaussian());
			}
			var vol = 1000.0 + 50.0 * (i % 7);
			out.push({
				open: px, high: px * 1.002, low: px * 0.998, close: px,
				volume: vol, time: i, index: i
			});
		}
		return out;
	}

	/** Piecewise-linear impulse tape (exact rationals — no libm) for lattice pivots. */
	static function impulseBars():Array<Bar> {
		var bars = [0, 10, 20, 30, 40, 50];
		var pxs = [100.0, 110.0, 105.0, 120.0, 112.0, 125.0];
		var out:Array<Bar> = [];
		var li = 0;
		for (i in 0...51) {
			while (li + 1 < bars.length && bars[li + 1] <= i) li++;
			var aBar = bars[li];
			var aPx = pxs[li];
			var bBar = li + 1 < bars.length ? bars[li + 1] : aBar;
			var bPx = li + 1 < pxs.length ? pxs[li + 1] : aPx;
			var span = bBar - aBar;
			var t = span > 0 ? (i - aBar) / (span + 0.0) : 0.0;
			var px = aPx + (bPx - aPx) * t;
			out.push({
				open: px, high: px * 1.001, low: px * 0.999, close: px,
				volume: 1000, time: i, index: i
			});
		}
		return out;
	}

	static function dumpCloud(buf:StringBuf, tag:String, t:Int, c:ForecastCloud):Void {
		buf.add(tag + ".t" + t + ".priceLo=" + fbits(c.priceLo) + "\n");
		buf.add(tag + ".t" + t + ".priceHi=" + fbits(c.priceHi) + "\n");
		buf.add(tag + ".t" + t + ".priceMid=" + fbits(c.priceMid) + "\n");
		buf.add(tag + ".t" + t + ".spread=" + fbits(c.spread) + "\n");
		buf.add(tag + ".t" + t + ".probUp=" + fbits(c.probUp) + "\n");
		buf.add(tag + ".t" + t + ".topMass=" + fbits(c.topMass) + "\n");
		buf.add(tag + ".t" + t + ".entropy=" + fbits(c.countEntropy) + "\n");
		buf.add(tag + ".t" + t + ".invalidate=" + fbits(c.invalidatePrice) + "\n");
		buf.add(tag + ".t" + t + ".labelCode=" + fbits(c.labelCode) + "\n");
		buf.add(tag + ".t" + t + ".samples=" + c.samples + "\n");
	}

	static function fbits(f:Float):String {
		var b = FPHelper.doubleToI64(f);
		return StringTools.hex(b.high, 8) + StringTools.hex(b.low, 8);
	}
}

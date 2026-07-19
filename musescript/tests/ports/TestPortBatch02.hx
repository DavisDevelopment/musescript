package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.harness.Bar;
import musescript.indicators.lib.*;
import musescript.indicators.prim.*;
import musescript.indicators.IndicatorBatch;

class TestPortBatch02 extends Test {
	// ====== ABCD ======
	function testAbcdBullishPattern():Void {
		// From Rust: AB=40 down, BC=24.7 up (0.618), CD=40 down → AB = CD (bullish).
		var abcd = new Abcd();
		var pivots = [140.0, 100.0, 124.7, 84.7];
		var candles = candlesForPivots(pivots);
		var last:Null<Float> = null;
		for (c in candles) {
			last = abcd.update(c);
		}
		Assert.equals(1.0, last);
	}

	function testAbcdBatchEqualsStreaming():Void {
		var candles = candlesForPivots([140.0, 100.0, 124.7, 84.7]);
		var a = new Abcd();
		var b = new Abcd();
		var batch = IndicatorBatch.run(a, candles);
		var streamed = [];
		for (x in candles) {
			streamed.push(b.update(x));
		}
		Assert.same(batch, streamed);
	}

	// ====== AdaptiveCycle ======
	function testAdaptiveCycleWarmupPeriod():Void {
		var ac = new AdaptiveCycle();
		Assert.equals(50, ac.warmupPeriod());
		Assert.equals("AdaptiveCycle", ac.name());
		Assert.isFalse(ac.isReady());
	}

	function testAdaptiveCycleOutputInBand():Void {
		var ac = new AdaptiveCycle();
		var prices:Array<Float> = [];
		for (i in 0...200) {
			prices.push(100.0 + Math.sin(i * 0.5) * 5.0);
		}
		var out = [];
		for (p in prices) {
			out.push(ac.update(p));
		}
		for (v in out) {
			if (v != null) {
				Assert.isTrue(v >= 3.0 && v <= 25.0, 'period $v out of [3,25]');
				var rounded = Math.round(v);
				Assert.equals(rounded, v, 'period $v not integer-valued');
			}
		}
	}

	function testAdaptiveCycleBatchEqualsStreaming():Void {
		var prices:Array<Float> = [];
		for (i in 0...200) {
			prices.push(100.0 + Math.sin(i * 0.3) * 5.0);
		}
		var a = new AdaptiveCycle();
		var b = new AdaptiveCycle();
		var batch = IndicatorBatch.run(a, prices);
		var streamed = [];
		for (p in prices) {
			streamed.push(b.update(p));
		}
		Assert.same(batch, streamed);
	}

	// ====== AdaptiveLaguerreFilter ======
	function testAdaptiveLaguerreFilterWarmup():Void {
		var alf = new AdaptiveLaguerreFilter(5);
		Assert.equals(5, alf.warmupPeriod());
		Assert.equals("AdaptiveLaguerre", alf.name());
		// The Laguerre cascade is a recursive filter, not a windowed one: it emits
		// a finite value from the very first bar (the error-normalization window
		// backing gamma just gets a partial diffs buffer until `period` bars in).
		Assert.notNull(alf.update(10.0));
		Assert.notNull(alf.update(11.0));
		Assert.notNull(alf.update(12.0));
		Assert.isFalse(alf.isReady()); // fewer than `period` diffs collected so far
	}

	function testAdaptiveLaguerreFilterConstantSeries():Void {
		var alf = new AdaptiveLaguerreFilter(5);
		var out = [];
		for (i in 0...40) {
			out.push(alf.update(42.0));
		}
		// After warmup, should converge to constant.
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.isTrue(Math.abs(last - 42.0) < 1e-8);
	}

	function testAdaptiveLaguerreFilterBatchEqualsStreaming():Void {
		var prices:Array<Float> = [];
		for (i in 1...51) {
			prices.push(i * 0.7);
		}
		var a = new AdaptiveLaguerreFilter(7);
		var b = new AdaptiveLaguerreFilter(7);
		var batch = IndicatorBatch.run(a, prices);
		var streamed = [];
		for (p in prices) {
			streamed.push(b.update(p));
		}
		Assert.same(batch, streamed);
	}

	// ====== AdaptiveRsi ======
	function testAdaptiveRsiFirstEmissionAtWarmup():Void {
		var r = new AdaptiveRsi(4);
		var prices = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0];
		var out = [];
		for (p in prices) {
			out.push(r.update(p));
		}
		// First 4 should be null.
		for (i in 0...4) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[4]);
	}

	function testAdaptiveRsiPureUptrendIsMax():Void {
		var r = new AdaptiveRsi(5);
		var prices:Array<Float> = [];
		for (i in 1...41) {
			prices.push(i * 1.0);
		}
		var out = IndicatorBatch.run(r, prices);
		var last = null;
		for (v in out) {
			if (v != null) last = v;
		}
		Assert.notNull(last);
		Assert.isTrue(Math.abs(last - 100.0) < 1e-8);
	}

	function testAdaptiveRsiBatchEqualsStreaming():Void {
		var prices:Array<Float> = [];
		for (i in 0...120) {
			prices.push(100.0 + Math.sin(i * 0.25) * 9.0);
		}
		var a = new AdaptiveRsi(14);
		var b = new AdaptiveRsi(14);
		var batch = IndicatorBatch.run(a, prices);
		var streamed = [];
		for (p in prices) {
			streamed.push(b.update(p));
		}
		Assert.same(batch, streamed);
	}

	// ====== ADX ======
	function testAdxPureUptrendPlusDiDominant():Void {
		var adx = new Adx(14);
		var candles:Array<Bar> = [];
		for (i in 0...50) {
			var base = 100.0 + i * 2.0;
			candles.push(bar(base + 1.0, base - 0.5, base + 0.5));
		}
		var last = null;
		for (c in candles) {
			var out = adx.update(c);
			if (out != null) last = out;
		}
		Assert.notNull(last);
		Assert.isTrue(last.plusDi > last.minusDi);
		Assert.isTrue(last.adx > 0.0);
	}

	function testAdxZeroTrueRangeYieldsZero():Void {
		var adx = new Adx(5);
		var candles:Array<Bar> = [];
		for (i in 0...30) {
			candles.push(bar(10.0, 10.0, 10.0));
		}
		var last = null;
		for (c in candles) {
			var out = adx.update(c);
			if (out != null) last = out;
		}
		Assert.notNull(last);
		Assert.equals(0.0, last.plusDi);
		Assert.equals(0.0, last.minusDi);
		Assert.equals(0.0, last.adx);
	}

	function testAdxBatchEqualsStreaming():Void {
		var candles:Array<Bar> = [];
		for (i in 0...60) {
			var base = 100.0 + Math.sin(i * 0.3) * 5.0;
			candles.push(bar(base + 1.0, base - 1.0, base));
		}
		var a = new Adx(14);
		var b = new Adx(14);
		var batch = IndicatorBatch.run(a, candles);
		var streamed = [];
		for (c in candles) {
			streamed.push(b.update(c));
		}
		Assert.same(batch, streamed);
	}

	// ====== ADXR ======
	function testAdxrPureUptrendFinite():Void {
		var adxr = new Adxr(14);
		var candles:Array<Bar> = [];
		for (i in 0...80) {
			var base = 100.0 + i * 2.0;
			candles.push(bar(base + 1.0, base - 0.5, base + 0.5));
		}
		var last = null;
		for (c in candles) {
			var out = adxr.update(c);
			if (out != null) last = out;
		}
		Assert.notNull(last);
		Assert.isTrue(last > 0.0 && last <= 100.0 + 1e-9);
	}

	function testAdxrFirstEmissionAtWarmup():Void {
		var adxr = new Adxr(5);
		var candles:Array<Bar> = [];
		for (i in 0...80) {
			var p = 100.0 + Math.sin(i * 0.3) * 5.0;
			candles.push(bar(p + 1.0, p - 1.0, p));
		}
		var out = IndicatorBatch.run(adxr, candles);
		var warmup = 3 * 5 - 1; // 14
		for (i in 0...warmup - 1) {
			Assert.isNull(out[i]);
		}
		Assert.notNull(out[warmup - 1]);
	}

	function testAdxrBatchEqualsStreaming():Void {
		var candles:Array<Bar> = [];
		for (i in 0...60) {
			var p = 100.0 + Math.sin(i * 0.25) * 5.0;
			candles.push(bar(p + 1.0, p - 1.0, p));
		}
		var a = new Adxr(7);
		var b = new Adxr(7);
		var batch = IndicatorBatch.run(a, candles);
		var streamed = [];
		for (c in candles) {
			streamed.push(b.update(c));
		}
		Assert.same(batch, streamed);
	}

	// ====== Alligator ======
	function testAlligatorConstantSeriesYieldsConstant():Void {
		var alligator = Alligator.classic();
		var candles:Array<Bar> = [];
		for (i in 0...40) {
			candles.push(bar(11.0, 9.0));
		}
		var out = IndicatorBatch.run(alligator, candles);
		for (i in 12...out.length) {
			var v = out[i];
			Assert.notNull(v);
			Assert.isTrue(Math.abs(v.jaw - 10.0) < 1e-10);
			Assert.isTrue(Math.abs(v.teeth - 10.0) < 1e-10);
			Assert.isTrue(Math.abs(v.lips - 10.0) < 1e-10);
		}
	}

	function testAlligatorUptrendOrdering():Void {
		var alligator = Alligator.classic();
		var candles:Array<Bar> = [];
		for (i in 0...80) {
			candles.push(bar(10.0 + i, 9.0 + i));
		}
		var out = IndicatorBatch.run(alligator, candles);
		var last = out[out.length - 1];
		Assert.notNull(last);
		Assert.isTrue(last.lips > last.teeth);
		Assert.isTrue(last.teeth > last.jaw);
	}

	function testAlligatorBatchEqualsStreaming():Void {
		var candles:Array<Bar> = [];
		for (i in 0...80) {
			var base = 100.0 + Math.sin(i * 0.2) * 5.0;
			candles.push(bar(base + 1.0, base - 1.0));
		}
		var a = Alligator.classic();
		var b = Alligator.classic();
		var batch = IndicatorBatch.run(a, candles);
		var streamed = [];
		for (c in candles) {
			streamed.push(b.update(c));
		}
		Assert.same(batch, streamed);
	}

	// ====== ALMA ======
	function testAlmaConstantSeriesYieldsConstant():Void {
		var alma = Alma.classic();
		var prices:Array<Float> = [];
		for (i in 0...40) {
			prices.push(42.0);
		}
		var out = IndicatorBatch.run(alma, prices);
		for (i in 8...out.length) {
			var v = out[i];
			Assert.notNull(v);
			Assert.isTrue(Math.abs(v - 42.0) < 1e-10);
		}
	}

	function testAlmaOffsetZeroLowerThanMean():Void {
		var alma = new Alma(5, 0.0, 6.0);
		var series:Array<Float> = [];
		for (i in 1...6) {
			series.push(i * 1.0);
		}
		var last = null;
		for (p in series) {
			last = alma.update(p);
		}
		Assert.notNull(last);
		var mean = 15.0 / 5.0; // 3.0
		Assert.isTrue(last < mean, '$last should be < $mean');
	}

	function testAlmaBatchEqualsStreaming():Void {
		var prices:Array<Float> = [];
		for (i in 1...101) {
			prices.push(Math.sin(i * 0.2) * 5.0 + i * 0.1);
		}
		var a = Alma.classic();
		var b = Alma.classic();
		var batch = IndicatorBatch.run(a, prices);
		var streamed = [];
		for (p in prices) {
			streamed.push(b.update(p));
		}
		Assert.same(batch, streamed);
	}

	// ====== Helpers ======

	static var barCounter:Int = 0;

	static function bar(high:Float, low:Float, ?close:Float):Bar {
		if (close == null) close = low;
		var idx = barCounter++;
		return {
			open: close,
			high: high,
			low: low,
			close: close,
			volume: 1.0,
			time: (idx : Float),
			index: idx
		};
	}

	static function candlesForPivots(pivots:Array<Float>):Array<Bar> {
		var out:Array<Bar> = [];
		out.push(bar(pivots[0], pivots[0] * 0.999));
		for (k in 0...pivots.length) {
			var price = pivots[k];
			var isHigh = k % 2 == 0;
			var next = k + 1 < pivots.length ? pivots[k + 1] : (isHigh ? price * 0.90 : price * 1.10);
			if (isHigh) {
				out.push(bar(price * 0.99, next));
			} else {
				out.push(bar(next, price * 1.01));
			}
		}
		return out;
	}
}

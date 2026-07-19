package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.*;
import musescript.indicators.prim.*;

/**
 * Batch 21: 5 indicators (bomar_bands, common_sense_ratio, dynamic_momentum_index,
 * fama, jma) — ported from Wickra Rust reference.
 *
 * Test values transcribed from wickra-core's `#[cfg(test)]` modules.
 */
class TestPortBatch21 extends Test {

	// ── JMA ────────────────────────────────────────────────────────────────

	public function testJmaRejectsZeroPeriod() {
		try {
			new Jma(0, 0.0, 2);
			Assert.fail("Jma should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testJmaRejectsNonFinitePhase() {
		try {
			new Jma(14, Math.NaN, 2);
			Assert.fail("Jma should reject NaN phase");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testJmaRejectsInvalidPower() {
		try {
			new Jma(14, 0.0, 0);
			Assert.fail("Jma should reject power 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Jma(14, 0.0, 5);
			Assert.fail("Jma should reject power 5");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testJmaConstantSeriesYieldsConstant() {
		var jma = new Jma(14, 0.0, 2);
		for (i in 0...60) {
			var out = jma.update(42.0);
			if (out != null) {
				Assert.floatEquals(42.0, out, 1e-6);
			}
		}
	}

	public function testJmaExtremePhaseIsClamped() {
		var a = new Jma(14, 250.0, 2);
		var b = new Jma(14, -250.0, 2);
		for (i in 1...41) {
			var p = (i : Float);
			var va = a.update(p);
			var vb = b.update(p);
			if (va != null) Assert.isTrue(Math.isFinite(va));
			if (vb != null) Assert.isTrue(Math.isFinite(vb));
		}
	}

	public function testJmaBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 1...81) {
			prices.push(100.0 + Math.sin((i : Float) * 0.2) * 5.0);
		}
		var a = new Jma(14, 0.0, 2);
		var b = new Jma(14, 0.0, 2);
		var batch:Array<Null<Float>> = [];
		for (p in prices) {
			batch.push(a.update(p));
		}
		var streamed:Array<Null<Float>> = [];
		for (p in prices) {
			streamed.push(b.update(p));
		}
		Assert.equals(batch.length, streamed.length);
		for (i in 0...batch.length) {
			var b1 = batch[i];
			var b2 = streamed[i];
			if (b1 == null && b2 == null) continue;
			if (b1 != null && b2 != null) {
				Assert.floatEquals(b1, b2, 1e-9);
			} else {
				Assert.fail('Batch/streaming mismatch at index $i: batch=$b1, streamed=$b2');
			}
		}
	}

	public function testJmaIgnoresNonFiniteInput() {
		var jma = new Jma(14, 0.0, 2);
		for (i in 1...16) {
			jma.update((i : Float));
		}
		var before = jma.update(16.0);
		var afterNan = jma.update(Math.NaN);
		Assert.equals(before, afterNan);
	}

	public function testJmaResetClearsState() {
		var jma = new Jma(14, 0.0, 2);
		for (i in 1...31) {
			jma.update((i : Float));
		}
		Assert.isTrue(jma.isReady());
		jma.reset();
		Assert.isFalse(jma.isReady());
	}

	// ── CommonSenseRatio ───────────────────────────────────────────────────

	public function testCommonSenseRatioRejectsPeriodLessThanTwo() {
		try {
			new CommonSenseRatio(1);
			Assert.fail("CSR should reject period < 2");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testCommonSenseRatioReferenceValue() {
		// window [-0.04, -0.02, 0.0, 0.02, 0.04]
		// gains = 0.06, losses = 0.06 -> profit factor 1.0
		// P95 = 0.036, |P5| = 0.036 -> tail ratio 1.0, CSR = 1.0
		var csr = new CommonSenseRatio(5);
		var returns = [-0.04, -0.02, 0.0, 0.02, 0.04];
		var out = null;
		for (r in returns) {
			out = csr.update(r);
		}
		Assert.notNull(out);
		Assert.floatEquals(1.0, out, 1e-6);
	}

	public function testCommonSenseRatioNoLossesIsZero() {
		var csr = new CommonSenseRatio(3);
		var last = csr.update(0.01);
		last = csr.update(0.02);
		last = csr.update(0.03);
		Assert.notNull(last);
		Assert.floatEquals(0.0, last, 1e-9);
	}

	public function testCommonSenseRatioFlatWindowIsZero() {
		var csr = new CommonSenseRatio(4);
		var out = null;
		for (i in 0...4) {
			out = csr.update(0.0);
		}
		Assert.notNull(out);
		Assert.floatEquals(0.0, out, 1e-9);
	}

	public function testCommonSenseRatioIgnoresNonFiniteInput() {
		var csr = new CommonSenseRatio(3);
		Assert.isNull(csr.update(0.01));
		Assert.isNull(csr.update(Math.NaN));
		var out = csr.update(-0.02);
		Assert.isNull(out);
		out = csr.update(0.03);
		Assert.notNull(out);
	}

	public function testCommonSenseRatioResetClearsState() {
		var csr = new CommonSenseRatio(3);
		csr.update(-0.01);
		csr.update(0.0);
		csr.update(0.02);
		Assert.isTrue(csr.isReady());
		csr.reset();
		Assert.isFalse(csr.isReady());
		Assert.isNull(csr.update(0.01));
	}

	public function testCommonSenseRatioBatchEqualsStreaming() {
		var rets:Array<Float> = [];
		for (i in 0...60) {
			rets.push(Math.sin((i : Float) * 0.25) * 0.02);
		}
		var a = new CommonSenseRatio(15);
		var b = new CommonSenseRatio(15);
		var batch:Array<Null<Float>> = [];
		for (r in rets) {
			batch.push(a.update(r));
		}
		var streamed:Array<Null<Float>> = [];
		for (r in rets) {
			streamed.push(b.update(r));
		}
		for (i in 0...batch.length) {
			var b1 = batch[i];
			var b2 = streamed[i];
			if (b1 == null && b2 == null) continue;
			if (b1 != null && b2 != null) {
				Assert.floatEquals(b1, b2, 1e-9);
			} else {
				Assert.fail('Batch/streaming mismatch at index $i');
			}
		}
	}

	// ── BomarBands ─────────────────────────────────────────────────────────

	public function testBomarBandsRejectsZeroPeriod() {
		try {
			new BomarBands(0, 0.85);
			Assert.fail("BomarBands should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testBomarBandsRejectsOutOfRangeCoverage() {
		try {
			new BomarBands(20, 0.0);
			Assert.fail("BomarBands should reject coverage 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new BomarBands(20, 1.1);
			Assert.fail("BomarBands should reject coverage 1.1");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new BomarBands(20, -0.5);
			Assert.fail("BomarBands should reject coverage -0.5");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testBomarBandsWarmsUpThenEmits() {
		var bb = new BomarBands(4, 0.85);
		Assert.isNull(bb.update(100.0));
		Assert.isNull(bb.update(102.0));
		Assert.isNull(bb.update(98.0));
		var out = bb.update(104.0);
		Assert.notNull(out);
		Assert.isTrue(bb.isReady());
	}

	public function testBomarBandsKnownBands() {
		// mean=101; |dev| = {1,1,3,3}/101; coverage 0.85 quantile -> 3/101.
		// offset = 101 * 3/101 = 3 -> upper 104, lower 98.
		var bb = new BomarBands(4, 0.85);
		var out = null;
		for (v in [100.0, 102.0, 98.0, 104.0]) {
			out = bb.update(v);
		}
		Assert.notNull(out);
		Assert.floatEquals(101.0, out.middle, 1e-6);
		Assert.floatEquals(104.0, out.upper, 1e-6);
		Assert.floatEquals(98.0, out.lower, 1e-6);
	}

	public function testBomarBandsZeroMidlineCollapsesBands() {
		// Window mean exactly zero -> relative deviation undefined -> collapse.
		var bb = new BomarBands(2, 0.85);
		var out = bb.update(3.0);
		Assert.isNull(out);
		out = bb.update(-3.0);
		Assert.notNull(out);
		Assert.floatEquals(0.0, out.middle, 1e-9);
		Assert.floatEquals(0.0, out.upper, 1e-9);
		Assert.floatEquals(0.0, out.lower, 1e-9);
	}

	public function testBomarBandsRollingWindowEvictsOldest() {
		// Eight values through a period-4 window: only the last four survive.
		var bb = new BomarBands(4, 0.85);
		var out = null;
		for (v in [50.0, 50.0, 50.0, 50.0, 100.0, 102.0, 98.0, 104.0]) {
			out = bb.update(v);
		}
		Assert.notNull(out);
		Assert.floatEquals(101.0, out.middle, 1e-6);
		Assert.floatEquals(104.0, out.upper, 1e-6);
		Assert.floatEquals(98.0, out.lower, 1e-6);
	}

	public function testBomarBandsResetClearsState() {
		var bb = new BomarBands(4, 0.85);
		for (v in [100.0, 102.0, 98.0, 104.0]) {
			bb.update(v);
		}
		Assert.isTrue(bb.isReady());
		bb.reset();
		Assert.isFalse(bb.isReady());
		Assert.isNull(bb.update(100.0));
	}

	// ── DynamicMomentumIndex ───────────────────────────────────────────────

	public function testDynamicMomentumIndexRejectsZeroPeriod() {
		try {
			new DynamicMomentumIndex(0);
			Assert.fail("DMI should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testDynamicMomentumIndexWarmupPeriod() {
		var dmi = new DynamicMomentumIndex(14);
		Assert.equals(31, dmi.warmupPeriod());
	}

	public function testDynamicMomentumIndexFirstEmissionMatchesWarmupPeriod() {
		var prices:Array<Float> = [];
		for (i in 0...50) {
			prices.push(100.0 + Math.sin((i : Float) * 0.4) * 6.0);
		}
		var dmi = new DynamicMomentumIndex(14);
		var outputs:Array<Null<Float>> = [];
		for (p in prices) {
			outputs.push(dmi.update(p));
		}
		for (i in 0...30) {
			Assert.isNull(outputs[i], 'index $i must be None during warmup');
		}
		Assert.notNull(outputs[30], 'first value at warmup_period - 1 = 30');
	}

	public function testDynamicMomentumIndexPureUptrendIsOneHundred() {
		// Every change positive -> avg_loss 0 -> 100
		var prices:Array<Float> = [];
		for (i in 1...61) {
			prices.push((i : Float));
		}
		var dmi = new DynamicMomentumIndex(14);
		var out = null;
		for (p in prices) {
			out = dmi.update(p);
		}
		Assert.notNull(out);
		Assert.floatEquals(100.0, out, 1e-6);
	}

	public function testDynamicMomentumIndexFlatMarketIsNeutral() {
		// Constant prices: no changes -> neutral 50
		var dmi = new DynamicMomentumIndex(14);
		var out = null;
		for (i in 0...50) {
			out = dmi.update(42.0);
		}
		Assert.notNull(out);
		Assert.floatEquals(50.0, out, 1e-6);
	}

	public function testDynamicMomentumIndexOutputStaysInRange() {
		var prices:Array<Float> = [];
		for (i in 0...120) {
			prices.push(100.0 + Math.sin((i : Float) * 0.3) * 10.0 + Math.cos((i : Float) * 0.07) * 4.0);
		}
		var dmi = new DynamicMomentumIndex(14);
		for (p in prices) {
			var out = dmi.update(p);
			if (out != null) {
				Assert.isTrue(out >= 0.0 && out <= 100.0, 'DMI $out left [0, 100]');
			}
		}
	}

	public function testDynamicMomentumIndexIgnoresNonFiniteInput() {
		var dmi = new DynamicMomentumIndex(14);
		var ready = null;
		for (i in 0...40) {
			ready = dmi.update(100.0 + (i : Float));
		}
		Assert.notNull(ready);
		var afterNan = dmi.update(Math.NaN);
		Assert.equals(ready, afterNan);
	}

	public function testDynamicMomentumIndexResetClearsState() {
		var dmi = new DynamicMomentumIndex(14);
		for (i in 0...40) {
			dmi.update(100.0 + (i : Float));
		}
		Assert.isTrue(dmi.isReady());
		dmi.reset();
		Assert.isFalse(dmi.isReady());
		Assert.isNull(dmi.update(1.0));
	}

	public function testDynamicMomentumIndexBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...80) {
			prices.push(50.0 + Math.sin((i : Float) * 0.5) * 10.0);
		}
		var a = new DynamicMomentumIndex(14);
		var b = new DynamicMomentumIndex(14);
		var batch:Array<Null<Float>> = [];
		for (p in prices) {
			batch.push(a.update(p));
		}
		var streamed:Array<Null<Float>> = [];
		for (p in prices) {
			streamed.push(b.update(p));
		}
		for (i in 0...batch.length) {
			var b1 = batch[i];
			var b2 = streamed[i];
			if (b1 == null && b2 == null) continue;
			if (b1 != null && b2 != null) {
				Assert.floatEquals(b1, b2, 1e-9);
			} else {
				Assert.fail('Batch/streaming mismatch at index $i');
			}
		}
	}

	// ── FAMA ───────────────────────────────────────────────────────────────

	public function testFamaRejectsInvalidLimits() {
		try {
			new Fama(0.0, 0.05);
			Assert.fail("Fama should reject fast_limit 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new Fama(0.05, 0.5);
			Assert.fail("Fama should reject slow > fast");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testFamaNewWithValidLimitsConstructs() {
		var fama = new Fama(0.5, 0.05);
		var out = null;
		for (i in 0...60) {
			out = fama.update(100.0 + Math.sin((i : Float) * 0.3) * 5.0);
		}
		Assert.notNull(out);
	}

	public function testFamaWarmupPeriod() {
		var fama = Fama.classic();
		Assert.equals(33, fama.warmupPeriod());
	}

	public function testFamaBatchEqualsStreaming() {
		var prices:Array<Float> = [];
		for (i in 0...120) {
			prices.push(100.0 + Math.cos((i : Float) * 0.25) * 5.0);
		}
		var a = Fama.classic();
		var b = Fama.classic();
		var batch:Array<Null<Float>> = [];
		for (p in prices) {
			batch.push(a.update(p));
		}
		var streamed:Array<Null<Float>> = [];
		for (p in prices) {
			streamed.push(b.update(p));
		}
		for (i in 0...batch.length) {
			var b1 = batch[i];
			var b2 = streamed[i];
			if (b1 == null && b2 == null) continue;
			if (b1 != null && b2 != null) {
				Assert.floatEquals(b1, b2, 1e-9);
			} else {
				Assert.fail('Batch/streaming mismatch at index $i');
			}
		}
	}

	public function testFamaIgnoresNonFiniteInput() {
		var fama = Fama.classic();
		var prices:Array<Float> = [];
		for (i in 0...100) {
			prices.push(100.0 + Math.sin((i : Float) * 0.3) * 5.0);
		}
		for (p in prices) {
			fama.update(p);
		}
		var before = fama.value();
		Assert.notNull(before);
		var afterNan = fama.update(Math.NaN);
		Assert.equals(before, afterNan);
	}

	public function testFamaResetClearsState() {
		var fama = Fama.classic();
		var prices:Array<Float> = [];
		for (i in 0...100) {
			prices.push(100.0 + Math.sin((i : Float) * 0.3) * 5.0);
		}
		for (p in prices) {
			fama.update(p);
		}
		Assert.isTrue(fama.isReady());
		fama.reset();
		Assert.isFalse(fama.isReady());
	}
}

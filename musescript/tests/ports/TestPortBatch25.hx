package musescript.tests.ports;

import utest.Test;
import utest.Assert;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.RenkoTrailingStop;
import musescript.indicators.lib.Rmi;
import musescript.indicators.lib.Rocp;
import musescript.indicators.lib.Rocr;

/**
 * Batch 25: 4 Tier-1 indicators ported from wickra-core (renko_trailing_stop,
 * rmi, rocp, rocr). Known-value cases transcribed from the Rust fixture blocks
 * in vendor/wickra/crates/wickra-core/src/indicators/<name>.rs.
 */
class TestPortBatch25 extends Test {
	// ── RenkoTrailingStop ────────────────────────────────────────────────

	public function testRenkoRejectsInvalidBlock() {
		var exc = false;
		try new RenkoTrailingStop(0.0) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new RenkoTrailingStop(-1.0) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testRenkoFirstValueIsBlockBelowClose() {
		var s = new RenkoTrailingStop(1.0);
		Assert.floatEquals(99.0, s.update(100.0), 1e-9);
	}

	public function testRenkoStopOnlyMovesAfterFullBlockAdvance() {
		var s = new RenkoTrailingStop(1.0);
		s.update(100.0);
		Assert.floatEquals(99.0, s.update(100.5), 1e-9);
		Assert.floatEquals(100.0, s.update(101.0), 1e-9);
		Assert.floatEquals(102.0, s.update(103.5), 1e-9);
	}

	public function testRenkoBatchEqualsStreaming() {
		var prices = [for (i in 0...80) 100.0 + Math.sin(i * 0.2) * 6.0];
		var a = new RenkoTrailingStop(1.0), b = new RenkoTrailingStop(1.0);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	// ── RMI ──────────────────────────────────────────────────────────────

	public function testRmiRejectsZeroParams() {
		var exc = false;
		try new Rmi(0, 5) catch (e:String) exc = true;
		Assert.isTrue(exc);
		exc = false;
		try new Rmi(14, 0) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testRmiAccessorsAndMetadata() {
		var rmi = new Rmi(14, 5);
		Assert.equals(19, rmi.warmupPeriod());
		Assert.equals("RMI", rmi.name());
		Assert.isFalse(rmi.isReady());
	}

	public function testRmiBatchEqualsStreaming() {
		var prices = [for (i in 0...60) 100.0 + Math.sin(i * 0.4) * 8.0];
		var a = new Rmi(14, 5), b = new Rmi(14, 5);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	// ── ROCP ─────────────────────────────────────────────────────────────

	public function testRocpRejectsZeroPeriod() {
		var exc = false;
		try new Rocp(0) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testRocpAccessorsReportConfig() {
		var r = new Rocp(3);
		Assert.equals("ROCP", r.name());
		Assert.equals(4, r.warmupPeriod());
		Assert.isFalse(r.isReady());
	}

	public function testRocpKnownValueIsAFraction() {
		var r = new Rocp(1);
		var out = IndicatorBatch.run(r, [10.0, 11.0]);
		Assert.isNull(out[0]);
		Assert.floatEquals(0.1, out[1], 1e-9);
	}

	public function testRocpConstantSeriesYieldsZero() {
		var r = new Rocp(3);
		var out = IndicatorBatch.run(r, [for (_ in 0...12) 10.0]);
		for (i in 4...out.length) Assert.floatEquals(0.0, out[i], 1e-9);
	}

	public function testRocpBatchEqualsStreaming() {
		var prices = [for (i in 1...81) 100.0 + Math.sin(i * 0.3) * 7.0];
		var a = new Rocp(5), b = new Rocp(5);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}

	// ── ROCR ─────────────────────────────────────────────────────────────

	public function testRocrRejectsZeroPeriod() {
		var exc = false;
		try new Rocr(0) catch (e:String) exc = true;
		Assert.isTrue(exc);
	}

	public function testRocrAccessorsReportConfig() {
		var r = new Rocr(3);
		Assert.equals("ROCR", r.name());
		Assert.equals(4, r.warmupPeriod());
		Assert.isFalse(r.isReady());
	}

	public function testRocrKnownValueIsARatio() {
		var r = new Rocr(1);
		var out = IndicatorBatch.run(r, [10.0, 11.0]);
		Assert.isNull(out[0]);
		Assert.floatEquals(1.1, out[1], 1e-9);
	}

	public function testRocrConstantSeriesYieldsOne() {
		var r = new Rocr(3);
		var out = IndicatorBatch.run(r, [for (_ in 0...12) 10.0]);
		for (i in 4...out.length) Assert.floatEquals(1.0, out[i], 1e-9);
	}

	public function testRocrBatchEqualsStreaming() {
		var prices = [for (i in 1...81) 100.0 + Math.sin(i * 0.3) * 7.0];
		var a = new Rocr(5), b = new Rocr(5);
		var batched = IndicatorBatch.run(a, prices);
		var streamed = [for (p in prices) b.update(p)];
		for (i in 0...batched.length) {
			if (batched[i] == null) Assert.isNull(streamed[i]);
			else Assert.floatEquals(batched[i], streamed[i], 1e-9);
		}
	}
}

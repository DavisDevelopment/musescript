package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.harness.TapeLinter;
import musescript.evo.ProjectionScore;
import musescript.evo.ProjKind;

/**
 * Bucket H — tape linter + realized-target integrity (PIPELINE_HARDENING_TODO.md).
 */
class TestTapeLinter extends Test {
	static function bar(o:Float, h:Float, l:Float, c:Float, v:Float, t:Float, i:Int):Bar {
		return {open: o, high: h, low: l, close: c, volume: v, time: t, index: i};
	}

	static function cleanTape(n:Int):Array<Bar> {
		return [for (i in 0...n) {
			var px = 100.0 + i * 0.1;
			bar(px, px + 0.5, px - 0.5, px + 0.1, 1000, 1000.0 + i, i);
		}];
	}

	// ── H1: tape sanity ───────────────────────────────────────────────────────

	public function testCleanTapePasses() {
		var issues = TapeLinter.lint(cleanTape(30));
		Assert.equals(0, TapeLinter.errorCount(issues));
		Assert.isTrue(TapeLinter.isClean(cleanTape(30)));
	}

	public function testEmptyTapeErrors() {
		var issues = TapeLinter.lint([]);
		Assert.isTrue(TapeLinter.errorCount(issues) >= 1);
		Assert.equals("empty", issues[0].code);
	}

	public function testHighBelowLowIsError() {
		var bars = cleanTape(5);
		bars[2] = bar(100, 99, 101, 100, 1, 1002, 2);
		var issues = TapeLinter.lint(bars);
		Assert.isTrue(TapeLinter.errorCount(issues) >= 1);
		var codes = [for (iss in issues) iss.code];
		Assert.isTrue(codes.indexOf("high_lt_low") >= 0);
	}

	public function testHighBelowBodyIsError() {
		var bars = cleanTape(5);
		bars[1] = bar(100, 100.1, 99, 101, 1, 1001, 1); // close 101 > high 100.1
		Assert.isFalse(TapeLinter.isClean(bars));
	}

	public function testNegativeVolumeIsError() {
		var bars = cleanTape(5);
		bars[0] = bar(100, 101, 99, 100, -5, 1000, 0);
		Assert.isFalse(TapeLinter.isClean(bars));
	}

	public function testZeroVolumeWarnsByDefault() {
		var bars = cleanTape(5);
		bars[3] = bar(100, 101, 99, 100, 0, 1003, 3);
		var issues = TapeLinter.lint(bars);
		Assert.equals(0, TapeLinter.errorCount(issues));
		Assert.isTrue([for (iss in issues) iss.code].indexOf("zero_volume") >= 0);
	}

	// ── H2: look-ahead / time integrity ───────────────────────────────────────

	public function testTimeRegressionIsError() {
		var bars = cleanTape(5);
		bars[3] = bar(100, 101, 99, 100, 1, 1001, 3); // before bars[2].time=1002
		var issues = TapeLinter.lint(bars);
		Assert.isTrue([for (iss in issues) iss.code].indexOf("time_regression") >= 0);
		Assert.isFalse(TapeLinter.isClean(bars));
	}

	public function testDuplicateTimeIsError() {
		var bars = cleanTape(5);
		bars[2] = bar(100, 101, 99, 100, 1, bars[1].time, 2);
		Assert.isTrue([for (iss in TapeLinter.lint(bars)) iss.code].indexOf("duplicate_time") >= 0);
	}

	public function testIndexMismatchWarns() {
		var bars = cleanTape(4);
		bars[1] = bar(100, 101, 99, 100, 1, 1001, 99);
		var issues = TapeLinter.lint(bars);
		Assert.equals(0, TapeLinter.errorCount(issues));
		Assert.isTrue([for (iss in issues) iss.code].indexOf("index_mismatch") >= 0);
	}

	public function testRealTslaTapeIsClean() {
		var path = "data/real/tsla.csv";
		Assert.isTrue(OhlcvCsv.exists(path), "data/real/tsla.csv required for H standing check");
		var bars = OhlcvCsv.load(path);
		Assert.isTrue(bars.length > 1000);
		var issues = TapeLinter.lint(bars, {allowZeroVolume: true});
		Assert.equals(0, TapeLinter.errorCount(issues), TapeLinter.formatReport(issues, 10));
		Assert.isTrue(TapeLinter.isClean(bars, {allowZeroVolume: true}));
	}

	// ── H3: realized-vol / realized-target ────────────────────────────────────

	public function testRealizedTargetLastHAreNan() {
		var bars = cleanTape(20);
		var y = ProjectionScore.realizedTarget(bars, PLevel, 5);
		Assert.equals(20, y.length);
		for (i in 15...20) Assert.isTrue(Math.isNaN(y[i]), 'last-H bar $i must be NaN');
		for (i in 0...15) Assert.isTrue(Math.isFinite(y[i]));
	}

	public function testRealizedLevelUsesFutureNotPresent() {
		var bars = cleanTape(12);
		var y = ProjectionScore.realizedTarget(bars, PLevel, 3);
		Assert.floatEquals(bars[3].close, y[0], 1e-12);
		Assert.isTrue(y[0] != bars[0].close);
	}

	public function testForwardRangeIgnoresBarT() {
		var bars = cleanTape(10);
		// Spike only on bar t=2 high — must NOT enter range for target at t=2 (window is t+1..t+h)
		bars[2] = bar(100, 999, 99, 100, 1, 1002, 2);
		bars[3] = bar(100, 101, 99, 100, 1, 1003, 3);
		bars[4] = bar(100, 102, 98, 100, 1, 1004, 4);
		var y = ProjectionScore.realizedTarget(bars, PRange, 2);
		// range at t=2 covers bars 3..4 only → max high 102, min low 98 → 4
		Assert.floatEquals(4.0, y[2], 1e-9);
		Assert.isTrue(y[2] < 50, "bar-t spike must not leak into forwardRange");
	}

	public function testRealizedVolUsesFutureReturnsOnly() {
		var bars = cleanTape(30);
		var y = ProjectionScore.realizedTarget(bars, PVol, 5);
		Assert.isTrue(Math.isNaN(y[25]));
		Assert.isTrue(Math.isFinite(y[10]));
		Assert.isTrue(y[10] >= 0);
	}

	public function testMutatingFutureMovesTarget() {
		var bars = cleanTape(15);
		var y0 = ProjectionScore.realizedTarget(bars, PLevel, 2);
		bars[5].close = 999.0;
		bars[5].high = 1000.0;
		var y1 = ProjectionScore.realizedTarget(bars, PLevel, 2);
		Assert.isTrue(y0[3] != y1[3], "mutating future close must move PLevel target at t=3");
	}
}

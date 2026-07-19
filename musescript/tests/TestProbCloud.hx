package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.kestrel.ProbCloudRuntime;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.MuseCompiler;

/**
 * Kestrel probability-cloud query layer (2026-07-19). `ProbCloudRuntime` is
 * a pure-Haxe, dependency-free port of the Python `ProbabilityCloud` query
 * API (kalshi-ai-advisor/python/synth/marketsim/unified_diffmarketsim/
 * probability_cloud.py) — DELIBERATELY portable (same source compiles to JS
 * for web/mobile and Python for backtest) since the user explicitly wants
 * identical query behavior everywhere a strategy runs, not per-platform
 * reimplementations that could quietly drift. FITTING a cloud stays
 * Python-only (tools/kestrel_bridge.py, unverified in this session — needs
 * a real environment with the proprietary marketsim/encoder code to
 * integration-test; see musescript-kestrel-probcloud-bridge memory);
 * QUERYING one never touches Python again.
 *
 * The values below are hand-computed against the exact same formulas
 * `probability_cloud.py` uses (piecewise-linear `np.interp`, trapezoid
 * expected value, Bowley skew, cross-sectional conviction) on a SYMMETRIC
 * synthetic quantile grid chosen so most results have an obvious closed
 * form (0.0, 0.5, exact boundary values) — a real regression net for the
 * interpolation math without needing to run the Python original here.
 */
class TestProbCloud extends Test {
	static final QUANTILES:Array<Float> = [0.05, 0.25, 0.5, 0.75, 0.95];
	// Symbol A: wide symmetric fan. Symbol B: half the spread (tighter = more "convicted").
	static final VALS_A:Array<Float> = [-2.0, -0.5, 0.0, 0.5, 2.0];
	static final VALS_B:Array<Float> = [-1.0, -0.25, 0.0, 0.25, 1.0];

	static function twoSymbolCloud():ProbCloudRuntime {
		var json:Dynamic = {
			symbols: ["A", "B"],
			quantiles: QUANTILES,
			paths: [
				[for (v in VALS_A) [v]], // [quantile][horizonStep=1] per symbol
				[for (v in VALS_B) [v]],
			],
			horizon: 1,
			coverage: null
		};
		return ProbCloudRuntime.fromJson(json);
	}

	// ── interp() primitive ──────────────────────────────────────────────────

	public function testInterpExactGridPoint() {
		Assert.floatEquals(0.0, ProbCloudRuntime.interp(0.5, QUANTILES, VALS_A));
	}

	public function testInterpBetweenGridPoints() {
		// Halfway between quantile 0.25 (-0.5) and 0.5 (0.0) -> value -0.25.
		Assert.floatEquals(-0.25, ProbCloudRuntime.interp(0.375, QUANTILES, VALS_A));
	}

	public function testInterpClampsBelowRange() {
		Assert.floatEquals(VALS_A[0], ProbCloudRuntime.interp(0.0, QUANTILES, VALS_A));
		Assert.floatEquals(VALS_A[0], ProbCloudRuntime.interp(-999.0, QUANTILES, VALS_A));
	}

	public function testInterpClampsAboveRange() {
		Assert.floatEquals(VALS_A[VALS_A.length - 1], ProbCloudRuntime.interp(1.0, QUANTILES, VALS_A));
		Assert.floatEquals(VALS_A[VALS_A.length - 1], ProbCloudRuntime.interp(999.0, QUANTILES, VALS_A));
	}

	// ── central tendency & dispersion ───────────────────────────────────────

	public function testMedianIsMiddleQuantile() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(0.0, cloud.median("A"));
		Assert.floatEquals(0.0, cloud.median("B"));
	}

	public function testQuantileAtExactLevel() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(-2.0, cloud.quantileAt("A", 0.05));
		Assert.floatEquals(2.0, cloud.quantileAt("A", 0.95));
	}

	public function testIntervalAndIqr() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(-0.5, cloud.intervalLow("A", 0.5));
		Assert.floatEquals(0.5, cloud.intervalHigh("A", 0.5));
		Assert.floatEquals(1.0, cloud.iqr("A"));
	}

	public function testWidth() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(4.0, cloud.width("A", 0.9));
		Assert.floatEquals(2.0, cloud.width("B", 0.9));
	}

	/** Cross-sectional: the TIGHTER fan (B) must read as MORE convicted than
	 * the wider one (A) — this is the whole point of the metric. */
	public function testConvictionIsCrossSectional() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(0.0, cloud.conviction("A"));
		Assert.floatEquals(1.0, cloud.conviction("B"));
	}

	public function testSkewOfSymmetricFanIsZero() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(0.0, cloud.skew("A"));
	}

	public function testExpectedValueOfSymmetricFanIsZero() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(0.0, cloud.expectedValue("A"));
	}

	// ── probabilities ────────────────────────────────────────────────────────

	public function testCdfAtMedianIsHalf() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(0.5, cloud.cdf("A", 0.0));
	}

	public function testProbAboveBelowSumToOne() {
		var cloud = twoSymbolCloud();
		var above = cloud.probAbove("A", 0.0);
		var below = cloud.probBelow("A", 0.0);
		Assert.floatEquals(1.0, above + below);
		Assert.floatEquals(0.5, above);
	}

	public function testProbUpMatchesProbAboveZero() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(cloud.probAbove("A", 0.0), cloud.probUp("A"));
	}

	public function testProbBetweenMatchesCdfDifference() {
		var cloud = twoSymbolCloud();
		// cdf(0.5)=0.75, cdf(-0.5)=0.25 -> between = 0.5
		Assert.floatEquals(0.5, cloud.probBetween("A", -0.5, 0.5));
	}

	public function testProbBetweenOrderIndependent() {
		var cloud = twoSymbolCloud();
		Assert.floatEquals(cloud.probBetween("A", -0.5, 0.5), cloud.probBetween("A", 0.5, -0.5));
	}

	/** The whole point of the flat-tail clamp: probability never reads as
	 * exactly 0 or 1 even arbitrarily far outside the fitted grid — an
	 * "impossible" 0% or "certain" 100% would be an overconfident Kalshi
	 * strike quote, per the Python docstring's whole rationale. */
	public function testTailNeverReadsAsExactZeroOrOne() {
		var cloud = twoSymbolCloud();
		var farAbove = cloud.probAbove("A", 1000.0);
		var farBelow = cloud.probBelow("A", -1000.0);
		Assert.isTrue(farAbove > 0.0);
		Assert.isTrue(farBelow > 0.0);
		Assert.floatEquals(0.05, farAbove);
		Assert.floatEquals(0.05, farBelow);
	}

	// ── calibration honesty ─────────────────────────────────────────────────

	public function testUncalibratedByDefault() {
		var cloud = twoSymbolCloud();
		Assert.isFalse(cloud.isCalibrated());
		Assert.isTrue(StringTools.contains(cloud.trustNote(), "uncalibrated"));
	}

	public function testCalibratedWhenCoveragePresent() {
		var json:Dynamic = {
			symbols: ["A"],
			quantiles: QUANTILES,
			paths: [[for (v in VALS_A) [v]]],
			horizon: 1,
			coverage: {cov90: 0.89, cov50: 0.51}
		};
		var cloud = ProbCloudRuntime.fromJson(json);
		Assert.isTrue(cloud.isCalibrated());
		Assert.isTrue(StringTools.contains(cloud.trustNote(), "calibrated"));
		Assert.isFalse(StringTools.contains(cloud.trustNote(), "uncalibrated"));
	}

	// ── malformed input ──────────────────────────────────────────────────────

	public function testUnknownSymbolThrows() {
		var cloud = twoSymbolCloud();
		var threw = false;
		try {
			cloud.median("NOPE");
		} catch (_:Dynamic) {
			threw = true;
		}
		Assert.isTrue(threw);
	}

	// ── MuseScript builtin surface (interp + JS parity, real strategy source) ─
	// The cloud JSON is embedded as a properly-escaped MuseScript string
	// literal and constructed via `probcloud_from_json(...)` right inside the
	// source — this exercises the REAL dispatch path (ECall resolution, arg
	// passing, JS `api.invoke` vs interp) for every builtin, same discipline
	// as every other MuseScript-source-level test in this suite.

	/** `"..."` MuseScript string literal for `s`, escaping backslashes/quotes. */
	static function museStringLiteral(s:String):String {
		return '"' + StringTools.replace(StringTools.replace(s, "\\", "\\\\"), '"', '\\"') + '"';
	}

	static function cloudJson():String {
		return haxe.Json.stringify({
			symbols: ["A", "B"],
			quantiles: QUANTILES,
			paths: [
				[for (v in VALS_A) [v]],
				[for (v in VALS_B) [v]],
			],
			horizon: 1,
			coverage: null
		});
	}

	static function probeSrc():String {
		return 'strategy CloudProbe {\n'
			+ '  cloud = probcloud_from_json(${museStringLiteral(cloudJson())})\n'
			+ '  onBar {\n'
			+ '    plot(probcloud_median(cloud, "A"), "med")\n'
			+ '    plot(probcloud_prob_above(cloud, "A", 0.0), "pA")\n'
			+ '    plot(probcloud_conviction(cloud, "B"), "convB")\n'
			+ '    plot(probcloud_prob_between(cloud, "A", -0.5, 0.5), "between")\n'
			+ '  }\n'
			+ '}\n';
	}

	public function testFromJsonRoundTrips() {
		var cloud = musescript.builtins.ProbCloudBuiltins.fromJson(cloudJson());
		Assert.floatEquals(0.0, cloud.median("A"));
	}

	public function testBuiltinsCallableFromMuseScriptSource() {
		var src = probeSrc();
		var feed = BarFeed.synthetic(2, 1);
		var harness = new HarnessContext();
		new MuseInterp(harness).runBacktest(new MuseParser().parse(src), feed);
		var byLabel = new Map<String, Float>();
		for (c in harness.chart.commands) byLabel.set(c.label, c.series);
		Assert.floatEquals(0.0, byLabel.get("med"));
		Assert.floatEquals(0.5, byLabel.get("pA"));
		Assert.floatEquals(1.0, byLabel.get("convB"));
		Assert.floatEquals(0.5, byLabel.get("between"));
	}

	public function testBuiltinsJsInterpParity() {
		#if js
		var src = probeSrc();
		var feed = BarFeed.synthetic(3, 1);

		var interpHarness = new HarnessContext();
		new MuseInterp(interpHarness).runBacktest(new MuseParser().parse(src), feed);
		var interpVals = [for (c in interpHarness.chart.commands) c.series];

		var jsHarness = new HarnessContext();
		Reflect.setField(jsHarness, "feed", feed);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(src), {target: "js", strict: true});
		ex.fn(jsHarness);
		var jsVals = [for (c in jsHarness.chart.commands) c.series];

		Assert.same(interpVals, jsVals);
		#end
	}
}

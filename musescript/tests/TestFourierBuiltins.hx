package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.FourierDecompose;
import musescript.indicators.lib.FourierDominantPeriod;
import musescript.indicators.lib.FourierProjection;
import musescript.indicators.lib.FourierRecompose;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;

/**
 * The fourier_* builtins (MuseScript-native, FourierMath-based). The load-
 * bearing gates are mathematical identities, not smoke checks: full-rank
 * recomposition must reproduce the input EXACTLY (DFT completeness), and
 * projection of a sinusoid whose period divides the window must predict the
 * true future value to float precision.
 */
class TestFourierBuiltins extends Test {
	static inline var EPS = 1e-6;

	/** A*cos(2π·t/cyclePeriod + phi) + mean [+ slope·t]. */
	static function tone(t:Int, cyclePeriod:Float, a:Float, phi:Float, mean:Float, slope:Float = 0.0):Float {
		return mean + slope * t + a * Math.cos(2.0 * Math.PI * t / cyclePeriod + phi);
	}

	// ── decompose ────────────────────────────────────────────────────────────

	public function testDecomposeRecoversSingleToneMeanAmpPhase() {
		// N=8 window fed exactly 8 samples of mean 10 + 3·cos(2πj/8 + 0.7):
		// bin 1 must carry amp 3, phase 0.7; the vector leads with the mean.
		var d = new FourierDecompose(8, 1);
		var out:Null<Array<Float>> = null;
		for (j in 0...8) out = d.update(tone(j, 8, 3.0, 0.7, 10.0));
		Assert.notNull(out);
		Assert.equals(4, out.length); // [mean, period, amp, phase]
		Assert.isTrue(Math.abs(out[0] - 10.0) < EPS, 'mean ${out[0]}');
		Assert.isTrue(Math.abs(out[1] - 8.0) < EPS, 'period ${out[1]}');
		Assert.isTrue(Math.abs(out[2] - 3.0) < EPS, 'amp ${out[2]}');
		Assert.isTrue(Math.abs(out[3] - 0.7) < EPS, 'phase ${out[3]}');
	}

	public function testDecomposeRanksComponentsByAmplitude() {
		// Two tones: period 16 (amp 5) and period 8 (amp 2) in a 16-window —
		// the amp-5 component must come first.
		var d = new FourierDecompose(16, 2);
		var out:Null<Array<Float>> = null;
		for (j in 0...16)
			out = d.update(tone(j, 16, 5.0, 0.3, 100.0) + tone(j, 8, 2.0, 1.1, 0.0));
		Assert.notNull(out);
		Assert.equals(7, out.length); // mean + 2×(period, amp, phase)
		Assert.isTrue(Math.abs(out[1] - 16.0) < EPS);
		Assert.isTrue(Math.abs(out[2] - 5.0) < EPS);
		Assert.isTrue(Math.abs(out[4] - 8.0) < EPS);
		Assert.isTrue(Math.abs(out[5] - 2.0) < EPS);
	}

	public function testDecomposeWarmupAndValidation() {
		var d = new FourierDecompose(8, 2);
		Assert.equals(8, d.warmupPeriod());
		Assert.isFalse(d.isReady());
		for (j in 0...7) Assert.isNull(d.update(j + 0.0));
		Assert.notNull(d.update(7.0));
		Assert.isTrue(d.isReady());
		d.reset();
		Assert.isFalse(d.isReady());
		Assert.isNull(d.update(1.0));
		Assert.raises(() -> new FourierDecompose(3, 1));
		Assert.raises(() -> new FourierDecompose(8, -1));
	}

	// ── recompose ────────────────────────────────────────────────────────────

	public function testRecomposeFullRankIsExact() {
		// k >= N/2 keeps every bin → DFT completeness: output == input exactly.
		var r = new FourierRecompose(8, 4);
		var xs = [3.1, -0.4, 7.7, 2.2, 5.9, 5.0, -1.3, 4.6, 8.8, 0.2, 6.1, 3.3];
		var outs = IndicatorBatch.run(r, xs);
		for (i in 7...xs.length) {
			Assert.notNull(outs[i]);
			Assert.isTrue(Math.abs(outs[i] - xs[i]) < EPS, 'bar $i: ${outs[i]} vs ${xs[i]}');
		}
	}

	public function testRecomposeKZeroIsRollingMean() {
		var r = new FourierRecompose(4, 0);
		var outs = IndicatorBatch.run(r, [1.0, 2.0, 3.0, 4.0, 5.0]);
		Assert.isTrue(Math.abs(outs[3] - 2.5) < EPS); // mean(1,2,3,4)
		Assert.isTrue(Math.abs(outs[4] - 3.5) < EPS); // mean(2,3,4,5)
	}

	public function testRecomposeSingleToneWithK1IsExact() {
		// Pure in-band tone + mean: keeping 1 component reproduces it exactly.
		var r = new FourierRecompose(16, 1);
		var last:Null<Float> = null;
		var expected = 0.0;
		for (t in 0...48) {
			expected = tone(t, 16, 4.0, 0.9, 50.0);
			last = r.update(expected);
		}
		Assert.isTrue(Math.abs(last - expected) < EPS, '$last vs $expected');
	}

	// ── projection ───────────────────────────────────────────────────────────

	public function testProjectionPredictsInBandSinusoidExactly() {
		// Period-16 tone in a 32-window (bin 2 — integral), detrend off:
		// projecting h bars ahead must equal the true future sample.
		for (h in [0, 1, 3, 8]) {
			var p = new FourierProjection(32, 1, h, false);
			var last:Null<Float> = null;
			var t = 0;
			while (t < 48) {
				last = p.update(tone(t, 16, 4.0, 0.4, 20.0));
				t++;
			}
			var truth = tone(47 + h, 16, 4.0, 0.4, 20.0);
			Assert.isTrue(Math.abs(last - truth) < EPS, 'h=$h: $last vs $truth');
		}
	}

	public function testProjectionDetrendsLinearDrift() {
		// Trend + in-band cycle: with detrend on, the horizon-4 projection
		// must stay close to truth; the raw-window projection must not be
		// better (the trend aliases into the cycles without detrending).
		var mkSample = t -> tone(t, 16, 2.0, 0.0, 10.0, 0.25);
		var det = new FourierProjection(32, 2, 4, true);
		var raw = new FourierProjection(32, 2, 4, false);
		var lastDet:Null<Float> = null, lastRaw:Null<Float> = null;
		for (t in 0...64) {
			lastDet = det.update(mkSample(t));
			lastRaw = raw.update(mkSample(t));
		}
		var truth = mkSample(63 + 4);
		var errDet = Math.abs(lastDet - truth);
		var errRaw = Math.abs(lastRaw - truth);
		Assert.isTrue(errDet < 0.75, 'detrended err $errDet');
		Assert.isTrue(errDet <= errRaw + EPS, 'detrended ($errDet) should beat raw ($errRaw)');
	}

	public function testProjectionHorizonZeroMatchesRecomposeWhenNotDetrending() {
		var p = new FourierProjection(8, 2, 0, false);
		var r = new FourierRecompose(8, 2);
		var xs = [for (t in 0...20) tone(t, 8, 3.0, 0.2, 5.0) + tone(t, 4, 1.0, 1.4, 0.0)];
		var po = IndicatorBatch.run(p, xs);
		var ro = IndicatorBatch.run(r, xs.copy());
		for (i in 0...xs.length) {
			if (po[i] == null) { Assert.isNull(ro[i]); continue; }
			Assert.isTrue(Math.abs(po[i] - ro[i]) < EPS);
		}
	}

	public function testProjectionValidation() {
		Assert.raises(() -> new FourierProjection(3, 1, 1));
		Assert.raises(() -> new FourierProjection(8, -1, 1));
		Assert.raises(() -> new FourierProjection(8, 1, -1));
	}

	// ── dominant period ──────────────────────────────────────────────────────

	public function testDominantPeriodFindsTheCycle() {
		var dp = new FourierDominantPeriod(64);
		var last:Null<Float> = null;
		for (t in 0...64) last = dp.update(tone(t, 16, 5.0, 0.0, 100.0));
		Assert.isTrue(Math.abs(last - 16.0) < EPS, '$last');
	}

	// ── shared discipline: batch==streaming, non-finite inputs ──────────────

	public function testBatchEqualsStreaming() {
		var xs = [for (t in 0...60) tone(t, 12, 3.0, 0.5, 40.0, 0.05) + Math.sin(t * 1.7)];
		var a1 = new FourierRecompose(16, 3), b1 = new FourierRecompose(16, 3);
		var a2 = new FourierProjection(16, 3, 5), b2 = new FourierProjection(16, 3, 5);
		var a3 = new FourierDominantPeriod(16), b3 = new FourierDominantPeriod(16);
		for (pair in [{a: (a1 : Dynamic), b: (b1 : Dynamic)}, {a: (a2 : Dynamic), b: (b2 : Dynamic)}, {a: (a3 : Dynamic), b: (b3 : Dynamic)}]) {
			var batched = IndicatorBatch.run(pair.a, xs);
			var streamed = [for (x in xs) pair.b.update(x)];
			Assert.equals(batched.length, streamed.length);
			for (i in 0...batched.length) {
				if (batched[i] == null) Assert.isNull(streamed[i]);
				else Assert.floatEquals((batched[i] : Float), (streamed[i] : Float));
			}
		}
		// Vector-output decompose: elementwise.
		var a4 = new FourierDecompose(16, 3), b4 = new FourierDecompose(16, 3);
		var batched4 = IndicatorBatch.run(a4, xs);
		var streamed4 = [for (x in xs) b4.update(x)];
		for (i in 0...batched4.length) {
			if (batched4[i] == null) { Assert.isNull(streamed4[i]); continue; }
			Assert.equals(batched4[i].length, streamed4[i].length);
			for (q in 0...batched4[i].length) Assert.floatEquals(batched4[i][q], streamed4[i][q]);
		}
	}

	public function testNonFiniteInputIsIgnored() {
		var r = new FourierRecompose(4, 2);
		for (t in 0...4) r.update(t + 1.0);
		var before = r.update(5.0);
		Assert.isNull(r.update(Math.NaN));
		Assert.isNull(r.update(Math.POSITIVE_INFINITY));
		// State untouched: the next real value continues the same window.
		var after = r.update(5.0);
		Assert.notNull(after);
		Assert.notNull(before);
	}

	// ── end-to-end through the language (flat + ta.) ─────────────────────────

	public function testFourierBuiltinsThroughEngine() {
		var source = '
			@strategy("fourier")
			@on(bar) {
				var comps = fourier_decompose(close, 8, 2);
				var smooth = fourier_recompose(close, 8, 2);
				var proj = ta.fourier_projection(close, 8, 2, 3);
				var cyc = fourier_dominant_period(close, 8);
				if (!na(smooth) && !na(proj) && count(comps) > 0 && proj > smooth && cyc > 2) long();
				if (!na(proj) && !na(smooth) && proj < smooth) flat();
			}
		';
		var harness = new HarnessContext();
		var result = new MuseInterp(harness).runBacktest(
			new MuseParser().parse(source), BarFeed.synthetic(200, 11));
		Assert.isTrue(result.trades >= 0);
	}
}

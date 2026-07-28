package musescript.tests;

import utest.Assert;
import utest.Test;
import haxe.Int64;
import haxe.ds.Vector;
import musescript.ew.mcmc.DetRng;
import musescript.ew.mcmc.RegimeMcmc;

/**
 * The regime-switching MCMC must actually RECOVER latent regimes from data — not just run. Synthetic
 * tape: a calm first half (low σ) then a volatile second half (high σ). A correct sampler concentrates
 * posterior mass on the volatile regime in the back half and the calm regime in the front half. Also
 * pins determinism: same seed ⇒ identical posterior (the parity contract, checked here within-target;
 * cross-target parity is DetParityDump's job).
 */
class TestRegimeMcmc extends Test {
	static function synthTape(seed:Int64):Vector<Float> {
		// deterministic synthetic returns: 120 calm (σ≈0.004) then 120 volatile (σ≈0.02)
		var rng = new DetRng(seed);
		var n = 240;
		var v = new Vector<Float>(n);
		for (t in 0...n) {
			var sig = t < 120 ? 0.004 : 0.02;
			v[t] = sig * rng.nextGaussian();
		}
		return v;
	}

	public function testRecoversCalmThenVolatile() {
		var data = synthTape(Int64.make(0xABCD, 0x1234));
		var m = new RegimeMcmc(Int64.make(0, 42), data, 2);
		m.run(6000, 2000);

		// regime 0 is calm (hard σ-ascending), regime 1 volatile.
		// early bar → calm; late bar → volatile.
		var earlyCalm = m.regimeProb(20, 0);
		var lateVol = m.regimeProb(220, 1);

		Assert.isTrue(earlyCalm > 0.6, 'early bar should read calm (got P(calm)=$earlyCalm)');
		Assert.isTrue(lateVol > 0.6, 'late bar should read volatile (got P(vol)=$lateVol)');
		// the recovered volatile σ must exceed the calm σ by a clear margin
		Assert.isTrue(m.regimeSigma(1) > 2.0 * m.regimeSigma(0),
			'volatile σ should be >2× calm σ (got ${m.regimeSigma(0)} vs ${m.regimeSigma(1)})');
		// chain must actually be moving
		Assert.isTrue(m.acceptRate() > 0.02, 'accept rate too low (${m.acceptRate()})');
	}

	public function testCurrentRegimeAndEntropy() {
		var data = synthTape(Int64.make(0xABCD, 0x1234));
		var m = new RegimeMcmc(Int64.make(0, 42), data, 2);
		m.run(6000, 2000);
		// tape ends volatile → current regime is 1, entropy finite and >= 0
		Assert.equals(1, m.currentRegime());
		var e = m.currentEntropy();
		Assert.isTrue(e >= 0 && e <= 0.7, 'entropy out of range: $e'); // <= ln2
	}

	public function testDeterministicWithinTarget() {
		var data = synthTape(Int64.make(1, 2));
		var a = new RegimeMcmc(Int64.make(0, 7), data, 3);
		var b = new RegimeMcmc(Int64.make(0, 7), data, 3);
		a.run(3000, 1000);
		b.run(3000, 1000);
		for (t in [0, 50, 120, 200]) {
			for (k in 0...3) {
				Assert.floatEquals(a.regimeProb(t, k), b.regimeProb(t, k));
			}
		}
	}
}

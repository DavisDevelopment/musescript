package musescript.evo;

import musescript.murmuration.MurmurationConfig;

/**
 * POET-style environment co-evolution over `MurmurationConfig` (research B11): mutate env knobs,
 * keep only under a minimal criterion, and support cross-env transfer scoring.
 * Gated by CorpusEvoRun `--poet` (kestrel builds).
 *
 * «κόσμοι πολλοί· ψυχὴ μία πλανᾶται.»
 */
class PoetEnvs {
	/** Soft bounds: at least one elite Sharpe in (tooHard, tooEasy). */
	public static inline var TOO_HARD = -0.5;
	public static inline var TOO_EASY = 3.0;

	public static function cloneConfig(c:MurmurationConfig):MurmurationConfig {
		return {
			nAgents: c.nAgents, seed: c.seed, startPrice: c.startPrice, tick: c.tick,
			momentumHalflife: c.momentumHalflife, volWindow: c.volWindow,
			fundamentalVol: c.fundamentalVol, marketFactorVol: c.marketFactorVol,
			impact: c.impact, priceGridHalfWidth: c.priceGridHalfWidth,
			mixMarketMaker: c.mixMarketMaker, mixMomentum: c.mixMomentum,
			mixValue: c.mixValue, mixNoise: c.mixNoise,
			momGainMean: c.momGainMean, valGainMean: c.valGainMean,
			mmSpreadMean: c.mmSpreadMean, noiseRateMean: c.noiseRateMean,
			fundamentalMeanReversion: c.fundamentalMeanReversion
		};
	}

	/** Mutate one continuous knob by ±15–40%. */
	public static function mutate(cfg:MurmurationConfig, rng:Rand):MurmurationConfig {
		var out = cloneConfig(cfg);
		var which = rng.int(5);
		var scale = 0.85 + rng.float() * 0.55; // 0.85..1.40
		switch (which) {
			case 0: out.fundamentalVol = clamp(out.fundamentalVol * scale, 1e-6, 0.05);
			case 1: out.marketFactorVol = clamp(out.marketFactorVol * scale, 1e-6, 0.05);
			case 2: out.impact = clamp(out.impact * scale, 1e-4, 1.0);
			case 3: out.mixMarketMaker = clamp(out.mixMarketMaker * scale, 0.02, 0.6);
			default: out.fundamentalMeanReversion = clamp(out.fundamentalMeanReversion * scale, 0.0, 0.05);
		}
		out.seed = cfg.seed + 1 + rng.int(1000);
		return out;
	}

	/**
	 * Minimal criterion (MCC): keep env if some elite is neither hopeless nor trivially printing
	 * money — discriminates search without degenerate markets.
	 */
	public static function minimalCriterion(eliteScores:Array<Float>, ?tooHard:Float = TOO_HARD, ?tooEasy:Float = TOO_EASY):Bool {
		if (eliteScores == null || eliteScores.length == 0) return false;
		var any = false;
		for (s in eliteScores) {
			if (Math.isNaN(s) || s == Math.NEGATIVE_INFINITY) continue;
			if (s > tooHard && s < tooEasy) any = true;
		}
		return any;
	}

	/** Seed N envs along calm→volatile axis (same lerp CorpusEvoRun already uses). */
	public static function seedAxis(n:Int, ?meanReversion:Float = 0.0):Array<MurmurationConfig> {
		var out:Array<MurmurationConfig> = [];
		var base = MurmurationConfigs.defaults();
		for (m in 0...n) {
			var t = n > 1 ? m / (n - 1) : 0.0;
			var cfg = MurmurationConfigs.defaults();
			cfg.fundamentalVol = base.fundamentalVol * (0.3 + t * 2.0);
			cfg.marketFactorVol = base.marketFactorVol * (0.3 + t * 2.0);
			cfg.impact = base.impact * (0.5 + t * 1.5);
			cfg.mixMarketMaker = Math.max(0.02, base.mixMarketMaker * (1.0 - t * 0.7));
			if (meanReversion > 0) cfg.fundamentalMeanReversion = meanReversion * (1.0 + t * 4.0);
			cfg.seed = base.seed + m * 997;
			out.push(cfg);
		}
		return out;
	}

	static inline function clamp(x:Float, lo:Float, hi:Float):Float {
		return x < lo ? lo : (x > hi ? hi : x);
	}
}

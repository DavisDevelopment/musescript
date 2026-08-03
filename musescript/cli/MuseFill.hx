package musescript.cli;

import musescript.evo.BoolNode;
import musescript.evo.CorpusSeed;
import musescript.evo.Variation;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.Expand;
import musescript.evo.Palette;
import musescript.evo.Rand;
import musescript.evo.ScalarNode;
import musescript.evo.StrategyGenome;
import musescript.evo.rigor.OosVerdict;
import musescript.evo.rigor.ProbSharpe;
import musescript.evo.rigor.PurgeEmbargo;
import musescript.evo.rigor.TrialsSession;
import musescript.evo.rigor.TruthReport;
import musescript.evo.rigor.TruthVerdict;
import musescript.harness.Bar;
import musescript.harness.Metrics;

/**
 * `muse fill` (SPEC_AUTHOR_HOLES) — fill an author's sketch holes under the honest gate.
 *
 * A `?`-bearing sketch reverse-compiles to a TEMPLATED genome; we search N fills
 * (`Variation.fillHoles`), keep the best, and report its verdict DEFLATED BY THE
 * SEARCH SIZE (`ProbSharpe.dsr(returns, N)` / `TruthReport` with `nTrials = N_eval`).
 *
 * Honesty model (P1 OOS):
 * - Default / `honestOos=false`: full-sample rank+score. TruthReport cannot claim
 *   Robust (at best Fragile). Publishing Robust without OOS is refused.
 * - `honestOos=true`: rank fills on the IS slice; score the champion on the
 *   purge/embargo OOS slice; mark `oosHeld`/`purgeEmbargoApplied`. Robust is
 *   earnable only when OOS gates clear under search-N deflation.
 */
class MuseFill {
	public static function run(
		sketch:String, budget:Int, seed:Int, bars:Array<Bar>, ?opts:FillOpts
	):FillReport {
		if (budget < 1) return { ok: false, reason: "budget must be >= 1" };
		if (bars == null || bars.length < 3) return { ok: false, reason: "tape too short" };

		var honestOos = opts != null && opts.honestOos == true;
		var oosFrac = opts != null && opts.oosFrac != null ? opts.oosFrac : 0.25;
		var embargoBars = opts != null && opts.embargoBars != null ? opts.embargoBars : 20;
		var minTrades = opts != null && opts.minTrades != null ? opts.minTrades : 20;
		var minOosBars = opts != null && opts.minOosBars != null ? opts.minOosBars : 40;
		var minIsBars = opts != null && opts.minIsBars != null ? opts.minIsBars : 40;
		var psrGate = opts != null && opts.psrGate != null ? opts.psrGate : 0.95;
		var nBoot = opts != null && opts.nBoot != null ? opts.nBoot : 80;

		var allowed = new Map<String, Bool>();
		for (n in Palette.INDS) allowed.set(n, true);

		var t = CorpusSeed.translateSource(sketch, allowed);
		if (t.genome == null) return { ok: false, reason: "translate failed: " + t.error };
		if (!Variation.isTemplated(t.genome)) return { ok: false, reason: "no holes to fill (sketch has no `?`)" };

		var isBars = bars;
		var oosBars:Array<Bar> = null;
		var split = { isEnd: bars.length, oosStart: bars.length, embargo: 0, purged: 0 };
		if (honestOos) {
			// Shrink embargo before giving up on short Studio/test tapes (same idea as MuseRuntime).
			var n = bars.length;
			var rawOos = Std.int(n * oosFrac);
			if (rawOos < 1) rawOos = 1;
			if (rawOos - embargoBars < minOosBars && embargoBars > 0) {
				var shrink = rawOos - minOosBars;
				embargoBars = shrink > 0 ? shrink : 0;
			}
			split = PurgeEmbargo.split(n, oosFrac, embargoBars);
			var oosLen = n - split.oosStart;
			if (oosLen < minOosBars || split.isEnd < minIsBars) {
				return {
					ok: false,
					reason: 'OOS/IS too short after purge (IS=${split.isEnd} OOS=$oosLen embargo=${split.embargo});'
						+ ' refuse Robust path without a real holdout'
				};
			}
			isBars = bars.slice(0, split.isEnd);
			oosBars = bars.slice(split.oosStart, n);
		}

		TrialsSession.reset();
		var v = new Variation(seed);
		var best:StrategyGenome = null;
		var bestFr:FitnessResult = null;
		var bestScore = Math.NEGATIVE_INFINITY;
		var evaluated = 0;

		for (k in 0...budget) {
			var cand = v.fillHoles(t.genome);
			var fr = Fitness.evaluate(cand, isBars);
			if (!fr.ok || fr.bankrupt) continue;
			evaluated++;
			TrialsSession.recordTrial();
			var sc = Fitness.score(fr, 1); // 1-trade floor for RANKING during the search
			if (sc > bestScore) { bestScore = sc; best = cand; bestFr = fr; }
		}

		if (best == null) return { ok: false, reason: "no valid fill in " + budget + " tries" };

		// Honest gate: published nTrials MUST be the search size (distinct evaluated fills).
		var nTrials = evaluated < 1 ? 1 : evaluated;
		if (TrialsSession.getCount() != nTrials) {
			return { ok: false, reason: "trials-session drift (internal)" };
		}

		var dishonest = refuseDishonestVerdict(nTrials, budget);
		if (dishonest != null) return { ok: false, reason: dishonest };

		var scoreBars = honestOos ? oosBars : bars;
		var scoreFr = honestOos ? Fitness.evaluate(best, scoreBars) : bestFr;
		if (scoreFr == null || !scoreFr.ok) {
			return { ok: false, reason: "champion failed on " + (honestOos ? "OOS" : "full") + " tape" };
		}

		var returns = Metrics.returnsFromEquity(scoreFr.equity);
		var dsrRaw = returns.length >= 3 ? ProbSharpe.dsr(returns, 1) : 0.0;
		var dsrDeflated = returns.length >= 3 ? ProbSharpe.dsr(returns, nTrials) : 0.0;

		// Cash/flat null on the scored slice — beats-null is not buy-and-hold unless asked.
		var nullFr = Fitness.evaluate(flatGenome(), scoreBars);
		var nullSr = nullFr.ok && Math.isFinite(nullFr.sharpe) ? nullFr.sharpe : 0.0;

		var tr = TruthReport.evaluate(returns, scoreFr.trades, nullSr, {
			nTrials: nTrials,
			minTrades: minTrades,
			bootSeed: seed,
			nBoot: nBoot,
			psrGate: psrGate,
			oosHeld: honestOos,
			purgeEmbargoApplied: honestOos,
			embargoBars: honestOos ? split.embargo : 0
		});

		var refuseRobust = refuseRobustWithoutOos(honestOos, tr.verdict);
		if (refuseRobust != null) return { ok: false, reason: refuseRobust };

		var oosGo:Null<Bool> = null;
		var oosReason:Null<String> = null;
		if (honestOos) {
			var bh = Fitness.evaluate(buyHoldGenome(), scoreBars);
			var bhSr = bh.ok && Math.isFinite(bh.sharpe) ? bh.sharpe : 0.0;
			var ov = OosVerdict.evaluate(returns, scoreFr.trades, bhSr, {
				minTrades: minTrades, nTrials: nTrials, nBoot: nBoot, psrGate: psrGate, bootSeed: seed
			});
			oosGo = ov.go;
			oosReason = ov.reason;
		}

		var provisional = scoreFr.trades >= minTrades && dsrDeflated > 0.5;
		var verdictLabel = switch (tr.verdict) {
			case TruthVerdict.Robust: "Robust";
			case TruthVerdict.Fragile:
				honestOos ? "Fragile"
					: (provisional ? "Fragile (DSR ok, no OOS)" : "Fragile");
			case TruthVerdict.Overfit: "Overfit";
			case TruthVerdict.CoinFlip:
				honestOos ? "Coin-flip"
					: (provisional ? "Clears-DSR (provisional, no OOS)" : "Coin-flip");
		};

		return {
			ok: true,
			reason: "",
			filled: Expand.expand(best),
			sharpe: scoreFr.sharpe,
			trades: scoreFr.trades,
			nEval: evaluated,
			nTrials: nTrials,
			dsrRaw: dsrRaw,
			dsrDeflated: dsrDeflated,
			verdict: verdictLabel,
			truthVerdict: Std.string(tr.verdict),
			honestOos: honestOos,
			oosHeld: tr.oosHeld || tr.purgeEmbargoApplied,
			purgeEmbargoApplied: tr.purgeEmbargoApplied,
			embargoBars: tr.embargoBars,
			isBars: split.isEnd,
			oosBars: honestOos ? (bars.length - split.oosStart) : 0,
			isSharpe: bestFr.sharpe,
			oosGo: oosGo,
			oosReason: oosReason
		};
	}

	/**
	 * A multi-candidate fill whose published trials count stays at 1 is p-hacking.
	 * Returns an error reason, or null if honest.
	 */
	public static function refuseDishonestVerdict(nTrialsPublished:Int, budget:Int):Null<String> {
		if (budget > 1 && nTrialsPublished <= 1) {
			return "dishonest path refused: cannot publish nTrials=1 after budget=" + budget
				+ " (search size must deflate DSR)";
		}
		return null;
	}

	/**
	 * Robust requires a real purge/embargo OOS hold. In-sample-only fill must not claim it.
	 */
	public static function refuseRobustWithoutOos(honestOos:Bool, truthVerdict:TruthVerdict):Null<String> {
		if (truthVerdict == TruthVerdict.Robust && !honestOos) {
			return "dishonest path refused: Robust requires honest OOS / purge-embargo (honestOos=true)";
		}
		return null;
	}

	static function flatGenome():StrategyGenome {
		return {
			entryLong: BCmp(">", KConst(0.0), KConst(1.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(1.0), KConst(0.0)),
			exitShort: BCmp(">", KConst(1.0), KConst(0.0)),
			size: KConst(1.0), params: [], name: "flat_null", lineage: ["muse-fill-null"]
		};
	}

	static function buyHoldGenome():StrategyGenome {
		return {
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "buy_and_hold", lineage: ["muse-fill-bh"]
		};
	}

	/**
	 * Momentum tape — a GENUINE, learnable edge: AR(1)-persistent returns (trends that continue),
	 * so a fill that times the trend has real, non-spurious skill.
	 */
	public static function momentumTape(n:Int, seed:Int):Array<Bar> {
		var rng = new Rand(seed);
		var bars:Array<Bar> = [];
		var prev = 100.0;
		var ret = 0.0;
		for (i in 0...n) {
			var eps = (rng.float() * 2 - 1) * 0.006;
			ret = 0.6 * ret + eps + 0.0002;
			var close = prev * (1 + ret);
			bars.push({
				open: prev,
				high: Math.max(prev, close) * 1.001,
				low: Math.min(prev, close) * 0.999,
				close: close, volume: 1000.0, time: i, index: i
			});
			prev = close;
		}
		return bars;
	}

	/**
	 * Strong planted trend (high SNR) for OOS positive control — mild drift so OOS prices stay
	 * affordable under `long(1)` sizing; both halves keep the same edge so a fill that stays long
	 * can clear TruthReport.Robust under modest search-N.
	 */
	public static function plantedTrendTape(n:Int, seed:Int, drift:Float = 0.0012):Array<Bar> {
		var rng = new Rand(seed);
		var bars:Array<Bar> = [];
		var prev = 100.0;
		var ret = 0.0;
		for (i in 0...n) {
			var eps = (rng.float() * 2 - 1) * 0.0008;
			ret = 0.75 * ret + eps + drift;
			var close = prev * (1 + ret);
			bars.push({
				open: prev,
				high: Math.max(prev, close) * 1.0005,
				low: Math.min(prev, close) * 0.9995,
				close: close, volume: 1000.0, time: i, index: i
			});
			prev = close;
		}
		return bars;
	}

	/** Driftless seeded random walk — the honest null tape (no edge to find). */
	public static function driftlessTape(n:Int, seed:Int):Array<Bar> {
		var rng = new Rand(seed);
		var bars:Array<Bar> = [];
		var prev = 100.0;
		for (i in 0...n) {
			var ret = (rng.float() * 2 - 1) * 0.01;
			var close = prev * (1 + ret);
			bars.push({
				open: prev,
				high: Math.max(prev, close) * 1.001,
				low: Math.min(prev, close) * 0.999,
				close: close, volume: 1000.0, time: i, index: i
			});
			prev = close;
		}
		return bars;
	}

	static function fmt(x:Float, dp = 4):String {
		if (!Math.isFinite(x)) return "n/a";
		var p = Math.pow(10, dp);
		return Std.string(Math.round(x * p) / p);
	}

	public static function main() {
		Sys.println("== muse fill — honest hole-filling (P1 OOS) ==\n");
		var tape = driftlessTape(400, 20260731);
		var noiseSketch = "strategy Noise {\n  onBar {\n    when ?Bool && close > ?Scalar: { long(1) }\n    when ?Bool: { flat() }\n  }\n}";
		Sys.println("SKETCH (all-holes, on a DRIFTLESS null tape — the negative control):");
		Sys.println(noiseSketch + "\n");

		for (budget in [50, 500, 3000]) {
			var r = run(noiseSketch, budget, 1337, tape);
			if (!r.ok) { Sys.println("budget " + budget + ": " + r.reason); continue; }
			Sys.println("budget=" + budget + "  nEval=" + r.nEval
				+ "  nTrials=" + r.nTrials
				+ "  bestSharpe=" + fmt(r.sharpe, 3)
				+ "  trades=" + r.trades
				+ "  DSR@1=" + fmt(r.dsrRaw)
				+ "  DSR@N=" + fmt(r.dsrDeflated)
				+ "  => " + r.verdict
				+ "  truth=" + r.truthVerdict);
		}
		Sys.println("\nExpect: DSR@N collapses toward 0 as N grows; TruthReport stays CoinFlip/Fragile,");
		Sys.println("never Robust without OOS — a noise sketch cannot be filled into an edge.");

		Sys.println("\n-- POSITIVE control: planted trend + honestOos purge/embargo --");
		var edgeTape = plantedTrendTape(480, 424242);
		var edgeSketch = "strategy Mom {\n  onBar {\n    when close > ?Scalar in [0.0, 50.0]: { long(1) }\n    when close < ?Scalar in [-10.0, -1.0]: { flat() }\n  }\n}";
		Sys.println(edgeSketch);
		for (budget in [3, 20]) {
			var r = run(edgeSketch, budget, 99, edgeTape, {
				honestOos: true, oosFrac: 0.28, embargoBars: 5, minTrades: 1, nBoot: 60
			});
			if (!r.ok) { Sys.println("budget " + budget + ": " + r.reason); continue; }
			Sys.println("budget=" + budget + "  nEval=" + r.nEval
				+ "  IS=" + r.isBars + " OOS=" + r.oosBars + " embargo=" + r.embargoBars
				+ "  oosSharpe=" + fmt(r.sharpe, 3) + "  trades=" + r.trades
				+ "  DSR@1=" + fmt(r.dsrRaw) + "  DSR@N=" + fmt(r.dsrDeflated)
				+ "  => " + r.verdict + "  truth=" + r.truthVerdict
				+ "  oosHeld=" + r.oosHeld);
		}
		Sys.println("\nExpect: with OOS held, Robust is earnable when gates clear; IS-only cannot claim it.");
		Sys.println("Dishonest nTrials=1 publish is refused.");
	}
}

typedef FillOpts = {
	/** Rank on IS, score TruthReport on purge/embargo OOS. Required to earn Robust. */
	?honestOos:Bool,
	?oosFrac:Float,
	?embargoBars:Int,
	?minTrades:Int,
	?minOosBars:Int,
	?minIsBars:Int,
	?psrGate:Float,
	?nBoot:Int
}

typedef FillReport = {
	ok:Bool,
	reason:String,
	?filled:String,
	?sharpe:Float,
	?trades:Int,
	?nEval:Int,
	?nTrials:Int,
	?dsrRaw:Float,
	?dsrDeflated:Float,
	?verdict:String,
	?truthVerdict:String,
	?honestOos:Bool,
	?oosHeld:Bool,
	?purgeEmbargoApplied:Bool,
	?embargoBars:Int,
	?isBars:Int,
	?oosBars:Int,
	?isSharpe:Float,
	?oosGo:Null<Bool>,
	?oosReason:Null<String>
};

package musescript.cli;

import musescript.evo.CorpusSeed;
import musescript.evo.Variation;
import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.evo.Expand;
import musescript.evo.Palette;
import musescript.evo.Rand;
import musescript.evo.StrategyGenome;
import musescript.evo.rigor.ProbSharpe;
import musescript.harness.Bar;

/**
 * `muse fill` (SPEC_AUTHOR_HOLES P0.3) — fill an author's sketch holes under the honest gate.
 *
 * A `?`-bearing sketch reverse-compiles to a TEMPLATED genome; we search N fills (Variation
 * .fillHoles), keep the best on the tape, and report its verdict DEFLATED BY THE SEARCH SIZE
 * (ProbSharpe.dsr(returns, N)). The more we let the engine try, the higher the bar the winner
 * must clear — so a noise sketch comes back Coin-flip no matter how hard we search. Random-search
 * fill in P0; the same seam upgrades to constrained evolution later (§14).
 */
class MuseFill {
	public static function run(sketch:String, budget:Int, seed:Int, bars:Array<Bar>):FillReport {
		var allowed = new Map<String, Bool>();
		for (n in Palette.INDS) allowed.set(n, true);

		var t = CorpusSeed.translateSource(sketch, allowed);
		if (t.genome == null) return { ok: false, reason: "translate failed: " + t.error };
		if (!Variation.isTemplated(t.genome)) return { ok: false, reason: "no holes to fill (sketch has no `?`)" };

		var v = new Variation(seed);
		var best:StrategyGenome = null;
		var bestFr:FitnessResult = null;
		var bestScore = Math.NEGATIVE_INFINITY;
		var evaluated = 0;

		for (k in 0...budget) {
			var cand = v.fillHoles(t.genome);
			var fr = Fitness.evaluate(cand, bars);
			if (!fr.ok || fr.bankrupt) continue;
			evaluated++;
			var sc = Fitness.score(fr, 1); // 1-trade floor for RANKING during the search
			if (sc > bestScore) { bestScore = sc; best = cand; bestFr = fr; }
		}

		if (best == null) return { ok: false, reason: "no valid fill in " + budget + " tries" };

		var returns = returnsFrom(bestFr.equity);
		var dsrRaw = returns.length >= 3 ? ProbSharpe.dsr(returns, 1) : 0.0;
		var dsrDeflated = returns.length >= 3 ? ProbSharpe.dsr(returns, evaluated) : 0.0;
		// The honest gate: distinguishable from best-of-N noise AND enough trades to trust the Sharpe.
		var eligible = bestFr.trades >= 20 && dsrDeflated > 0.5;

		return {
			ok: true,
			reason: "",
			filled: Expand.expand(best),
			sharpe: bestFr.sharpe,
			trades: bestFr.trades,
			nEval: evaluated,
			dsrRaw: dsrRaw,
			dsrDeflated: dsrDeflated,
			verdict: eligible ? "Robust (provisional)" : "Coin-flip"
		};
	}

	static function returnsFrom(eq:Null<Array<Float>>):Array<Float> {
		if (eq == null) return [];
		var r = [];
		for (i in 1...eq.length) if (eq[i - 1] != 0) r.push(eq[i] / eq[i - 1] - 1);
		return r;
	}

	/** Driftless seeded random walk — the honest null tape (no edge to find). */
	public static function driftlessTape(n:Int, seed:Int):Array<Bar> {
		var rng = new Rand(seed);
		var bars:Array<Bar> = [];
		var prev = 100.0;
		for (i in 0...n) {
			var ret = (rng.float() * 2 - 1) * 0.01; // symmetric => zero drift
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
		Sys.println("== muse fill — honest hole-filling (P0) ==\n");
		var tape = driftlessTape(400, 20260731);
		var noiseSketch = "strategy Noise {\n  onBar {\n    when ?Bool && close > ?Scalar: { long(1) }\n    when ?Bool: { flat() }\n  }\n}";
		Sys.println("SKETCH (all-holes, on a DRIFTLESS null tape — the negative control):");
		Sys.println(noiseSketch + "\n");

		// Show the anti-gaming: the deflated bar RISES as the search budget grows.
		for (budget in [50, 500, 3000]) {
			var r = run(noiseSketch, budget, 1337, tape);
			if (!r.ok) { Sys.println("budget " + budget + ": " + r.reason); continue; }
			Sys.println("budget=" + budget + "  nEval=" + r.nEval
				+ "  bestSharpe=" + fmt(r.sharpe, 3)
				+ "  trades=" + r.trades
				+ "  DSR@1=" + fmt(r.dsrRaw)
				+ "  DSR@N=" + fmt(r.dsrDeflated)
				+ "  => " + r.verdict);
		}
		Sys.println("\nExpect: DSR@N collapses toward 0 as N grows (best-of-N noise deflated),");
		Sys.println("and the verdict stays Coin-flip — a noise sketch cannot be filled into an edge.");
	}
}

typedef FillReport = {
	ok:Bool,
	reason:String,
	?filled:String,
	?sharpe:Float,
	?trades:Int,
	?nEval:Int,
	?dsrRaw:Float,
	?dsrDeflated:Float,
	?verdict:String
};

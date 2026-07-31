package;

import musescript.evo.rigor.LeaderboardScore;
import musescript.ew.mcmc.DetRng;

/**
 * Generates the /leaderboard seed board from the REAL audited scoring math.
 * Curated reference strategies (genuine-edge / null / thin / overfit / decayed)
 * are ranked by LeaderboardScore.rank at the live field size N, so every score
 * on the wall (field-N-deflated DSR, lower-CI rankStat, PBO gate, eligibility)
 * comes from the same instrument the product ships — nothing hand-tuned.
 *
 * Output: JSON to stdout, consumed by mederos-web public/leaderboard-seed.json.
 */
class LeaderboardSeedGen {
	static var rng:DetRng;

	// A return series with a target per-obs mean/std (genuine structure, not faked
	// numbers — the scores are computed from these by the real code).
	static function series(n:Int, mean:Float, std:Float):Array<Float> {
		return [for (_ in 0...n) mean + std * rng.nextGaussian()];
	}

	static function main() {
		rng = new DetRng(haxe.Int64.make(0, 20260730));

		// id, label, author, n, mean, std, trades, pbo, heldDays, source
		// Effect sizes are deliberately unambiguous so the board teaches cleanly;
		// the scores themselves are still computed by the real instrument.
		var defs:Array<Dynamic> = [
			// Genuine-edge candidates (clear the lower-CI gate -> make the wall)
			{ id: "vt-carry", label: "Vol-target carry", author: "arc", n: 250, mean: 0.24, std: 0.78, trades: 88, pbo: 0.16, held: 41,
			  src: "param look: Scalar = 20\nstrategy VtCarry {\n  onBar {\n    when volTarget(close, look) > 0: { long() }\n  }\n}" },
			{ id: "xs-mom", label: "Cross-sectional momentum", author: "quill", n: 240, mean: 0.205, std: 0.82, trades: 132, pbo: 0.24, held: 33,
			  src: "strategy XsMom {\n  onBar {\n    when rank(mom(close, 60)) > 0.8: { long() }\n  }\n}" },
			{ id: "regime-trend", label: "Regime-gated trend", author: "sable", n: 240, mean: 0.19, std: 0.83, trades: 71, pbo: 0.29, held: 26,
			  src: "strategy RegimeTrend {\n  onBar {\n    when trendUp(close, 100) and lowVol(close, 20): { long() }\n  }\n}" },
			{ id: "don-break", label: "Donchian breakout + ATR stop", author: "mesa", n: 230, mean: 0.185, std: 0.84, trades: 64, pbo: 0.33, held: 12,
			  src: "strategy DonBreak {\n  onBar {\n    when crossover(close, donchianHi(close, 55)): { long() }\n  }\n}" },
			// Null / coin-flip (no real edge -> CI includes null -> ineligible)
			{ id: "sma-cross", label: "SMA crossover 8/26", author: "novice", n: 210, mean: -0.04, std: 1.0, trades: 54, pbo: 0.43, held: 0,
			  src: "strategy SmaCross {\n  onBar {\n    when crossover(sma(close,8), sma(close,26)): { long() }\n  }\n}" },
			{ id: "macd-hist", label: "MACD histogram flip", author: "drift", n: 205, mean: -0.07, std: 1.04, trades: 77, pbo: 0.47, held: 0,
			  src: "strategy MacdHist {\n  onBar {\n    when macdHist(close) > 0: { long() }\n  }\n}" },
			// Thin-trade false positive (great Sharpe, <20 trades -> ineligible)
			{ id: "lucky-spike", label: "Earnings gap punt", author: "yolo", n: 60, mean: 0.42, std: 0.7, trades: 6, pbo: 0.2, held: 0,
			  src: "strategy Gap {\n  onBar {\n    when gapUp(open, close, 0.08): { long() }\n  }\n}" },
			// Overfit selection (PBO >= 0.5 -> ineligible even with positive returns)
			{ id: "kitchen-sink", label: "14-indicator ensemble", author: "maximus", n: 220, mean: 0.2, std: 0.8, trades: 96, pbo: 0.63, held: 0,
			  src: "strategy KitchenSink {\n  onBar {\n    when confluence14(close) > 9: { long() }\n  }\n}" },
		];

		var entries:Array<LeaderboardEntryIn> = [];
		var meta:Map<String, Dynamic> = new Map();
		for (d in defs) {
			entries.push({
				returns: series(d.n, d.mean, d.std),
				trades: d.trades,
				pbo: d.pbo,
				id: d.id,
				label: d.label,
				author: d.author,
				category: "studio-default"
			});
			meta.set(d.id, d);
		}

		var ctx:LeaderboardCtx = { fieldN: entries.length, minTrades: 20, nBoot: 400, nullValue: 0.0 };
		var ranked = LeaderboardScore.rank(entries, ctx);

		var buf = new StringBuf();
		buf.add('{\n');
		buf.add('  "schema": "mederos.leaderboardSeed.v1",\n');
		buf.add('  "category": "studio-default",\n');
		buf.add('  "fieldN": ' + ranked.fieldN + ',\n');
		buf.add('  "eligibleCount": ' + ranked.eligibleCount + ',\n');
		buf.add('  "wall": [\n');
		for (i in 0...ranked.wall.length) {
			var w = ranked.wall[i];
			var s = w.score;
			var m = meta.get(s.id);
			buf.add('    ' + row(w.rank, s, m));
			buf.add(i < ranked.wall.length - 1 ? ',\n' : '\n');
		}
		buf.add('  ],\n');
		buf.add('  "failed": [\n');
		for (i in 0...ranked.failed.length) {
			var s = ranked.failed[i];
			var m = meta.get(s.id);
			buf.add('    ' + row(-1, s, m));
			buf.add(i < ranked.failed.length - 1 ? ',\n' : '\n');
		}
		buf.add('  ]\n');
		buf.add('}\n');
		Sys.print(buf.toString());
	}

	static function num(x:Float):String {
		if (x == null || !Math.isFinite(x)) return "null";
		return Std.string(Math.round(x * 10000) / 10000);
	}

	static function jstr(s:String):String {
		if (s == null) return '""';
		var out = s.split("\\").join("\\\\").split('"').join('\\"').split("\n").join("\\n");
		return '"' + out + '"';
	}

	static function verdictOf(s:LeaderboardScoreOut):String {
		if (s.eligible) return "Robust";
		var r = s.reason != null ? s.reason : "";
		if (r.indexOf("minTrades") >= 0) return "Thin";
		if (r.indexOf("overfit") >= 0 || r.indexOf("PBO") >= 0) return "Overfit";
		return "Coin-flip";
	}

	static function row(rank:Int, s:LeaderboardScoreOut, m:Dynamic):String {
		var parts = [];
		if (rank > 0) parts.push('"rank": ' + rank);
		parts.push('"id": ' + jstr(s.id));
		parts.push('"label": ' + jstr(s.label));
		parts.push('"author": ' + jstr(s.author));
		parts.push('"verdict": ' + jstr(verdictOf(s)));
		parts.push('"eligible": ' + s.eligible);
		parts.push('"rankStat": ' + num(s.rankStat));
		parts.push('"dsr": ' + num(s.dsrDeflated));
		parts.push('"pbo": ' + num(s.pbo));
		parts.push('"ciLo": ' + num(s.ciLo));
		parts.push('"ciHi": ' + num(s.ciHi));
		parts.push('"trades": ' + s.trades);
		parts.push('"nTrials": ' + s.nTrials);
		parts.push('"seedsPassed": ' + s.seedsPassed);
		parts.push('"heldDays": ' + (m != null ? m.held : 0));
		parts.push('"reason": ' + jstr(s.reason));
		parts.push('"source": ' + jstr(m != null ? m.src : ""));
		return '{ ' + parts.join(", ") + ' }';
	}
}

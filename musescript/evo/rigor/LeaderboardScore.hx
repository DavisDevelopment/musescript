package musescript.evo.rigor;

/**
 * Honest Leaderboard scoring contract.
 *
 * Ranking math IS the anti-gaming: field-N-deflated DSR, lower-CI ordering,
 * eligibility gates before rank, account-trials rising bar. No popularity /
 * streak / raw-Sharpe signals — those poison the brand.
 *
 * Reuses ProbSharpe (DSR), Pbo (CSCV gate), BlockBootstrap (CI). Pure +
 * unit-tested: null entries are ineligible; planted edge ranks; larger fieldN
 * raises the bar.
 */
typedef LeaderboardCtx = {
	/** Leaderboard-wide field size (submissions in category). Feeds DSR nTrials. */
	fieldN:Int,
	?minTrades:Int,
	/** Assigned evaluation seeds (v1 substrate); informational for callers. */
	?seedSet:Array<Int>,
	/**
	 * Account-level submission count for this author (anti-flood). Combined with
	 * fieldN via `effectiveTrials` — flooding raises the author's own bar.
	 */
	?accountTrials:Int,
	?nBoot:Int,
	?bootSeed:Int,
	/** CI must exclude this on the positive side (default 0). */
	?nullValue:Float
}

typedef LeaderboardEntryIn = {
	returns:Array<Float>,
	trades:Int,
	/** CSCV PBO; null/NaN → ineligible (honest: can't claim non-overfit). */
	?pbo:Null<Float>,
	/**
	 * Per-seed lower-CI skill (assigned seed-set). When present, rankStat =
	 * median of these; seedsPassed = count > null.
	 */
	?seedCiLos:Array<Float>,
	/** Override ctx.accountTrials for this entry. */
	?accountTrials:Int,
	?id:String,
	?label:String,
	?verdict:String,
	?author:String,
	?category:String
}

typedef LeaderboardScoreOut = {
	eligible:Bool,
	reason:String,
	/** Lower-CI skill (or median across seeds) — higher = better among eligible. */
	rankStat:Float,
	/** DSR at nTrials = effectiveTrials(fieldN, accountTrials). */
	dsrDeflated:Float,
	pbo:Float,
	ciLo:Float,
	ciHi:Float,
	trades:Int,
	seedsPassed:Int,
	nTrials:Int,
	id:Null<String>,
	label:Null<String>,
	verdict:Null<String>,
	author:Null<String>
}

typedef LeaderboardRanked = {
	/** Eligible entries sorted by rankStat descending (rank 1 = best). */
	wall:Array<{rank:Int, score:LeaderboardScoreOut}>,
	/** Ineligible — shown in "didn't make the wall", never rank 9999. */
	failed:Array<LeaderboardScoreOut>,
	fieldN:Int,
	eligibleCount:Int
}

class LeaderboardScore {
	public static inline var SCHEMA = "mederos.leaderboardScore.v1";
	public static inline var MIN_TRADES_DEFAULT = 20;

	/**
	 * Effective DSR trials: field size N plus account flood penalty.
	 * First submission → fieldN; each additional account submission raises the bar.
	 */
	public static function effectiveTrials(fieldN:Int, accountTrials:Int):Int {
		var n = fieldN < 1 ? 1 : fieldN;
		var a = accountTrials < 1 ? 1 : accountTrials;
		// max(field, account) already rises with either; add (account-1) so
		// flooding a small field still hurts the flooder specifically.
		var t = n + (a > 1 ? a - 1 : 0);
		return t < 1 ? 1 : t;
	}

	/** Evaluate one entry against the board context. */
	public static function evaluate(entry:LeaderboardEntryIn, ctx:LeaderboardCtx):LeaderboardScoreOut {
		var minTrades = ctx.minTrades != null ? ctx.minTrades : MIN_TRADES_DEFAULT;
		var nBoot = ctx.nBoot != null ? ctx.nBoot : 200;
		var bootSeed = ctx.bootSeed != null ? ctx.bootSeed : musescript.repro.ReproStamp.DEFAULT_SEED;
		var nullValue = ctx.nullValue != null ? ctx.nullValue : 0.0;
		var acct = entry.accountTrials != null
			? entry.accountTrials
			: (ctx.accountTrials != null ? ctx.accountTrials : 1);
		var nTrials = effectiveTrials(ctx.fieldN, acct);

		var returns = entry.returns != null ? entry.returns : [];
		var trades = entry.trades;
		var pboRaw:Null<Float> = entry.pbo;
		var pbo = pboRaw != null && Math.isFinite(pboRaw) ? pboRaw : Math.NaN;

		var dsr = returns.length >= 3 ? ProbSharpe.dsr(returns, nTrials) : 0.0;
		var ci = BlockBootstrap.sharpeCi(returns, bootSeed, nBoot);
		var ciLo = ci.lo;
		var ciHi = ci.hi;

		var seedLos = entry.seedCiLos != null
			? [for (x in entry.seedCiLos) if (Math.isFinite(x)) x]
			: [];
		var seedsPassed = 0;
		var rankStat:Float;
		if (seedLos.length > 0) {
			for (x in seedLos) if (x > nullValue) seedsPassed++;
			rankStat = median(seedLos);
		} else {
			seedsPassed = Math.isFinite(ciLo) && ciLo > nullValue ? 1 : 0;
			rankStat = Math.isFinite(ciLo) ? ciLo : Math.NEGATIVE_INFINITY;
		}

		var reason = "";
		var eligible = true;

		if (trades < minTrades) {
			eligible = false;
			reason = 'trades=$trades < minTrades=$minTrades';
		} else if (!(dsr > 0)) {
			eligible = false;
			reason = 'DSR(fieldN=${ctx.fieldN},acct=$acct)=${fmt(dsr)} ≤ 0';
		} else if (!Math.isFinite(pbo)) {
			eligible = false;
			reason = "PBO unavailable — can't claim non-overfit";
		} else if (!(pbo < 0.5)) {
			eligible = false;
			reason = 'PBO=${fmt(pbo)} ≥ 0.5 (overfit selection)';
		} else if (!(Math.isFinite(rankStat) && rankStat > nullValue)) {
			eligible = false;
			reason = seedLos.length > 0
				? 'median seed CI lo=${fmt(rankStat)} does not beat null'
				: 'Sharpe CI lo=${fmt(ciLo)} does not exclude null';
		} else {
			reason = 'eligible DSR=${fmt(dsr)} rankStat=${fmt(rankStat)} trials=$nTrials';
		}

		return {
			eligible: eligible,
			reason: reason,
			rankStat: rankStat,
			dsrDeflated: dsr,
			pbo: pbo,
			ciLo: ciLo,
			ciHi: ciHi,
			trades: trades,
			seedsPassed: seedsPassed,
			nTrials: nTrials,
			id: entry.id,
			label: entry.label,
			verdict: entry.verdict,
			author: entry.author
		};
	}

	/**
	 * Rank a field: evaluate all → eligible sorted by rankStat desc → wall;
	 * ineligible go to `failed` (never assigned a vanity low rank).
	 * `ctx.fieldN` should be the category field size (typically entries.length).
	 */
	public static function rank(entries:Array<LeaderboardEntryIn>, ctx:LeaderboardCtx):LeaderboardRanked {
		var fieldN = ctx.fieldN > 0 ? ctx.fieldN : (entries != null ? entries.length : 1);
		if (fieldN < 1) fieldN = 1;
		var baseCtx:LeaderboardCtx = {
			fieldN: fieldN,
			minTrades: ctx.minTrades,
			seedSet: ctx.seedSet,
			accountTrials: ctx.accountTrials,
			nBoot: ctx.nBoot,
			bootSeed: ctx.bootSeed,
			nullValue: ctx.nullValue
		};

		var wallScores:Array<LeaderboardScoreOut> = [];
		var failed:Array<LeaderboardScoreOut> = [];
		if (entries != null) {
			for (e in entries) {
				var score = evaluate(e, baseCtx);
				if (score.eligible) wallScores.push(score);
				else failed.push(score);
			}
		}

		wallScores.sort((a, b) -> {
			if (a.rankStat > b.rankStat) return -1;
			if (a.rankStat < b.rankStat) return 1;
			// Tie-break: higher deflated DSR, then more seeds passed.
			if (a.dsrDeflated > b.dsrDeflated) return -1;
			if (a.dsrDeflated < b.dsrDeflated) return 1;
			if (a.seedsPassed > b.seedsPassed) return -1;
			if (a.seedsPassed < b.seedsPassed) return 1;
			return 0;
		});

		var wall = [];
		for (i in 0...wallScores.length) {
			wall.push({ rank: i + 1, score: wallScores[i] });
		}

		return {
			wall: wall,
			failed: failed,
			fieldN: fieldN,
			eligibleCount: wall.length
		};
	}

	public static function scoreToDyn(s:LeaderboardScoreOut):Dynamic {
		return {
			schema: SCHEMA,
			eligible: s.eligible,
			reason: s.reason,
			rankStat: fin(s.rankStat),
			dsrDeflated: fin(s.dsrDeflated),
			pbo: fin(s.pbo),
			ciLo: fin(s.ciLo),
			ciHi: fin(s.ciHi),
			trades: s.trades,
			seedsPassed: s.seedsPassed,
			nTrials: s.nTrials,
			id: s.id,
			label: s.label,
			verdict: s.verdict,
			author: s.author
		};
	}

	public static function rankToDyn(r:LeaderboardRanked):Dynamic {
		return {
			schema: SCHEMA + ".rank",
			fieldN: r.fieldN,
			eligibleCount: r.eligibleCount,
			wall: [for (w in r.wall) { rank: w.rank, score: scoreToDyn(w.score) }],
			failed: [for (f in r.failed) scoreToDyn(f)]
		};
	}

	static function median(xs:Array<Float>):Float {
		if (xs.length == 0) return Math.NaN;
		var sorted = xs.copy();
		sorted.sort((a, b) -> a < b ? -1 : a > b ? 1 : 0);
		var m = Std.int(sorted.length / 2);
		return (sorted.length % 2 == 0) ? 0.5 * (sorted[m - 1] + sorted[m]) : sorted[m];
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 10000) / 10000);
	}

	static function fin(x:Float):Null<Float> {
		return Math.isFinite(x) ? x : null;
	}
}

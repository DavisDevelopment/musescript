package musescript.evo.rigor;

import musescript.evo.Fitness;
import musescript.evo.FitnessResult;
import musescript.harness.Metrics;

/**
 * Honest Backtest / Truth Report data contract (Initiative 1).
 *
 * Every IDE-facing backtest MUST surface this (or an equivalent JSON blob from
 * `toDyn` / `toJson`) — a Sharpe without an honest verdict is a product bug.
 *
 * Built from the hardened instrument: min-trades, DSR (trials-aware), PBO,
 * purge/embargo OOS hold, and beats-null vs a null baseline scored with the
 * Initiative 1.4 exemption (`Fitness.scoreNullBaseline`).
 *
 * Does not replace `OosVerdict` (GO/NO-GO for evo CLIs); this is the richer
 * traffic-light surface for Strategy Studio.
 */
typedef TruthReportOpts = {
	?minTrades:Int,
	?nTrials:Int,
	?bootSeed:Int,
	?nBoot:Int,
	?psrGate:Float,
	?pbo:Null<Float>,
	?purgeEmbargoApplied:Bool,
	?embargoBars:Int,
	?oosHeld:Bool,
	/** Null-baseline total return (equity end/start − 1); optional, for return-bar compare. */
	?nullReturn:Null<Float>,
	/** Strategy total return; optional companion to nullReturn. */
	?strategyReturn:Null<Float>,
	/** Initiative 4.2 — primary experiment seed (defaults to bootSeed / 42). */
	?seed:Int,
	/** Initiative 4.2 — equity bit-digest for shareable re-verification. */
	?equityDigest:Null<String>,
	/** Initiative 4.2 — fill-sequence digest (`FillHash`). */
	?fillDigest:Null<String>,
	/** Initiative 4.2 — execution profile / backend labels for ReproStamp. */
	?profile:String,
	?backend:String
}

class TruthReport {
	public var verdict:TruthVerdict;
	public var beatsNull:Bool;
	public var sharpe:Float;
	public var dsr:Float;
	public var psr:Float;
	public var pbo:Null<Float>;
	public var nTrials:Int;
	public var trades:Int;
	public var minTrades:Int;
	public var minTradesPassed:Bool;
	public var oosHeld:Bool;
	public var purgeEmbargoApplied:Bool;
	public var embargoBars:Int;
	public var nullSharpe:Float;
	public var nullReturn:Null<Float>;
	public var strategyReturn:Null<Float>;
	public var ciLo:Float;
	public var ciHi:Float;
	public var threshold:Float;
	/** Plain-language failure / caution reasons for the UI drill-down. */
	public var reasons:Array<String>;
	/** Per-gate pass flags for traffic-light drill-down. */
	public var gates:{
		minTrades:Bool,
		ciExcludesZero:Bool,
		dsr:Bool,
		beatsNull:Bool,
		pbo:Bool,
		oosHeld:Bool
	};
	/** Initiative 4.2 — seed stamp for shareable / re-runnable Truth Reports. */
	public var seed:Int;
	public var bootSeed:Int;
	public var equityDigest:Null<String>;
	public var fillDigest:Null<String>;
	/** `ReproStamp.toJson()` — embed under Truth Report share cards. */
	public var repro:Null<Dynamic>;

	public function new() {
		verdict = TruthVerdict.CoinFlip;
		beatsNull = false;
		sharpe = Math.NaN;
		dsr = Math.NaN;
		psr = Math.NaN;
		pbo = null;
		nTrials = 1;
		trades = 0;
		minTrades = Fitness.defaultMinTrades;
		minTradesPassed = false;
		oosHeld = false;
		purgeEmbargoApplied = false;
		embargoBars = 0;
		nullSharpe = Math.NaN;
		nullReturn = null;
		strategyReturn = null;
		ciLo = Math.NaN;
		ciHi = Math.NaN;
		threshold = 0;
		reasons = [];
		gates = {
			minTrades: false, ciExcludesZero: false, dsr: false,
			beatsNull: false, pbo: true, oosHeld: false
		};
		seed = musescript.repro.ReproStamp.DEFAULT_SEED;
		bootSeed = musescript.repro.ReproStamp.DEFAULT_SEED;
		equityDigest = null;
		fillDigest = null;
		repro = null;
	}

	/**
	 * Build a Truth Report from OOS strategy returns + trade count + null baseline Sharpe.
	 * `nTrials` defaults to `TrialsSession.effectiveTrials()` when omitted.
	 */
	public static function evaluate(
		returns:Array<Float>,
		trades:Int,
		nullSharpe:Float,
		?opts:TruthReportOpts
	):TruthReport {
		var r = new TruthReport();
		var minTrades = opts != null && opts.minTrades != null ? opts.minTrades : Fitness.defaultMinTrades;
		var nTrials = opts != null && opts.nTrials != null
			? opts.nTrials
			: TrialsSession.effectiveTrials();
		if (nTrials < 1) nTrials = 1;
		var bootSeed = opts != null && opts.bootSeed != null ? opts.bootSeed : 42;
		var nBoot = opts != null && opts.nBoot != null ? opts.nBoot : 200;
		var psrGate = opts != null && opts.psrGate != null ? opts.psrGate : 0.95;
		var seed = opts != null && opts.seed != null ? opts.seed : bootSeed;

		r.minTrades = minTrades;
		r.nTrials = nTrials;
		r.trades = trades;
		r.nullSharpe = nullSharpe;
		r.seed = seed;
		r.bootSeed = bootSeed;
		r.equityDigest = opts != null ? opts.equityDigest : null;
		r.fillDigest = opts != null ? opts.fillDigest : null;
		r.repro = musescript.repro.ReproStamp.make({
			seed: seed,
			bootSeed: bootSeed,
			profile: opts != null && opts.profile != null ? opts.profile : "truth-report",
			backend: opts != null && opts.backend != null ? opts.backend : "js"
		}).toJson();
		if (opts != null) {
			if (opts.pbo != null) r.pbo = opts.pbo;
			if (opts.purgeEmbargoApplied == true) r.purgeEmbargoApplied = true;
			if (opts.embargoBars != null) r.embargoBars = opts.embargoBars;
			if (opts.oosHeld == true) r.oosHeld = true;
			if (opts.nullReturn != null) r.nullReturn = opts.nullReturn;
			if (opts.strategyReturn != null) r.strategyReturn = opts.strategyReturn;
		}

		r.sharpe = Metrics.sharpe(returns, 0.0);
		r.psr = ProbSharpe.psr(returns, 0.0);
		r.dsr = ProbSharpe.dsr(returns, nTrials);
		r.threshold = ProbSharpe.expectedMaxSr(nTrials, 1.0);
		var ci = BlockBootstrap.sharpeCi(returns, bootSeed, nBoot);
		r.ciLo = ci.lo;
		r.ciHi = ci.hi;

		var minOk = trades >= minTrades;
		var ciOk = BlockBootstrap.excludesNull(ci, 0.0);
		var dsrOk = r.dsr >= psrGate;
		var beats = Math.isFinite(r.sharpe) && Math.isFinite(nullSharpe) && r.sharpe > nullSharpe;
		// Optional return bar when both returns provided (Initiative 1.4 alternate compare).
		if (!beats && r.nullReturn != null && r.strategyReturn != null
			&& Math.isFinite(r.nullReturn) && Math.isFinite(r.strategyReturn)) {
			beats = r.strategyReturn > r.nullReturn;
		}
		var pboOk = r.pbo == null || !Pbo.isOverfit(r.pbo);
		var oosOk = r.oosHeld || r.purgeEmbargoApplied; // host may mark either

		r.minTradesPassed = minOk;
		r.beatsNull = beats && minOk;
		r.gates = {
			minTrades: minOk,
			ciExcludesZero: ciOk,
			dsr: dsrOk,
			beatsNull: beats,
			pbo: pboOk,
			oosHeld: oosOk
		};

		// Plain-language reasons (order = priority for UI).
		if (!minOk) {
			r.reasons.push(
				'Only $trades trade${trades == 1 ? "" : "s"} — need at least $minTrades for a trustworthy Sharpe. '
				+ 'A 1-trade "great Sharpe" is luck, not skill.');
		}
		if (!ciOk) {
			r.reasons.push(
				'Block-bootstrap Sharpe CI [${fmt(ci.lo)}, ${fmt(ci.hi)}] still includes zero — '
				+ 'edge is not distinguishable from noise.');
		}
		if (!dsrOk) {
			var srShow = fmt(r.sharpe);
			var dsrShow = fmt(r.dsr);
			if (nTrials > 1) {
				r.reasons.push(
					'Your Sharpe of $srShow deflates to DSR=$dsrShow once we account for the '
					+ '$nTrials variants tried this session (SR₀≈${fmt(r.threshold)}) — that looks like noise-mining.');
			} else {
				r.reasons.push(
					'Deflated Sharpe (DSR=$dsrShow) is below the gate ($psrGate) — sample does not support a real edge.');
			}
		}
		if (minOk && !beats) {
			r.reasons.push(
				'OOS Sharpe (${fmt(r.sharpe)}) does not beat the null baseline (${fmt(nullSharpe)})'
				+ (r.nullReturn != null ? ' / return bar' : '') + '.');
		}
		if (r.pbo != null && !pboOk) {
			r.reasons.push(
				'PBO=${fmt(r.pbo)} ≥ 0.5 — probability of backtest overfitting says selection is no better than chance.');
		}
		if (!r.purgeEmbargoApplied && !r.oosHeld) {
			r.reasons.push(
				'OOS hold with purge/embargo was not marked — IDE should pass purgeEmbargoApplied or oosHeld.');
		}

		r.verdict = classify(r, nTrials, psrGate);
		if (r.verdict == TruthVerdict.Robust && r.reasons.length == 0) {
			r.reasons.push(
				'Cleared min-trades, DSR (trials=$nTrials), CI-excludes-zero, and beats-null gates.');
		}
		return r;
	}

	/**
	 * Convenience: build from a strategy `FitnessResult` + null-baseline result.
	 * Null baseline is scored with `scoreNullBaseline` (1.4 exemption); its raw
	 * Sharpe is used for the beats-null compare.
	 */
	public static function fromFitness(
		strategy:FitnessResult,
		nullBaseline:FitnessResult,
		?opts:TruthReportOpts
	):TruthReport {
		var rets = strategy.ok && strategy.equity != null
			? Metrics.returnsFromEquity(strategy.equity)
			: [];
		var nullSr = nullBaseline.ok && Math.isFinite(nullBaseline.sharpe)
			? nullBaseline.sharpe
			: Math.NaN;
		var nullScore = Fitness.scoreNullBaseline(nullBaseline);
		var o:TruthReportOpts = {
			minTrades: opts != null ? opts.minTrades : null,
			nTrials: opts != null ? opts.nTrials : null,
			bootSeed: opts != null ? opts.bootSeed : null,
			nBoot: opts != null ? opts.nBoot : null,
			psrGate: opts != null ? opts.psrGate : null,
			pbo: opts != null ? opts.pbo : null,
			purgeEmbargoApplied: opts != null ? opts.purgeEmbargoApplied : null,
			embargoBars: opts != null ? opts.embargoBars : null,
			oosHeld: opts != null ? opts.oosHeld : null,
			nullReturn: opts != null ? opts.nullReturn : null,
			strategyReturn: opts != null ? opts.strategyReturn : null,
			seed: opts != null ? opts.seed : null,
			equityDigest: opts != null && opts.equityDigest != null
				? opts.equityDigest
				: (strategy.equity != null ? musescript.repro.EquityDigest.of(strategy.equity) : null),
			fillDigest: opts != null && opts.fillDigest != null
				? opts.fillDigest
				: musescript.evo.FillHash.of(strategy.fills),
			profile: opts != null ? opts.profile : null,
			backend: opts != null && opts.backend != null ? opts.backend : strategy.backend
		};
		if (o.strategyReturn == null && strategy.ok && strategy.finalEquity > 0)
			o.strategyReturn = strategy.finalEquity / 100000.0 - 1.0;
		if (o.nullReturn == null && nullBaseline.ok && nullBaseline.finalEquity > 0)
			o.nullReturn = nullBaseline.finalEquity / 100000.0 - 1.0;
		var report = evaluate(rets, strategy.ok ? strategy.trades : 0, nullSr, o);
		if (!strategy.ok) {
			report.verdict = TruthVerdict.CoinFlip;
			report.reasons.unshift('Strategy evaluation failed'
				+ (strategy.error != null ? ': ${strategy.error}' : '.'));
		}
		if (!nullBaseline.ok || !Math.isFinite(nullScore)) {
			report.reasons.push('Null baseline evaluation was invalid — beats-null gate is inconclusive.');
		}
		return report;
	}

	static function classify(r:TruthReport, nTrials:Int, psrGate:Float):TruthVerdict {
		var g = r.gates;
		if (!g.minTrades) return TruthVerdict.CoinFlip;
		if (r.pbo != null && Pbo.isOverfit(r.pbo)) return TruthVerdict.Overfit;
		// Trials-aware overfit: PSR would clear but DSR collapses under many trials.
		if (nTrials > 1 && !g.dsr && r.psr >= psrGate) return TruthVerdict.Overfit;
		if (!g.ciExcludesZero || !g.beatsNull || !g.dsr) return TruthVerdict.CoinFlip;
		// Soft caution: elevated but sub-threshold PBO, or OOS not explicitly held.
		if ((r.pbo != null && r.pbo >= 0.35) || !g.oosHeld) return TruthVerdict.Fragile;
		return TruthVerdict.Robust;
	}

	/** JSON-safe anonymous object for IDE / WASM bridge. */
	public function toDyn():Dynamic {
		return {
			verdict: (verdict : String),
			beatsNull: beatsNull,
			sharpe: finiteOrNull(sharpe),
			dsr: finiteOrNull(dsr),
			psr: finiteOrNull(psr),
			pbo: pbo != null && Math.isFinite(pbo) ? pbo : null,
			nTrials: nTrials,
			trades: trades,
			minTrades: minTrades,
			minTradesPassed: minTradesPassed,
			oosHeld: oosHeld,
			purgeEmbargoApplied: purgeEmbargoApplied,
			embargoBars: embargoBars,
			nullSharpe: finiteOrNull(nullSharpe),
			nullReturn: nullReturn != null && Math.isFinite(nullReturn) ? nullReturn : null,
			strategyReturn: strategyReturn != null && Math.isFinite(strategyReturn) ? strategyReturn : null,
			ciLo: finiteOrNull(ciLo),
			ciHi: finiteOrNull(ciHi),
			threshold: finiteOrNull(threshold),
			reasons: reasons.copy(),
			gates: {
				minTrades: gates.minTrades,
				ciExcludesZero: gates.ciExcludesZero,
				dsr: gates.dsr,
				beatsNull: gates.beatsNull,
				pbo: gates.pbo,
				oosHeld: gates.oosHeld
			},
			seed: seed,
			bootSeed: bootSeed,
			equityDigest: equityDigest,
			fillDigest: fillDigest,
			repro: repro
		};
	}

	public function toJson(?pretty:Bool):String {
		return haxe.Json.stringify(toDyn(), pretty == true ? "  " : null);
	}

	public static function parse(json:String):TruthReport {
		return fromDyn(haxe.Json.parse(json));
	}

	public static function fromDyn(o:Dynamic):TruthReport {
		var r = new TruthReport();
		if (o == null) return r;
		r.verdict = o.verdict != null ? (o.verdict : TruthVerdict) : TruthVerdict.CoinFlip;
		r.beatsNull = o.beatsNull == true;
		r.sharpe = num(o.sharpe);
		r.dsr = num(o.dsr);
		r.psr = num(o.psr);
		r.pbo = o.pbo != null ? num(o.pbo) : null;
		r.nTrials = o.nTrials != null ? Std.int(o.nTrials) : 1;
		r.trades = o.trades != null ? Std.int(o.trades) : 0;
		r.minTrades = o.minTrades != null ? Std.int(o.minTrades) : Fitness.defaultMinTrades;
		r.minTradesPassed = o.minTradesPassed == true;
		r.oosHeld = o.oosHeld == true;
		r.purgeEmbargoApplied = o.purgeEmbargoApplied == true;
		r.embargoBars = o.embargoBars != null ? Std.int(o.embargoBars) : 0;
		r.nullSharpe = num(o.nullSharpe);
		r.nullReturn = o.nullReturn != null ? num(o.nullReturn) : null;
		r.strategyReturn = o.strategyReturn != null ? num(o.strategyReturn) : null;
		r.ciLo = num(o.ciLo);
		r.ciHi = num(o.ciHi);
		r.threshold = num(o.threshold);
		r.reasons = o.reasons != null ? [for (x in (o.reasons : Array<Dynamic>)) Std.string(x)] : [];
		r.seed = o.seed != null ? Std.int(o.seed) : musescript.repro.ReproStamp.DEFAULT_SEED;
		r.bootSeed = o.bootSeed != null ? Std.int(o.bootSeed) : r.seed;
		r.equityDigest = o.equityDigest != null ? Std.string(o.equityDigest) : null;
		r.fillDigest = o.fillDigest != null ? Std.string(o.fillDigest) : null;
		r.repro = o.repro;
		if (o.gates != null) {
			r.gates = {
				minTrades: o.gates.minTrades == true,
				ciExcludesZero: o.gates.ciExcludesZero == true,
				dsr: o.gates.dsr == true,
				beatsNull: o.gates.beatsNull == true,
				pbo: o.gates.pbo != false,
				oosHeld: o.gates.oosHeld == true
			};
		}
		return r;
	}

	static function num(v:Dynamic):Float {
		if (v == null) return Math.NaN;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float);
		var p = Std.parseFloat(Std.string(v));
		return p;
	}

	static function finiteOrNull(x:Float):Null<Float> {
		return Math.isFinite(x) ? x : null;
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 10000) / 10000);
	}
}

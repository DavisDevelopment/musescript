package musescript.evo.rigor;

/**
 * Initiative 5.1 — Strategy Report Card.
 *
 * Serializable scoreboard built **only** from a Truth Report (and optional
 * SeedRobustness / UniverseRobustness aggregates). Every performance number
 * routes through the hardened instrument — never invent metrics here.
 *
 * Landed surface: single-tape Truth Report + optional seed-robustness sweep.
 * Per-instrument / universe rows are extension points (`instruments`,
 * `universeRobustness.status = "pending"` until the host supplies them).
 */
typedef SeedRobustnessSlot = {
	/** "go" | "no-go" | "pending" | "skipped" */
	var status:String;
	var go:Bool;
	var median:Float;
	var max:Float;
	var threshold:Float;
	var n:Int;
	var note:String;
}

typedef UniverseRobustnessSlot = {
	/** "go" | "no-go" | "pending" | "single-tape" */
	var status:String;
	var go:Bool;
	var singleName:Bool;
	var passed:Int;
	var total:Int;
	var names:Array<String>;
	var note:String;
}

typedef InstrumentRow = {
	var name:String;
	var metric:Float;
	var go:Bool;
}

typedef ReportCardOpts = {
	/** Pre-computed seed metrics (e.g. OOS Sharpe per seed). */
	?seedMetrics:Array<Float>,
	?seedThreshold:Float,
	/** Per-instrument metrics for universe robustness. */
	?instruments:Array<InstrumentRow>,
	?universeThreshold:Float,
	?universeMinPass:Int,
	?universeMinPassRate:Float,
	/** Strategy / tape labels for Studio display. */
	?strategyLabel:String,
	?tape:String
}

class ReportCard {
	public static inline var SCHEMA = "mederos.reportCard.v1";

	public var schema:String;
	public var verdict:TruthVerdict;
	/** Strategy Sharpe − null Sharpe (skill / capture vs null). */
	public var skillVsNull:Float;
	public var beatsNull:Bool;
	public var strategySharpe:Float;
	public var nullSharpe:Float;
	/** Strategy return − null return when both known. */
	public var profitVsBaseline:Null<Float>;
	public var strategyReturn:Null<Float>;
	public var nullReturn:Null<Float>;
	public var seedRobustness:SeedRobustnessSlot;
	public var universeRobustness:UniverseRobustnessSlot;
	public var instruments:Array<InstrumentRow>;
	public var gates:{
		minTrades:Bool,
		ciExcludesZero:Bool,
		dsr:Bool,
		beatsNull:Bool,
		pbo:Bool,
		oosHeld:Bool
	};
	public var trades:Int;
	public var nTrials:Int;
	public var seed:Int;
	public var equityDigest:Null<String>;
	public var fillDigest:Null<String>;
	public var strategyLabel:Null<String>;
	public var tape:Null<String>;
	public var reasons:Array<String>;
	/** Embedded Truth Report dyn (honesty drill-down). */
	public var truthReport:Null<Dynamic>;

	public function new() {
		schema = SCHEMA;
		verdict = TruthVerdict.CoinFlip;
		skillVsNull = Math.NaN;
		beatsNull = false;
		strategySharpe = Math.NaN;
		nullSharpe = Math.NaN;
		profitVsBaseline = null;
		strategyReturn = null;
		nullReturn = null;
		seedRobustness = pendingSeed("Seed-robustness not swept yet — call MuseRuntime.seedRobustnessSweep or pass seedMetrics.");
		universeRobustness = singleTapeUniverse();
		instruments = [];
		gates = {
			minTrades: false, ciExcludesZero: false, dsr: false,
			beatsNull: false, pbo: true, oosHeld: false
		};
		trades = 0;
		nTrials = 1;
		seed = musescript.repro.ReproStamp.DEFAULT_SEED;
		equityDigest = null;
		fillDigest = null;
		strategyLabel = null;
		tape = null;
		reasons = [];
		truthReport = null;
	}

	/** Build a Report Card from an evaluated Truth Report (+ optional robustness inputs). */
	public static function fromTruthReport(tr:TruthReport, ?opts:ReportCardOpts):ReportCard {
		var c = new ReportCard();
		if (tr == null) {
			c.reasons.push("No Truth Report — cannot build an honest Report Card.");
			return c;
		}
		c.verdict = tr.verdict;
		c.strategySharpe = tr.sharpe;
		c.nullSharpe = tr.nullSharpe;
		c.beatsNull = tr.beatsNull;
		c.skillVsNull = finiteDiff(tr.sharpe, tr.nullSharpe);
		c.strategyReturn = tr.strategyReturn;
		c.nullReturn = tr.nullReturn;
		if (tr.strategyReturn != null && tr.nullReturn != null
			&& Math.isFinite(tr.strategyReturn) && Math.isFinite(tr.nullReturn)) {
			c.profitVsBaseline = tr.strategyReturn - tr.nullReturn;
		}
		c.gates = {
			minTrades: tr.gates.minTrades,
			ciExcludesZero: tr.gates.ciExcludesZero,
			dsr: tr.gates.dsr,
			beatsNull: tr.gates.beatsNull,
			pbo: tr.gates.pbo,
			oosHeld: tr.gates.oosHeld
		};
		c.trades = tr.trades;
		c.nTrials = tr.nTrials;
		c.seed = tr.seed;
		c.equityDigest = tr.equityDigest;
		c.fillDigest = tr.fillDigest;
		c.reasons = tr.reasons.copy();
		c.truthReport = tr.toDyn();

		if (opts != null) {
			if (opts.strategyLabel != null) c.strategyLabel = opts.strategyLabel;
			if (opts.tape != null) c.tape = opts.tape;
			if (opts.seedMetrics != null && opts.seedMetrics.length > 0) {
				var thr = opts.seedThreshold != null ? opts.seedThreshold : 0.0;
				c.seedRobustness = fromSeedVerdict(SeedRobustness.verdict(opts.seedMetrics, thr));
			}
			if (opts.instruments != null && opts.instruments.length > 0) {
				c.instruments = [for (r in opts.instruments) {
					name: r.name, metric: r.metric, go: r.go
				}];
				var uThr = opts.universeThreshold != null ? opts.universeThreshold : 0.0;
				var minPass = opts.universeMinPass != null ? opts.universeMinPass : 2;
				var minRate = opts.universeMinPassRate != null ? opts.universeMinPassRate : 0.5;
				var perName = [for (r in c.instruments) { name: r.name, metric: r.metric }];
				c.universeRobustness = fromUniverseVerdict(
					UniverseRobustness.verdict(perName, uThr, minPass, minRate)
				);
			}
		}
		return c;
	}

	/** JSON-safe object for IDE / WASM bridge. */
	public function toDyn():Dynamic {
		return {
			schema: schema,
			verdict: (verdict : String),
			skillVsNull: finiteOrNull(skillVsNull),
			beatsNull: beatsNull,
			strategySharpe: finiteOrNull(strategySharpe),
			nullSharpe: finiteOrNull(nullSharpe),
			profitVsBaseline: profitVsBaseline != null && Math.isFinite(profitVsBaseline)
				? profitVsBaseline : null,
			strategyReturn: strategyReturn != null && Math.isFinite(strategyReturn)
				? strategyReturn : null,
			nullReturn: nullReturn != null && Math.isFinite(nullReturn) ? nullReturn : null,
			seedRobustness: {
				status: seedRobustness.status,
				go: seedRobustness.go,
				median: finiteOrNull(seedRobustness.median),
				max: finiteOrNull(seedRobustness.max),
				threshold: finiteOrNull(seedRobustness.threshold),
				n: seedRobustness.n,
				note: seedRobustness.note
			},
			universeRobustness: {
				status: universeRobustness.status,
				go: universeRobustness.go,
				singleName: universeRobustness.singleName,
				passed: universeRobustness.passed,
				total: universeRobustness.total,
				names: universeRobustness.names.copy(),
				note: universeRobustness.note
			},
			instruments: [for (r in instruments) {
				name: r.name,
				metric: finiteOrNull(r.metric),
				go: r.go
			}],
			gates: {
				minTrades: gates.minTrades,
				ciExcludesZero: gates.ciExcludesZero,
				dsr: gates.dsr,
				beatsNull: gates.beatsNull,
				pbo: gates.pbo,
				oosHeld: gates.oosHeld
			},
			trades: trades,
			nTrials: nTrials,
			seed: seed,
			equityDigest: equityDigest,
			fillDigest: fillDigest,
			strategyLabel: strategyLabel,
			tape: tape,
			reasons: reasons.copy(),
			truthReport: truthReport
		};
	}

	public function toJson(?pretty:Bool):String {
		return haxe.Json.stringify(toDyn(), pretty == true ? "  " : null);
	}

	public static function fromDyn(o:Dynamic):ReportCard {
		var c = new ReportCard();
		if (o == null) return c;
		var tr = o.truthReport != null
			? TruthReport.fromDyn(o.truthReport)
			: null;
		if (tr != null) {
			c = fromTruthReport(tr, {
				strategyLabel: o.strategyLabel != null ? Std.string(o.strategyLabel) : null,
				tape: o.tape != null ? Std.string(o.tape) : null
			});
		} else {
			c.verdict = o.verdict != null ? (o.verdict : TruthVerdict) : TruthVerdict.CoinFlip;
			c.skillVsNull = num(o.skillVsNull);
			c.beatsNull = o.beatsNull == true;
			c.strategySharpe = num(o.strategySharpe);
			c.nullSharpe = num(o.nullSharpe);
			c.profitVsBaseline = o.profitVsBaseline != null ? num(o.profitVsBaseline) : null;
			c.strategyReturn = o.strategyReturn != null ? num(o.strategyReturn) : null;
			c.nullReturn = o.nullReturn != null ? num(o.nullReturn) : null;
		}
		if (o.seedRobustness != null) {
			c.seedRobustness = {
				status: Std.string(o.seedRobustness.status != null ? o.seedRobustness.status : "pending"),
				go: o.seedRobustness.go == true,
				median: num(o.seedRobustness.median),
				max: num(o.seedRobustness.max),
				threshold: num(o.seedRobustness.threshold),
				n: o.seedRobustness.n != null ? Std.int(o.seedRobustness.n) : 0,
				note: o.seedRobustness.note != null ? Std.string(o.seedRobustness.note) : ""
			};
		}
		if (o.universeRobustness != null) {
			c.universeRobustness = {
				status: Std.string(o.universeRobustness.status != null
					? o.universeRobustness.status : "pending"),
				go: o.universeRobustness.go == true,
				singleName: o.universeRobustness.singleName == true,
				passed: o.universeRobustness.passed != null ? Std.int(o.universeRobustness.passed) : 0,
				total: o.universeRobustness.total != null ? Std.int(o.universeRobustness.total) : 0,
				names: o.universeRobustness.names != null
					? [for (x in (o.universeRobustness.names : Array<Dynamic>)) Std.string(x)] : [],
				note: o.universeRobustness.note != null ? Std.string(o.universeRobustness.note) : ""
			};
		}
		if (o.instruments != null) {
			c.instruments = [];
			for (x in (o.instruments : Array<Dynamic>)) {
				c.instruments.push({
					name: x.name != null ? Std.string(x.name) : "?",
					metric: num(x.metric),
					go: x.go == true
				});
			}
		}
		if (o.strategyLabel != null) c.strategyLabel = Std.string(o.strategyLabel);
		if (o.tape != null) c.tape = Std.string(o.tape);
		return c;
	}

	public static function fromSeedVerdict(v:{
		go:Bool, median:Float, max:Float, threshold:Float, n:Int
	}):SeedRobustnessSlot {
		return {
			status: v.n < 1 ? "skipped" : (v.go ? "go" : "no-go"),
			go: v.go,
			median: v.median,
			max: v.max,
			threshold: v.threshold,
			n: v.n,
			note: v.n < 1
				? "No finite seed metrics."
				: (v.go
					? 'Median metric ${fmt(v.median)} clears ${fmt(v.threshold)} across ${v.n} seeds (max=${fmt(v.max)}).'
					: 'Median ${fmt(v.median)} ≤ ${fmt(v.threshold)} across ${v.n} seeds — max=${fmt(v.max)} would cherry-pick.')
		};
	}

	public static function fromUniverseVerdict(v:{
		go:Bool, singleName:Bool, passed:Int, total:Int, threshold:Float, names:Array<String>
	}):UniverseRobustnessSlot {
		var status = v.singleName ? "single-tape" : (v.go ? "go" : "no-go");
		var note = if (v.singleName)
			"Single-tape / single-name — universe robustness not proven. Pass instruments[] to extend.";
		else if (v.go)
			'Passed ${v.passed}/${v.total} names (threshold ${fmt(v.threshold)}).';
		else
			'Only ${v.passed}/${v.total} names cleared ${fmt(v.threshold)} — not universe-robust.';
		return {
			status: status,
			go: v.go,
			singleName: v.singleName,
			passed: v.passed,
			total: v.total,
			names: v.names.copy(),
			note: note
		};
	}

	static function pendingSeed(note:String):SeedRobustnessSlot {
		return {
			status: "pending", go: false, median: Math.NaN, max: Math.NaN,
			threshold: 0, n: 0, note: note
		};
	}

	static function singleTapeUniverse():UniverseRobustnessSlot {
		return {
			status: "single-tape", go: false, singleName: true,
			passed: 0, total: 1, names: [],
			note: "Single-tape Report Card — pass instruments[] for universe-robustness."
		};
	}

	static function finiteDiff(a:Float, b:Float):Float {
		if (!Math.isFinite(a) || !Math.isFinite(b)) return Math.NaN;
		return a - b;
	}

	static function num(v:Dynamic):Float {
		if (v == null) return Math.NaN;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float);
		return Std.parseFloat(Std.string(v));
	}

	static function finiteOrNull(x:Float):Null<Float> {
		return Math.isFinite(x) ? x : null;
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 10000) / 10000);
	}
}

package musescript.evo.rigor;

/**
 * Initiative 5.2 — Honest Ledger entry contract.
 *
 * A running record of what the user's strategies actually did OOS — GOs and
 * NO-GOs equally. muse-script owns the serializable entry shape; the IDE
 * persists the list (localStorage / session). Honest NO-GOs are the moat.
 */
typedef HonestLedgerEntry = {
	var schema:String;
	var id:String;
	/** ISO-8601 timestamp (host-supplied; Haxe may leave null for IDE fill). */
	var at:Null<String>;
	var disposition:LedgerDisposition;
	var verdict:TruthVerdict;
	var beatsNull:Bool;
	var sharpe:Null<Float>;
	var dsr:Null<Float>;
	var nullSharpe:Null<Float>;
	var skillVsNull:Null<Float>;
	var profitVsBaseline:Null<Float>;
	var trades:Int;
	var nTrials:Int;
	var seed:Int;
	var equityDigest:Null<String>;
	var fillDigest:Null<String>;
	var strategyLabel:Null<String>;
	var tape:Null<String>;
	var gates:{
		minTrades:Bool,
		ciExcludesZero:Bool,
		dsr:Bool,
		beatsNull:Bool,
		pbo:Bool,
		oosHeld:Bool
	};
	var reasons:Array<String>;
}

class HonestLedger {
	public static inline var ENTRY_SCHEMA = "mederos.honestLedger.v1.entry";
	public static inline var LIST_SCHEMA = "mederos.honestLedger.v1";

	/** Map TruthVerdict → disposition (Fragile = caution GO; Coin-flip/Overfit = NO-GO). */
	public static function dispositionOf(verdict:TruthVerdict):LedgerDisposition {
		return switch (verdict) {
			case TruthVerdict.Robust: LedgerDisposition.Go;
			case TruthVerdict.Fragile: LedgerDisposition.Caution;
			case TruthVerdict.Overfit | TruthVerdict.CoinFlip: LedgerDisposition.NoGo;
		}
	}

	/** Build a ledger entry from a Truth Report (+ optional Report Card fields). */
	public static function entryFromTruth(
		tr:TruthReport,
		?meta:{
			?at:String,
			?id:String,
			?strategyLabel:String,
			?tape:String,
			?skillVsNull:Float,
			?profitVsBaseline:Float
		}
	):HonestLedgerEntry {
		var skill:Null<Float> = null;
		var profit:Null<Float> = null;
		if (meta != null && meta.skillVsNull != null && Math.isFinite(meta.skillVsNull))
			skill = meta.skillVsNull;
		else if (Math.isFinite(tr.sharpe) && Math.isFinite(tr.nullSharpe))
			skill = tr.sharpe - tr.nullSharpe;
		if (meta != null && meta.profitVsBaseline != null && Math.isFinite(meta.profitVsBaseline))
			profit = meta.profitVsBaseline;
		else if (tr.strategyReturn != null && tr.nullReturn != null
			&& Math.isFinite(tr.strategyReturn) && Math.isFinite(tr.nullReturn))
			profit = tr.strategyReturn - tr.nullReturn;

		var id = meta != null && meta.id != null ? meta.id : makeId(tr);
		return {
			schema: ENTRY_SCHEMA,
			id: id,
			at: meta != null ? meta.at : null,
			disposition: dispositionOf(tr.verdict),
			verdict: tr.verdict,
			beatsNull: tr.beatsNull,
			sharpe: Math.isFinite(tr.sharpe) ? tr.sharpe : null,
			dsr: Math.isFinite(tr.dsr) ? tr.dsr : null,
			nullSharpe: Math.isFinite(tr.nullSharpe) ? tr.nullSharpe : null,
			skillVsNull: skill,
			profitVsBaseline: profit,
			trades: tr.trades,
			nTrials: tr.nTrials,
			seed: tr.seed,
			equityDigest: tr.equityDigest,
			fillDigest: tr.fillDigest,
			strategyLabel: meta != null ? meta.strategyLabel : null,
			tape: meta != null ? meta.tape : null,
			gates: {
				minTrades: tr.gates.minTrades,
				ciExcludesZero: tr.gates.ciExcludesZero,
				dsr: tr.gates.dsr,
				beatsNull: tr.gates.beatsNull,
				pbo: tr.gates.pbo,
				oosHeld: tr.gates.oosHeld
			},
			reasons: tr.reasons.length > 3 ? tr.reasons.slice(0, 3) : tr.reasons.copy()
		};
	}

	public static function entryFromReportCard(card:ReportCard, ?at:String, ?id:String):HonestLedgerEntry {
		var tr = card.truthReport != null
			? TruthReport.fromDyn(card.truthReport)
			: null;
		if (tr == null) {
			tr = new TruthReport();
			tr.verdict = card.verdict;
			tr.beatsNull = card.beatsNull;
			tr.sharpe = card.strategySharpe;
			tr.nullSharpe = card.nullSharpe;
			tr.trades = card.trades;
			tr.nTrials = card.nTrials;
			tr.seed = card.seed;
			tr.equityDigest = card.equityDigest;
			tr.fillDigest = card.fillDigest;
			tr.gates = card.gates;
			tr.reasons = card.reasons;
		}
		var meta:{
			?at:String, ?id:String, ?strategyLabel:String, ?tape:String,
			?skillVsNull:Float, ?profitVsBaseline:Float
		} = {
			at: at,
			id: id,
			strategyLabel: card.strategyLabel,
			tape: card.tape
		};
		if (Math.isFinite(card.skillVsNull)) meta.skillVsNull = card.skillVsNull;
		if (card.profitVsBaseline != null && Math.isFinite(card.profitVsBaseline))
			meta.profitVsBaseline = card.profitVsBaseline;
		return entryFromTruth(tr, meta);
	}

	/** JSON-safe entry object. */
	public static function entryToDyn(e:HonestLedgerEntry):Dynamic {
		return {
			schema: e.schema,
			id: e.id,
			at: e.at,
			disposition: (e.disposition : String),
			verdict: (e.verdict : String),
			beatsNull: e.beatsNull,
			sharpe: e.sharpe,
			dsr: e.dsr,
			nullSharpe: e.nullSharpe,
			skillVsNull: e.skillVsNull,
			profitVsBaseline: e.profitVsBaseline,
			trades: e.trades,
			nTrials: e.nTrials,
			seed: e.seed,
			equityDigest: e.equityDigest,
			fillDigest: e.fillDigest,
			strategyLabel: e.strategyLabel,
			tape: e.tape,
			gates: {
				minTrades: e.gates.minTrades,
				ciExcludesZero: e.gates.ciExcludesZero,
				dsr: e.gates.dsr,
				beatsNull: e.gates.beatsNull,
				pbo: e.gates.pbo,
				oosHeld: e.gates.oosHeld
			},
			reasons: e.reasons.copy()
		};
	}

	/** Wrap entries for IDE persistence (`mederos.honestLedger.v1`). */
	public static function listToDyn(entries:Array<HonestLedgerEntry>):Dynamic {
		return {
			schema: LIST_SCHEMA,
			count: entries.length,
			goCount: countDisp(entries, LedgerDisposition.Go),
			cautionCount: countDisp(entries, LedgerDisposition.Caution),
			noGoCount: countDisp(entries, LedgerDisposition.NoGo),
			entries: [for (e in entries) entryToDyn(e)]
		};
	}

	static function countDisp(entries:Array<HonestLedgerEntry>, d:LedgerDisposition):Int {
		var n = 0;
		for (e in entries) if (e.disposition == d) n++;
		return n;
	}

	static function makeId(tr:TruthReport):String {
		var dig = tr.equityDigest != null ? tr.equityDigest : "nodigest";
		return 'tr-${tr.seed}-${tr.trades}-${dig}';
	}
}

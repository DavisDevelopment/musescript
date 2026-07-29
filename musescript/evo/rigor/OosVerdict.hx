package musescript.evo.rigor;

import musescript.harness.Metrics;

/**
 * Honest OOS verdict combining min-trade gate, DSR, trials correction, and
 * block-bootstrap CI. Used by `[ew-host OOS]` and standing controls.
 */
class OosVerdict {
	public static function evaluate(
		returns:Array<Float>,
		trades:Int,
		buyHoldSharpe:Float,
		?opts:{
			?minTrades:Int,
			?nTrials:Int,
			?bootSeed:Int,
			?nBoot:Int,
			?psrGate:Float
		}
	):{
		go:Bool,
		label:String,
		trades:Int,
		sharpe:Float,
		dsr:Float,
		psr:Float,
		nTrials:Int,
		threshold:Float,
		ciLo:Float,
		ciHi:Float,
		reason:String,
		/** Initiative 4.2 — bootstrap seed used for CI (re-runnable Truth Report). */
		bootSeed:Int
	} {
		var minTrades = opts != null && opts.minTrades != null ? opts.minTrades : 20;
		var nTrials = opts != null && opts.nTrials != null ? opts.nTrials : 1;
		var bootSeed = opts != null && opts.bootSeed != null ? opts.bootSeed : musescript.repro.ReproStamp.DEFAULT_SEED;
		var nBoot = opts != null && opts.nBoot != null ? opts.nBoot : 200;
		var psrGate = opts != null && opts.psrGate != null ? opts.psrGate : 0.95;

		var sharpe = Metrics.sharpe(returns, 0.0);
		var psr = ProbSharpe.psr(returns, 0.0);
		var dsr = ProbSharpe.dsr(returns, nTrials);
		var ci = BlockBootstrap.sharpeCi(returns, bootSeed, nBoot);
		var sr0 = ProbSharpe.expectedMaxSr(nTrials, 1.0);

		if (trades < minTrades) {
			return mk(false, "NO-GO", trades, sharpe, dsr, psr, nTrials, sr0, ci, bootSeed,
				'trades=$trades < minTrades=$minTrades');
		}
		if (!BlockBootstrap.excludesNull(ci, 0.0)) {
			return mk(false, "NO-GO", trades, sharpe, dsr, psr, nTrials, sr0, ci, bootSeed,
				'Sharpe CI [${fmt(ci.lo)}, ${fmt(ci.hi)}] does not exclude 0');
		}
		if (!(dsr >= psrGate)) {
			return mk(false, "NO-GO", trades, sharpe, dsr, psr, nTrials, sr0, ci, bootSeed,
				'DSR=${fmt(dsr)} < gate=$psrGate (trials=$nTrials, SR0≈${fmt(sr0)})');
		}
		if (!(sharpe > buyHoldSharpe)) {
			return mk(false, "NO-GO", trades, sharpe, dsr, psr, nTrials, sr0, ci, bootSeed,
				'OOS Sharpe=${fmt(sharpe)} ≤ buyHold=${fmt(buyHoldSharpe)}');
		}
		return mk(true, "BEATS", trades, sharpe, dsr, psr, nTrials, sr0, ci, bootSeed,
			'DSR=${fmt(dsr)} CI=[${fmt(ci.lo)}, ${fmt(ci.hi)}] trials=$nTrials');
	}

	static function mk(
		go:Bool, label:String, trades:Int, sharpe:Float, dsr:Float, psr:Float,
		nTrials:Int, threshold:Float, ci:{lo:Float, hi:Float, point:Float}, bootSeed:Int, reason:String
	) {
		return {
			go: go, label: label, trades: trades, sharpe: sharpe, dsr: dsr, psr: psr,
			nTrials: nTrials, threshold: threshold, ciLo: ci.lo, ciHi: ci.hi,
			bootSeed: bootSeed, reason: reason
		};
	}

	static function fmt(x:Float):String {
		if (!Math.isFinite(x)) return "n/a";
		return Std.string(Math.round(x * 10000) / 10000);
	}

	/** Format a one-line `[ew-host OOS]` style verdict. */
	public static function formatLine(v:{
		go:Bool, label:String, trades:Int, sharpe:Float, dsr:Float, psr:Float,
		nTrials:Int, threshold:Float, ciLo:Float, ciHi:Float, reason:String
	}, extra:String = ""):String {
		return '[ew-host OOS] trades=${v.trades} Sharpe=${fmt(v.sharpe)} DSR=${fmt(v.dsr)}'
			+ ' CI=[${fmt(v.ciLo)}, ${fmt(v.ciHi)}] trials=${v.nTrials} SR0≈${fmt(v.threshold)}'
			+ ' => ${v.label}' + (extra != "" ? ' | ' + extra : '') + ' (' + v.reason + ')';
	}
}

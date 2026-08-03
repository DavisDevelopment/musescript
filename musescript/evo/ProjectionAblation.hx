package musescript.evo;

import musescript.harness.Bar;
import musescript.evo.nma.NmaCreditBank;

/**
 * Module-aware credit for projection/manager co-evolution (PROJECTION_COEVOLUTION_PLAN.md §8 P4).
 *
 * Ablate each REFERENCED projection (replace every `SProj(name, *)` leaf with uninformative
 * `SPrice("close")`), re-score the policy, and treat `Δ = baseline − ablated` as how much the
 * manager actually *uses* that forecast. Deposit positive Δ into `NmaCreditBank` under
 * `"proj:"+name` so variation can protect load-bearing projections. A skillful-but-unused
 * forecast earns ~0 ablation credit and is prunable.
 *
 * Trading score only — never folds `projScore` into Δ (selection story stays MAP-Elites skill
 * axis + trading fitness inside the cell).
 *
 * «χρῆσις πιστοῖ, οὐ μαντεία μόνη.»
 */
class ProjectionAblation {
	/** Credit-bank key for one projection name. */
	public static inline function bankKey(name:String):String return 'proj:$name';

	/**
	 * Genome with every `SProj(ablateName, *)` rewritten to `SPrice("close")` — the forecast
	 * channel is removed; the policy still typechecks and runs.
	 */
	public static function ablate(g:StrategyGenome, ablateName:String):StrategyGenome {
		function ws(n:SeriesNode):SeriesNode {
			return switch (n) {
				case SPrice(f): SPrice(f);
				case SInd(name, field, window, src):
					SInd(name, field, window, src != null ? ws(src) : null);
				case SProj(name, _): name == ablateName ? SPrice("close") : n;
				case SPanel(a, b, c, d): SPanel(a, b, c, d);
			};
		}
		function wsc(n:ScalarNode):ScalarNode {
			return switch (n) {
				case KConst(v): KConst(v);
				case KParam(i): KParam(i);
				case KFeature(name): KFeature(name);
				case KSeries(s): KSeries(ws(s));
				case KLookback(s, k): KLookback(ws(s), k);
				case KArith(op, a, b): KArith(op, wsc(a), wsc(b));
				case KHole(inner): KHole(wsc(inner));
			};
		}
		function wb(n:BoolNode):BoolNode {
			return switch (n) {
				case BCross(dir, a, b): BCross(dir, ws(a), ws(b));
				case BCmp(op, a, b): BCmp(op, wsc(a), wsc(b));
				case BTrend(dir, s, w): BTrend(dir, ws(s), w);
				case BAnd(a, b): BAnd(wb(a), wb(b));
				case BOr(a, b): BOr(wb(a), wb(b));
				case BNot(a): BNot(wb(a));
				case BHole(inner): BHole(wb(inner));
				case BFeature(src): BFeature(src);
			};
		}
		return {
			entryLong: wb(g.entryLong),
			entryShort: wb(g.entryShort),
			exitLong: wb(g.exitLong),
			exitShort: wb(g.exitShort),
			size: wsc(g.size),
			params: g.params,
			name: g.name,
			lineage: g.lineage,
			seedOrigin: g.seedOrigin,
			projections: g.projections,
			panelAction: g.panelAction
		};
	}

	/** Trading fitness used for ablation Δ (sharpe when ok, else −∞). */
	public static function tradingScore(fr:FitnessResult):Float {
		if (fr == null || !fr.ok || fr.bankrupt == true || fr.trades < 1)
			return Fitness.NEG_INF;
		if (!Math.isFinite(fr.sharpe))
			return Fitness.NEG_INF;
		return fr.sharpe;
	}

	/**
	 * Per-referenced-projection ablation Δ (`baseline − ablated`). Missing / unscored → omitted.
	 * `evalFn` defaults to `Fitness.evaluate(..., "js")`.
	 */
	public static function deltas(
		g:StrategyGenome, bars:Array<Bar>,
		?evalFn:StrategyGenome->FitnessResult
	):Map<String, Float> {
		var out:Map<String, Float> = new Map();
		var refs = ProjInline.referencedNames(g);
		if (!refs.keys().hasNext())
			return out;
		var eval = evalFn != null ? evalFn : function(gg:StrategyGenome) return Fitness.evaluate(gg, bars, "js");
		var base = tradingScore(eval(g));
		if (base == Fitness.NEG_INF)
			return out;
		for (name in refs.keys()) {
			var ab = tradingScore(eval(ablate(g, name)));
			if (ab == Fitness.NEG_INF)
				out.set(name, base); // ablating broke the policy ⇒ full baseline as credit
			else
				out.set(name, base - ab);
		}
		return out;
	}

	/** Deposit finite ablation Δ into `NmaCreditBank` (`proj:name`). */
	public static function deposit(
		g:StrategyGenome, bars:Array<Bar>,
		?evalFn:StrategyGenome->FitnessResult
	):Map<String, Float> {
		var d = deltas(g, bars, evalFn);
		for (name => delta in d) {
			if (Math.isFinite(delta))
				NmaCreditBank.deposit(bankKey(name), delta);
		}
		return d;
	}

	/**
	 * Seed / nudge `GrowthWeights` category `projRead` from `NmaCreditBank` (`proj:name` keys).
	 * Positive ablation means → higher grow probability for that name. Explore floor via
	 * `ensureTag` min weights. No-op when the bank has no `proj:` observations.
	 */
	public static function applyBankToTuner(tuner:GrowthWeights, ?names:Array<String>):Void {
		if (tuner == null) return;
		var keys:Array<String> = names != null ? names : [];
		if (keys.length == 0) {
			// Discover any warm proj:* keys via a small known dense set + bank probe.
			for (i in 0...8) {
				var n = 'proj_$i';
				if (NmaCreditBank.observations(bankKey(n)) > 0) keys.push(n);
			}
			if (NmaCreditBank.observations(bankKey("ew_0")) > 0) keys.push("ew_0");
		}
		for (name in keys) {
			var mean = NmaCreditBank.mean(bankKey(name));
			var n = NmaCreditBank.observations(bankKey(name));
			if (n < 1) continue;
			// Map mean Δ into (0.02, ~1]: floor explore, boost used/skillful channels.
			var w = 0.05 + Math.max(0.0, mean);
			if (w > 1.5) w = 1.5;
			tuner.ensureTag("projRead", name, w);
			// Also nudge via reward so adaptive loop sees the signal if enabled.
			tuner.reward("projRead", name, mean);
		}
	}

	/**
	 * Use-weights in [0,1] from ablation Δ: `max(0, Δ)` normalized to sum 1 (or uniform if all ≤0).
	 * For use-weighted skill aggregation (plan §6 / §8).
	 */
	public static function useWeights(deltas:Map<String, Float>):Map<String, Float> {
		var w:Map<String, Float> = new Map();
		var sum = 0.0;
		var names:Array<String> = [];
		for (name => d in deltas) {
			names.push(name);
			var u = Math.isFinite(d) && d > 0 ? d : 0.0;
			w.set(name, u);
			sum += u;
		}
		if (sum <= 0 && names.length > 0) {
			var u = 1.0 / names.length;
			for (n in names) w.set(n, u);
			return w;
		}
		if (sum > 0) {
			for (n in names) w.set(n, w.get(n) / sum);
		}
		return w;
	}
}

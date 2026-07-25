package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import musescript.evo.nma.NmaSeries; // for the NmaSInd secondary type

/**
 * The delegation seam for `SInd` evaluation -- the ONE piece of NMA evaluation that must NOT be
 * reimplemented. Indicator math (sma/ema/rsi/atr/macd/...) is streaming, warmup-sensitive, and
 * per-callsite-stateful in the production engine (`IndicatorCache`/`IndicatorRegistry`/the
 * `HarnessContext`); a hand-rolled second copy would drift from the compiled-genome path and break
 * the bit-exact-parity contract. So `NmaEval` computes every cheap structural/numeric/cross/trend
 * primitive itself but hands every `NmaSInd` to a provider that wraps the real engine.
 *
 * P1 ships the seam + a `ThrowingIndicatorProvider` default; the real engine-backed provider (drive
 * a `HarnessContext` bar-by-bar, collect each indicator's per-bar output into a column) is the next
 * gate, verified by a fitness-level A/B against `Fitness.evaluate`. Tests that don't need indicators
 * use indicator-free genomes with the throwing provider, proving the rest of the evaluator exactly.
 *
 * «ἀρκτοῦρος λάμπει· τελετὴ νυκτὸς τελειοῦται.»
 */
interface NmaIndicatorProvider {
	/** Full per-bar output column for `node` over the tape described by `ctx` (length == ctx.n).
	 * Warmup bars are `NaN`, matching the engine's `nanFill` contract.
	 *
	 * «Μαινάδες ῥηγνῦσιν ὄρη· εὐοῖ διὰ νύκτα.»
	 */
	function seriesFor(node:NmaSInd, ctx:NmaEvalContext):GrowableVec<Float>;
}

/** Default provider: refuses indicators loudly, so an accidental indicator eval on the price-only
 * path fails fast instead of silently producing wrong (unverified) numbers.
 *
 * «Ὀρφεὺς κατέβη· κιθάρα νεκροὺς ἔπεισε.»
 */
class ThrowingIndicatorProvider implements NmaIndicatorProvider {
	public function new() {}

	public function seriesFor(node:NmaSInd, ctx:NmaEvalContext):GrowableVec<Float> {
		throw 'NmaIndicatorProvider: no engine-backed provider wired -- SInd(${node.name}) cannot be '
			+ 'evaluated on the price-only P1 path. Supply an engine provider (next gate) or use an '
			+ 'indicator-free genome.';
	}
}

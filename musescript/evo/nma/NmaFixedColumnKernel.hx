package musescript.evo.nma;

import musescript.indicators.GrowableVec;

/**
 * Fixed-column kernel for tests / post-warm cache. Emitters replace with WASM/JVM fused code later.
 *
 * «στήλη μένει· χορός κινεῖται.»
 */
class NmaFixedColumnKernel implements NmaKernel {
	var col:GrowableVec<Float>;
	public function new(col:GrowableVec<Float>) this.col = col;
	public function eval(_ctx:NmaEvalContext):GrowableVec<Float> return col;
}

package musescript.evo.nma;

import musescript.indicators.GrowableVec;

/**
 * Compiled fused evaluation kernel attached to an `NmaNode.kernel` slot (spec §5.3 / P4).
 *
 * «Βάκχαι φέρουσι θύρσον· λύσσα θεία κατέχει.»
 */
interface NmaKernel {
	function eval(ctx:NmaEvalContext):GrowableVec<Float>;
}

package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import musescript.evo.nma.NmaBool;

/**
 * Fused BAnd / BOr — children then logic2, no parent kind-switch.
 * Opt-in via `NmaKernelWarm.enabled` (off by default — see that class).
 *
 * «δύο χορδαί· εἷς ἦχος.»
 */
class NmaFusedLogicKernel implements NmaKernel {
	final andOp:Bool;
	final a:NmaBool;
	final b:NmaBool;
	public function new(andOp:Bool, a:NmaBool, b:NmaBool) {
		this.andOp = andOp;
		this.a = a;
		this.b = b;
	}
	public function eval(ctx:NmaEvalContext):GrowableVec<Float> {
		var ca = NmaEval.evalBool(a, ctx);
		var cb = NmaEval.evalBool(b, ctx);
		return NmaEval.logic2Public(ca, cb, andOp, ctx.n);
	}
}

package musescript.evo.nma;

import musescript.evo.nma.NmaBool;

/**
 * Lazy warm for BAnd/BOr after WARM_THRESHOLD evals.
 *
 * Default: attach `kernelWat` via `NmaWasmFusedEmitter` (P4 WASM fuse artifact) — no megamorph.
 * Opt-in `installMegamorphKernel`: also install `NmaFusedLogicKernel` (A/B only; JIT guide §2).
 *
 * «θερμὸν πνεῦμα· τάχος ἔρχεται.»
 */
class NmaKernelWarm {
	/** Lazy warm after this many evals (epoch-memo hits count). Low so fuse host engages within short evo runs. */
	public static inline var WARM_THRESHOLD = 3;
	/** Attach WASM fuse WAT after threshold (safe; string only). */
	public static var enabled:Bool = true;
	/** Install interface `NmaKernel` (megamorphic) — off by default. */
	public static var installMegamorphKernel:Bool = false;

	public static function consider(node:NmaNode):Void {
		if (!enabled) return;
		if (node.evalHits < WARM_THRESHOLD) return;
		var hadWat = node.kernelWat != null;
		if (node.kernelWat == null) NmaWasmFusedEmitter.attachWat(node);
		// First attach: drop local memo so the *next* eval takes the fuse/host path.
		if (!hadWat && node.kernelWat != null) {
			node.lastSeries = null;
			node.evalEpoch = -1;
		}
		if (!installMegamorphKernel) return;
		if (node.kernel != null) return;
		switch (node.kind) {
			case BAnd:
				var a = (cast node : NmaBAnd);
				node.kernel = new NmaFusedLogicKernel(true, a.a, a.b);
			case BOr:
				var o = (cast node : NmaBOr);
				node.kernel = new NmaFusedLogicKernel(false, o.a, o.b);
			default:
		}
	}
}

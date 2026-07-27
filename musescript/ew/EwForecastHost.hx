package musescript.ew;

import musescript.harness.Bar;
import musescript.ew.ForecastCloud.ForecastCloudUtil;

/**
 * Host contract for EW (and later MCMC) forecast emission.
 *
 * Streaming indicators and NMA/evo ProjectionProviders implement or wrap this.
 * Implementations must be point-in-time causal: cloud at bar t uses data ≤ t only.
 * Hard rules are enforced inside the host; soft params may be supplied per call /
 * per genome — never as boolean gates on grammar.
 */
interface EwForecastHost {
	/** Optional soft-param pack id / hash for cache keys (null = process default). */
	public function phiKey():Null<String>;

	/**
	 * Rebuild / advance on the latest bar. Callers that stream should invoke once
	 * per bar; batch MCMC hosts may ignore and only answer `cloudAt`.
	 */
	public function onBar(bar:Bar, index:Int):Void;

	/** Projection cloud as-of bar index `t` (causal). */
	public function cloudAt(t:Int):ForecastCloud;

	/**
	 * Top-K discrete count masses for UQ / entropy (length ≤ kMax).
	 * Empty / null when host only emits a single preferred count.
	 */
	public function topCounts(t:Int, kMax:Int):Array<EwCountMass>;
}

/** One competing wave labeling with posterior / soft mass. */
typedef EwCountMass = {
	var label:String;
	var mass:Float;
	var score:Float;
	var invalidatePrice:Float;
	var nestScore:Float;
	var degree:Int;
}

/**
 * Stub host — returns empty clouds. Useful for compile/wiring tests until the
 * lattice or MCMC backend is bound under `musescript.ew`.
 */
class EwForecastHostStub implements EwForecastHost {
	public function new() {}

	public function phiKey():Null<String> return null;

	public function onBar(bar:Bar, index:Int):Void {}

	public function cloudAt(t:Int):ForecastCloud {
		return ForecastCloudUtil.empty(0);
	}

	public function topCounts(t:Int, kMax:Int):Array<EwCountMass> {
		return [];
	}
}

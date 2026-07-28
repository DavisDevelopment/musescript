package musescript.evo;

/**
 * One named forward projection a genome computes each bar — a forecast hypothesized to have a
 * patterned relationship to the future timeseries, exposed to the policy as a variable (a fan
 * reduction like `proj_0__p50`) and scored leakage-free against realized future values
 * (PROJECTION_COEVOLUTION_PLAN.md §2).
 *
 * Bundle-shaped from day one: `sampler` yields `1..samples` series. The deterministic point
 * projection is `PSPoint` with `samples == 1`; a Monte-Carlo fan is `PSNoise` with `samples > 1`.
 * A genome carrying no projections (`StrategyGenome.projections` null/absent) is byte-identical to a
 * projection-free genome — projections are additive and default-inert.
 */
typedef ProjectionDecl = {
	/** The identifier the policy references (dense: `proj_0`, `proj_1`, …). */
	var name:String;
	/** What future quantity this forecasts — fixes the scoring target. */
	var kind:ProjKind;
	/** `H` bars ahead this projection claims a relationship to. */
	var horizon:Int;
	/** The evolvable fan generator (`1..samples` series). */
	var sampler:ProjSampler;
	/** `K` — number of series in the fan. `1` ⇒ deterministic point projection. */
	var samples:Int;
	/** Deterministic Monte-Carlo seed, so the fan is stable across re-evaluations of the genome. */
	var seed:Int;
	/**
	 * Soft φ residual deltas for `PSHost` only (keys ⊆ `EwPhiParams` soft fields). Applied via
	 * `EwPhiParams.clone()` + `PhiParamsDump.applyMap` — never touch hard EW grammar.
	 * Null/absent ⇒ host uses process-default / shared pack.
	 */
	var ?phiDeltas:Map<String, Float>;
}

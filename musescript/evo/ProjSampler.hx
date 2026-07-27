package musescript.evo;

/**
 * The evolvable fan generator for a projection: produces `1..K` series — a Monte-Carlo fan
 * (PROJECTION_COEVOLUTION_PLAN.md §2). The deterministic single-series "thought" is simply `K = 1`
 * (`PSPoint`); a multi-path forecast is `PSNoise` with `K > 1`. Modelling both as one type means the
 * point projection is the degenerate instance of the fan, so nothing downstream (grammar, eval,
 * scoring) needs a separate code path for "is this a fan" — and multi-series never requires a schema
 * migration.
 *
 * Both variants are built from `≤ t` inputs only; "forward-looking" is a scoring interpretation, not
 * a data-access privilege (see `ProjKind`).
 */
enum ProjSampler {
	/**
	 * Deterministic single series (`K = 1`): a PIT-causal `SeriesNode`. Every fan reduction of a
	 * one-sample fan (`p50`, `mean`, a raw `sample_0`) is just this series; `spread` is 0.
	 */
	PSPoint(node:SeriesNode);

	/**
	 * `K` seeded Monte-Carlo draws: a `base` path, an evolved per-bar volatility scale `vol`, and a
	 * `NoiseModel`. Deterministic given the projection's `seed` (stable fan across the fitness pass,
	 * attribution ablations, and the champion re-check).
	 */
	PSNoise(base:SeriesNode, vol:ScalarNode, model:NoiseModel);
}

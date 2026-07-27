package musescript.evo;

/**
 * Noise process a `PSNoise` sampler uses to draw its Monte-Carlo fan
 * (PROJECTION_COEVOLUTION_PLAN.md §2). Every draw is CAUSAL — noise at bar `t` uses only the seed and
 * information `≤ t` (a block-bootstrap resamples PAST residuals, never future ones), so a fan can be
 * a forecast without ever peeking ahead.
 */
enum NoiseModel {
	/** Scaled i.i.d. normal. */
	NGaussian;
	/** Resample PAST return blocks of length `block` (≤ t) — the mobile ForwardSim default. */
	NBlockBootstrap(block:Int);
	/** Scaled Student-t with `dof` degrees of freedom (fatter tails than Gaussian). */
	NStudentT(dof:Int);
}

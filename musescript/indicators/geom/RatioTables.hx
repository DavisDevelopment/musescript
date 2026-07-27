package musescript.indicators.geom;

/**
 * Canonical ratio ladders shared by Fib facades, harmonics, and EW soft scores.
 * Tables are immutable; consumers copy into local scratch when mutating.
 */
class RatioTables {
	/** Classic retracement ratios (0..1 of a swing leg). */
	public static final RETRACE:Array<Float> = [
		0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0
	];

	/** Extension / projection multiples of a measured leg. */
	public static final EXTENSION:Array<Float> = [
		0.618, 1.0, 1.618, 2.618, 4.236
	];

	/** Golden-pocket band edges. */
	public static final GOLDEN_POCKET:Array<Float> = [0.618, 0.65];

	/** Fan / arc intermediate ratios. */
	public static final FAN:Array<Float> = [0.382, 0.5, 0.618];

	/** Harmonic AB=CD / XA windows — midpoints for soft scoring elsewhere. */
	public static final HARMONIC_AB_XA:Array<Float> = [0.382, 0.5, 0.618, 0.786, 0.886];
	public static final HARMONIC_BC_AB:Array<Float> = [0.382, 0.5, 0.618, 0.786, 0.886];
	public static final HARMONIC_CD_BC:Array<Float> = [1.13, 1.272, 1.414, 1.618, 2.0, 2.24, 2.618];
	/** Harmonic AD/XA windows — midpoints for soft scoring elsewhere. */
	public static final HARMONIC_AD_XA:Array<Float> = [0.618, 0.786, 0.886, 1.13, 1.272, 1.618];

	/**
	 * Elliott Wave φ-family (Ch3 Frost/Prechter) — mirrors EwPhiParams handbook defaults.
	 * Prefer EwPhiParams.current() at runtime so finetuned packs win.
	 */
	public static final EW_PHI_CORE:Array<Float> = [
		0.382, 0.5, 0.618, 0.786, 1.0, 1.272, 1.618, 2.0, 2.618, 4.236
	];
}

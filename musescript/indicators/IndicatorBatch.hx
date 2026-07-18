package musescript.indicators;

/**
 * `batch` is free for every `MuseIndicator` — ports Wickra's `BatchExt`
 * blanket impl (one `update()` loop, works for any indicator whatsoever)
 * rather than requiring a second, indicator-specific vectorized
 * implementation that could drift from the streaming one.
 */
class IndicatorBatch {
	/** Run `ind` over `inputs` in order; index i of the result is `ind.update(inputs[i])`. */
	public static function run<TIn, TOut>(ind:MuseIndicator<TIn, TOut>, inputs:Array<TIn>):Array<Null<TOut>> {
		return [for (x in inputs) ind.update(x)];
	}

	/**
	 * Same as `run`, but NaN-filled instead of null — convenient for the
	 * common scalar-output case where callers want a plain `Array<Float>`
	 * (matching MuseScript's own NaN-during-warmup convention elsewhere)
	 * without null-checking every element.
	 */
	public static function runNan(ind:MuseIndicator<Dynamic, Float>, inputs:Array<Dynamic>):Array<Float> {
		return [for (x in inputs) { var v = ind.update(x); v == null ? Math.NaN : v; }];
	}
}

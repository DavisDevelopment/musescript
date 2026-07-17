package musescript.harness;

typedef Bar = {
	var open:Float;
	var high:Float;
	var low:Float;
	var close:Float;
	var volume:Float;
	var time:Float;
	var index:Int;
	/** Optional auxiliary fields (e.g. fundamentals, signals). Pushed into
	 * per-name series CAUSALLY by HarnessContext.runBacktest — one value as
	 * each bar arrives, never preloaded (preloading the whole column would
	 * let bar t read future values through tail-indexed series lookups). */
	var ?data:Map<String, Float>;
}

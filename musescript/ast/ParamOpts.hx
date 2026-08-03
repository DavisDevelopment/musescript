package musescript.ast;

typedef ParamOpts = {
	var ?min:Float;
	var ?max:Float;
	var ?step:Float;
	/** Explicit discrete sweep list: `param fast = 8 { values: [8, 13, 21, 34] }`. When present it
	 * takes priority over min/max/step in the optimizer's grid (PlanRunner.gridValues) -- the only
	 * way to sweep a NON-uniform set (e.g. Fibonacci window lengths) that no fixed step can express. */
	var ?values:Array<Float>;
	var ?tune:String;
	/** Optional type annotation name: Series | Scalar | Bool | Window | Price */
	var ?ty:String;
}

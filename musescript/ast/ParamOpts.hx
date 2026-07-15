package musescript.ast;

typedef ParamOpts = {
	var ?min:Float;
	var ?max:Float;
	var ?step:Float;
	var ?tune:String;
	/** Optional type annotation name: Series | Scalar | Bool | Window | Price */
	var ?ty:String;
}

package musescript.compile;

/** Result of MuseCompiler.compileEx — exposes which backend ran. */
typedef CompileEx = {
	var fn:musescript.BarStrategyFn;
	var backend:String; // "js" | "wasm" | "haxe" | "interp"
	var emitted:Bool;
};

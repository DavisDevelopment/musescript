package musescript.harness;

/** Options for {@link DiagPack.emit}. */
typedef DiagPackOpts = {
	/** ACF max lag (default 20). */
	?maxLag:Int,
	/** Rolling lag-1 ACF window; 0/omit skips the strip (default 0). */
	?rollingWindow:Int,
	/** Chart label prefix (default `"diag"`). */
	?prefix:String,
	/** Emit kiss / underwater / ACF panels (default all true). */
	?kiss:Bool,
	?underwater:Bool,
	?acf:Bool,
	?colorEquity:String,
	?colorPeak:String,
	?colorDd:String,
	?colorAcf:String,
	?colorRoll:String
};

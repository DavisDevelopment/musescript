package musescript.builtins;

import musescript.kestrel.ProbCloudRuntime;

/**
 * MuseScript-facing wrappers over `ProbCloudRuntime` — thin closures,
 * installed the same way `GraphBuiltins` is. `probcloud_from_json` accepts
 * a JSON STRING (the output of `tools/kestrel_bridge.py`'s fit step, or any
 * hand-authored/cached cloud fixture) and parses it via `haxe.Json.parse`,
 * itself portable to every target this project compiles to (JS for web/
 * mobile, Python for backtest) — so QUERYING a cloud never needs the Python
 * bridge at all, only the initial (expensive, offline) fit does.
 */
class ProbCloudBuiltins {
	public static function install(vars:Map<String, Dynamic>):Void {
		vars.set("probcloud_from_json", fromJson);
		vars.set("probcloud_median", median);
		vars.set("probcloud_quantile", quantileAt);
		vars.set("probcloud_interval_low", intervalLow);
		vars.set("probcloud_interval_high", intervalHigh);
		vars.set("probcloud_iqr", iqr);
		vars.set("probcloud_width", width);
		vars.set("probcloud_conviction", conviction);
		vars.set("probcloud_skew", skew);
		vars.set("probcloud_expected_value", expectedValue);
		vars.set("probcloud_cdf", cdf);
		vars.set("probcloud_prob_below", probBelow);
		vars.set("probcloud_prob_above", probAbove);
		vars.set("probcloud_prob_between", probBetween);
		vars.set("probcloud_prob_up", probUp);
		vars.set("probcloud_is_calibrated", isCalibrated);
		vars.set("probcloud_trust_note", trustNote);
	}

	public static function fromJson(json:String):ProbCloudRuntime
		return ProbCloudRuntime.fromJson(haxe.Json.parse(json));

	public static function median(cloud:ProbCloudRuntime, symbol:String, ?h:Float):Float
		return cloud.median(symbol, h == null ? -1 : Std.int(h));

	public static function quantileAt(cloud:ProbCloudRuntime, symbol:String, level:Float, ?h:Float):Float
		return cloud.quantileAt(symbol, level, h == null ? -1 : Std.int(h));

	public static function intervalLow(cloud:ProbCloudRuntime, symbol:String, ?coverage:Float, ?h:Float):Float
		return cloud.intervalLow(symbol, coverage == null ? 0.9 : coverage, h == null ? -1 : Std.int(h));

	public static function intervalHigh(cloud:ProbCloudRuntime, symbol:String, ?coverage:Float, ?h:Float):Float
		return cloud.intervalHigh(symbol, coverage == null ? 0.9 : coverage, h == null ? -1 : Std.int(h));

	public static function iqr(cloud:ProbCloudRuntime, symbol:String, ?h:Float):Float
		return cloud.iqr(symbol, h == null ? -1 : Std.int(h));

	public static function width(cloud:ProbCloudRuntime, symbol:String, ?coverage:Float, ?h:Float):Float
		return cloud.width(symbol, coverage == null ? 0.9 : coverage, h == null ? -1 : Std.int(h));

	public static function conviction(cloud:ProbCloudRuntime, symbol:String, ?h:Float):Float
		return cloud.conviction(symbol, h == null ? -1 : Std.int(h));

	public static function skew(cloud:ProbCloudRuntime, symbol:String, ?h:Float):Float
		return cloud.skew(symbol, h == null ? -1 : Std.int(h));

	public static function expectedValue(cloud:ProbCloudRuntime, symbol:String, ?h:Float):Float
		return cloud.expectedValue(symbol, h == null ? -1 : Std.int(h));

	public static function cdf(cloud:ProbCloudRuntime, symbol:String, x:Float, ?h:Float):Float
		return cloud.cdf(symbol, x, h == null ? -1 : Std.int(h));

	public static function probBelow(cloud:ProbCloudRuntime, symbol:String, x:Float, ?h:Float):Float
		return cloud.probBelow(symbol, x, h == null ? -1 : Std.int(h));

	public static function probAbove(cloud:ProbCloudRuntime, symbol:String, x:Float, ?h:Float):Float
		return cloud.probAbove(symbol, x, h == null ? -1 : Std.int(h));

	public static function probBetween(cloud:ProbCloudRuntime, symbol:String, a:Float, b:Float, ?h:Float):Float
		return cloud.probBetween(symbol, a, b, h == null ? -1 : Std.int(h));

	public static function probUp(cloud:ProbCloudRuntime, symbol:String, ?h:Float):Float
		return cloud.probUp(symbol, h == null ? -1 : Std.int(h));

	public static function isCalibrated(cloud:ProbCloudRuntime):Bool
		return cloud.isCalibrated();

	public static function trustNote(cloud:ProbCloudRuntime):String
		return cloud.trustNote();
}

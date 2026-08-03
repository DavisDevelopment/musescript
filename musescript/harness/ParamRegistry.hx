package musescript.harness;

class ParamRegistry {
	var values:Map<String, Dynamic>;
	var opts:Map<String, {?min:Float, ?max:Float, ?step:Float, ?values:Array<Float>, ?tune:String}>;
	public function new() {
		values = new Map();
		opts = new Map();
	}
	public function register(name:String, value:Dynamic, ?min:Float, ?max:Float, ?step:Float, ?tune:String, ?sweepValues:Array<Float>):Void {
		if (!values.exists(name)) values.set(name, value);
		var prev = opts.get(name);
		opts.set(name, {
			min: min != null ? min : (prev != null ? prev.min : null),
			max: max != null ? max : (prev != null ? prev.max : null),
			step: step != null ? step : (prev != null ? prev.step : null),
			values: sweepValues != null ? sweepValues : (prev != null ? prev.values : null),
			tune: tune != null ? tune : (prev != null ? prev.tune : null)
		});
	}
	public function get(name:String):Dynamic return values.get(name);
	public function set(name:String, v:Dynamic):Void values.set(name, v);
	public function all():Map<String, Dynamic> return values;
	public function getOpts(name:String) return opts.get(name);
	public function names():Array<String> return [for (k in values.keys()) k];
}

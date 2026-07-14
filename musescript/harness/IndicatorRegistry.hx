package musescript.harness;

class IndicatorRegistry {
	var factories:Map<String, Dynamic>;
	public function new() factories = new Map();
	public function register(name:String, factory:Dynamic):Void factories.set(name, factory);
	public function get(name:String):Dynamic return factories.get(name);
}

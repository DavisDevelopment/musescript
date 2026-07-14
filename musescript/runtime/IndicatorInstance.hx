package musescript.runtime;

class IndicatorInstance {
	public var closure:FnClosure;
	public var state:Map<String, Dynamic>;
	public var id:String;

	public function new(closure:FnClosure, id:String) {
		this.closure = closure;
		this.id = id;
		this.state = new Map();
		closure.indicatorState = state;
	}

	public function getState(key:String, ?def:Dynamic):Dynamic {
		return state.exists(key) ? state.get(key) : def;
	}

	public function setState(key:String, v:Dynamic):Void {
		state.set(key, v);
	}
}

package musescript.runtime;

class IndicatorInstance {
	public var closure:FnClosure;
	public var state:Map<String, Dynamic>;
	public var id:String;

	/**
	 * Per-callsite state, keyed by the static id CallsiteIds.assign() stamps on each
	 * `EMeta("__cs", [id], call)` syntactic call site. Without this, every call to the
	 * same `@indicator` declaration -- regardless of which line/args called it --
	 * shared the ONE `state` map above, so `cmo(close, 14)` and `cmo(close, 20)` used
	 * in the same strategy would silently corrupt each other's running state (found
	 * empirically: two same-named calls with different args interleaved their output).
	 * `state` remains the fallback for the untagged/legacy path (a bare call not
	 * routed through the CallsiteIds-wrapped dispatch, e.g. dynamic `api.apply`).
	 */
	var perCallsite:Map<Int, Map<String, Dynamic>>;

	public function new(closure:FnClosure, id:String) {
		this.closure = closure;
		this.id = id;
		this.state = new Map();
		this.perCallsite = new Map();
		closure.indicatorState = state;
	}

	/** The state map to use for one call: per-callsite when tagged, the shared legacy map otherwise. */
	public function stateFor(callsiteId:Int):Map<String, Dynamic> {
		if (callsiteId < 0) return state;
		var m = perCallsite.get(callsiteId);
		if (m == null) {
			m = new Map();
			perCallsite.set(callsiteId, m);
		}
		return m;
	}

	public function getState(key:String, ?def:Dynamic):Dynamic {
		return state.exists(key) ? state.get(key) : def;
	}

	public function setState(key:String, v:Dynamic):Void {
		state.set(key, v);
	}
}

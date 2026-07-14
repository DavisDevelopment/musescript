package musescript.runtime;

/**
 * Per-invocation locals with parent chain for lexical lookup.
 */
class CallFrame {
	public var bindings:Map<String, Ref>;
	public var parent:Null<CallFrame>;
	public var depth:Int;
	public var name:String;

	public function new(?parent:CallFrame, ?name:String) {
		this.parent = parent;
		this.bindings = new Map();
		this.depth = parent == null ? 0 : parent.depth + 1;
		this.name = name != null ? name : "<anon>";
	}

	public function define(name:String, value:Dynamic):Ref {
		var r = new Ref(value);
		bindings.set(name, r);
		return r;
	}

	public function set(name:String, value:Dynamic):Bool {
		var r = resolve(name);
		if (r == null) return false;
		r.value = value;
		return true;
	}

	public function resolve(name:String):Null<Ref> {
		if (bindings.exists(name)) return bindings.get(name);
		if (parent != null) return parent.resolve(name);
		return null;
	}

	public function get(name:String):Dynamic {
		var r = resolve(name);
		return r == null ? null : r.value;
	}

	public function snapshot():CallFrame {
		var f = new CallFrame(parent, name);
		for (k => v in bindings) {
			f.bindings.set(k, new Ref(v.value));
		}
		f.depth = depth;
		return f;
	}
}

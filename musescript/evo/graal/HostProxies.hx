package musescript.evo.graal;

import java.NativeArray;
import musescript.evo.graal.Polyglot;

/** String-keyed member proxy (the `{ env: {...} }` import object shape). */
class EnvProxy implements ProxyObject {
	var members:Map<String, Dynamic>;

	public function new(members:Map<String, Dynamic>) {
		this.members = members;
	}

	public function getMember(key:String):Dynamic
		return members.get(key);

	public function hasMember(key:String):Bool
		return members.exists(key);

	public function getMemberKeys():Dynamic
		return new KeysProxy([for (k in members.keys()) k]);

	public function putMember(key:String, value:Value):Void {
		members.set(key, value);
	}
}

class KeysProxy implements ProxyArray {
	var keys:Array<String>;

	public function new(keys:Array<String>) {
		this.keys = keys;
	}

	public function get(index:haxe.Int64):Dynamic
		return keys[haxe.Int64.toInt(index)];

	public function set(index:haxe.Int64, value:Value):Void {}

	public function getSize():haxe.Int64
		return haxe.Int64.ofInt(keys.length);
}

/** Closure-backed host function exposed to WASM imports. */
class HostFn implements ProxyExecutable {
	var fn:NativeArray<Value>->Dynamic;

	public function new(fn:NativeArray<Value>->Dynamic) {
		this.fn = fn;
	}

	public function execute(arguments:NativeArray<Value>):Dynamic
		return fn(arguments);
}

package musescript.runtime;

/**
 * Mutable binding cell for CallFrame locals.
 */
class Ref {
	public var value:Dynamic;
	public function new(?value:Dynamic) {
		this.value = value;
	}
}

package musescript.runtime;

/** Legacy throw-style yield (doYield / uncaught yield outside collect mode). */
class YieldSignal {
	public var value:Dynamic;
	public function new(value:Dynamic) this.value = value;
}

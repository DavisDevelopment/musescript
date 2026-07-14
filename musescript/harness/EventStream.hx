package musescript.harness;

import musescript.runtime.StreamIter;

/**
 * Live / buffered event stream as MuseIter.
 */
class EventStream extends StreamIter {
	public var name:String;
	public function new(name:String, ?maxDepth:Int = 1024) {
		super(maxDepth);
		this.name = name;
	}
}

package musescript.runtime;

/**
 * Explicit call stack for reentrant / recursive MuseScript functions.
 */
class CallStack {
	public var frames:Array<CallFrame>;
	public var maxDepth:Int;

	public function new(?maxDepth:Int = 10000) {
		this.frames = [];
		this.maxDepth = maxDepth;
	}

	public function current():Null<CallFrame> {
		return frames.length == 0 ? null : frames[frames.length - 1];
	}

	public function push(frame:CallFrame):Void {
		if (frames.length >= maxDepth)
			throw 'MuseScript call stack overflow (maxDepth=$maxDepth)';
		frames.push(frame);
	}

	public function pop():Null<CallFrame> {
		return frames.pop();
	}

	public function depth():Int {
		return frames.length;
	}

	public function resolve(name:String):Null<Ref> {
		var cur = current();
		return cur == null ? null : cur.resolve(name);
	}
}

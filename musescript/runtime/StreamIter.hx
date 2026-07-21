package musescript.runtime;

/*
daddydaddydaddydaddydaddydaddydaddy c:
*/
class StreamIter implements MuseIter {
	public var buffer:Array<Dynamic>;
	public var maxDepth:Int;
	public var closed:Bool;

	var waiters:Array<Void->Void>;

	public function new(?maxDepth:Int = 1024) {
		this.buffer = [];
		this.maxDepth = maxDepth;
		this.closed = false;
		this.waiters = [];
	}

	public function push(v:Dynamic):Void {
		if (closed) return;
		if (buffer.length >= maxDepth) buffer.shift();
		buffer.push(v);
		flushWaiters();
	}

	inline public function end():Void {
		closed = true;
		flushWaiters();
	}

	inline function flushWaiters():Void {
		while (waiters.length > 0) waiters.shift()();
	}

	public function next():IterResult<Dynamic> {
		// Drain buffered values synchronously; once empty-and-closed we're done.
		// Otherwise defer: the resume closure is just next() again, which re-checks
		// the buffer/closed state whenever the driver next pumps us. (The old
		// `next_work_chunk` local was a verbatim re-implementation of this method.)
		if (buffer.length > 0)
			return Value(buffer.shift());
		if (closed)
			return Done;

		var self = this;
		return Await(function() return self.next());
	}
}

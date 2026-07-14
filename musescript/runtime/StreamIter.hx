package musescript.runtime;

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

	public function end():Void {
		closed = true;
		flushWaiters();
	}

	function flushWaiters():Void {
		while (waiters.length > 0) waiters.shift()();
	}

	public function next():IterResult<Dynamic> {
		if (buffer.length > 0) return Value(buffer.shift());
		if (closed) return Done;
		var self = this;
		return Await(function():IterResult<Dynamic> {
			if (self.buffer.length > 0) return Value(self.buffer.shift());
			if (self.closed) return Done;
			return Await(function() return self.next());
		});
	}
}

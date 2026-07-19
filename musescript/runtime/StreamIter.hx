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
		//TODO: it seems like maybe this could be simplified(?)
		if (buffer.length > 0) 
			return Value(buffer.shift());
		if (closed) 
			return Done;

		var self = this;
		function next_work_chunk():IterResult<Dynamic> {
			if (self.buffer.length > 0) 
				return Value(self.buffer.shift());
			if (self.closed) 
				return Done;
			
			return Await(function() return self.next());
		}

		return Await(next_work_chunk);
	}
}

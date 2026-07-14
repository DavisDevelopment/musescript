package musescript.harness;

/**
 * Local publish stub for examples and event-driven strategies — not a broker adapter.
 *
 * Pre-creates `orderFlow` and `ticks` streams; use `ensureStream` for others.
 * Optional session lifecycle (`start` / `stop` / `pump`) coordinates stream shutdown
 * without any network or background threads.
 */
class LiveHarness extends HarnessContext {
	var _running:Bool;
	var _sessionStarted:Bool;
	var _streamsDrained:Bool;

	/** Synthetic clock for stamped events (milliseconds or arbitrary units). */
	public var now:Float;

	/** Amount `advanceClock` adds when called without an argument. */
	public var clockStep:Float;

	/** When true, `publish` sets `ts` on events that lack one. */
	public var stampEvents:Bool;

	/** When true, each `publish` advances the synthetic clock. */
	public var autoAdvanceClock:Bool;

	public function new(?startTime:Float = 0, ?clockStep:Float = 1) {
		super();
		this.now = startTime;
		this.clockStep = clockStep;
		this.stampEvents = false;
		this.autoAdvanceClock = false;
		ensureStream("orderFlow");
		ensureStream("ticks");
	}

	public var isRunning(get, never):Bool;

	inline function get_isRunning():Bool return _running;

	/** Begin a live-publish session; reopens streams closed by a prior `pump`. */
	public function start():Void {
		if (_running) return;
		_running = true;
		_sessionStarted = true;
		_streamsDrained = false;
		reopenClosedStreams();
	}

	/** Mark the session stopped; call `pump` to end open streams. */
	public function stop():Void {
		if (!_running) return;
		_running = false;
	}

	/**
	 * Ends all streams once after `stop` (no-op if the session was never started).
	 * Idempotent until the next `start`.
	 */
	public function pump():Void {
		if (_sessionStarted && !_running && !_streamsDrained) {
			endStreams();
			_streamsDrained = true;
		}
	}

	public function ensureStream(name:String):EventStream {
		var s = eventStreams.get(name);
		if (s == null) {
			s = new EventStream(name);
			eventStreams.set(name, s);
		}
		return s;
	}

	public function publish(streamName:String, ev:Dynamic):Void {
		if (stampEvents) stampEvent(ev);
		if (autoAdvanceClock) advanceClock();
		ensureStream(streamName).push(ev);
		if (streamName == "orderFlow") eventLog.push(ev);
	}

	public function publishOrder(ev:Dynamic):Void publish("orderFlow", ev);

	public function publishTick(ev:Dynamic):Void publish("ticks", ev);

	public function publishMany(streamName:String, events:Array<Dynamic>):Void {
		for (e in events) publish(streamName, e);
	}

	public function publishOrders(events:Array<Dynamic>):Void publishMany("orderFlow", events);

	public function publishTicks(events:Array<Dynamic>):Void publishMany("ticks", events);

	public function advanceClock(?delta:Null<Float>):Void {
		now += delta != null ? delta : clockStep;
	}

	public function endStreams():Void {
		for (_ => s in eventStreams) s.end();
	}

	function reopenClosedStreams():Void {
		for (name => s in eventStreams) {
			if (s.closed) eventStreams.set(name, new EventStream(name));
		}
	}

	function stampEvent(ev:Dynamic):Void {
		if (ev == null || Reflect.hasField(ev, "ts")) return;
		Reflect.setField(ev, "ts", now);
	}
}

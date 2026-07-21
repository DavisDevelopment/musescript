package musescript.runtime;

/**
 * Runtime generator — implements MuseIter.
 *
 * ## Interpreter (MuseInterp) — eager collect
 * On the first next(), the interpreter runs the full generator body once with
 * collecting=true. Each yield appends to queue; execution continues (no real
 * suspend). Later next() calls only drain the queue. Works for finite generators;
 * infinite generators will hang or exhaust memory.
 *
 * ## Compiler (GeneratorLower) — state machine
 * Common shapes (e.g. while+yield range, sequential yields) are lowered at
 * compile time to plain functions returning {next} iterators — no Generator
 * instance and no yield opcodes in the emitted path.
 *
 * ## Stepped mode (pauseAfterYield)
 * Set pauseAfterYield=true and provide evalBody. Each yield/delegate pauses the
 * body until the next next(). MuseInterp does not use this yet; see INTERP HOOK
 * comments below. Tests and future CPS/IP evaluators can opt in.
 *
 * ## True suspend/resume
 * Requires MuseInterp (or another evaluator) to resume evalExpr from yield
 * points — CPS rewrite, bytecode IP, or similar. Generator exposes hooks only.
 */
class Generator implements MuseIter {
	public var closure:Null<FnClosure>;
	public var frame:Null<CallFrame>;
	public var done:Bool;
	public var started:Bool;
	public var collecting:Bool;
	/** When true, pushYield/delegateTo throw YieldPause instead of running on. */
	public var pauseAfterYield:Bool;
	/** True after evalBody returns without YieldPause (body finished). */
	public var bodyComplete:Bool;
	public var queue:Array<Dynamic>;
	/** Called to run or resume the generator body (see advanceBody). */
	public var evalBody:Null<Generator->Dynamic>;

	/** Delegated iterator to run in collect mode. */
	var delegated:Null<MuseIter>;

	/*
	we gon make ourselves a generator, sha
	*/
	public function new(?closure:FnClosure, ?frame:CallFrame) {
		this.closure = closure;
		this.frame = frame;
		this.done = false;
		this.started = false;
		this.collecting = false;
		this.pauseAfterYield = false;
		this.bodyComplete = false;
		this.queue = [];
		this.evalBody = null;
		this.delegated = null;
	}

	public function next():IterResult<Dynamic> {
		if (done) return Done;

		while (true) {
			if (delegated != null) {
				switch (delegated.next()) {
					case Done:
						delegated = null;
					case Value(v):
						return Value(v);
					case Await(r):
						// Resume THROUGH our own logic: when the delegated iter
						// finishes we must clear `delegated` and continue our body
						// (via next()), not hand the raw Await back and strand the
						// post-yield* continuation.
						return Await(function() return resumeDelegated(r()));
				}
			}

			if (queue.length > 0) 
				return Value(queue.shift());

			if (!bodyComplete) {
				advanceBody();
				continue;
			}

			done = true;
			return Done;
		}
	}

	/** Resolve a delegated-iterator Await at any depth: exhaustion clears the
	 * delegation and resumes our own body via next(); a value passes through; a
	 * nested Await recurses rather than escaping raw. Mirrors FlatMappedIter. */
	function resumeDelegated(r:IterResult<Dynamic>):IterResult<Dynamic> {
		return switch (r) {
			case Done:
				delegated = null;
				next();
			case Value(v):
				Value(v);
			case Await(cont):
				Await(function() return resumeDelegated(cont()));
		};
	}

	function advanceBody():Void {
		if (bodyComplete || evalBody == null) {
			if (evalBody == null) {
				bodyComplete = true;
			}
			return;
		}

		if (!started) 
			started = true;
		collecting = true;

		try {
			evalBody(this);
			bodyComplete = true;
		} 
		catch (_:GeneratorYieldPause) {
			// stepped pause — resume on next next()
		} 
		catch (y:YieldSignal) {
			// legacy throw-style yield — treat as single value
			queue.push(y.value);
			if (pauseAfterYield) bodyComplete = false;
			else bodyComplete = true;
		} 
		catch (e:Dynamic) {
			collecting = false;
			done = true;
			bodyComplete = true;
			throw e;
		}
		collecting = false;
	}

	public function pushYield(value:Dynamic):Void {
		queue.push(value);
		if (pauseAfterYield && collecting) {
			throw new GeneratorYieldPause();
		}
	}

	public static function doYield(value:Dynamic):Dynamic {
		throw new YieldSignal(value);
	}

	/** yield* — drain iter via next() before resuming own body (stepped mode). */
	public inline function delegateTo(iter:MuseIter):Void {
		delegated = iter;
		if (pauseAfterYield && collecting) {
			throw new GeneratorYieldPause();
		}
	}

	/** Finite values without evalBody — handy for tests and MuseIters.from. */
	public static inline function fromValues(values: Array<Dynamic>):Generator {
		var g = new Generator();
		g.queue = values != null ? values.copy() : [];
		g.started = true;
		g.bodyComplete = true;
		return g;
	}

	public static inline function empty():Generator {
		return fromValues([]);
	}

	public static inline function from(iter:MuseIter):Generator {
		var g = new Generator();
		g.delegated = iter;
		g.started = true;
		return g;
	}
	
	public static inline function fromHaxeIter(iter:Iterator<Dynamic>):Generator {
		var g = new Generator();
		g.delegated = new HaxeIterWrapper(iter);
		g.started = true;
		return g;
	}

	// INTERP HOOK: true suspend — evalBody should not run the whole body at once.
	// On Yield/EYield: activeGenerator.pushYield(v) (throws when pauseAfterYield).
	// On YieldStar/EYieldStar: activeGenerator.delegateTo(MuseIters.from(expr)) instead of
	// IterDriver.each (which eagerly drains nested iters in collect mode).
	// After delegateTo's iter returns Done, call evalBody again from the yield* resume point
	// (save IP / CPS continuation). Until then, Generator.next drains delegated first.
	// Set gen.pauseAfterYield = true when wiring evalBody for stepped interpretation.
}

/** Internal stepped-mode pause signal (see pauseAfterYield). */
private class GeneratorYieldPause {
	public function new() {}
}

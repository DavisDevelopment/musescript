package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.StrategyWasmRuntimeWat;
import musescript.builtins.TradeBuiltins;

/**
 * F2: shared linear-memory variable frame. Where F1 alone can only ESCALATE
 * a whole statement to `host_eval` when it touches a name an escape region
 * also touches, F2 gives boundary-crossing names a slot in shared WASM
 * memory (`StrategyWasmRuntimeWat`'s FRAME region) instead — both the native
 * WASM code and the escape interp thunk read/write the SAME offset, so the
 * crossing never needs to escalate at all. The load-bearing claim this suite
 * pins: a statement mix that F1 alone escalates ENTIRELY (see
 * musescript-enums-classes-rollout memory / TestHybridWasm's
 * `testEscapedAssignTaintsLaterNativeRead`, which hand-traced this exact
 * source escalating all 5 statements) now keeps every native-capable
 * statement (`sma`/`crossover`/`crossunder`/`long`/`flat`) NATIVE, with only
 * the genuinely-unsupported one (`str_contains`) as an escape region.
 */
class TestVariableFrame extends Test {
	function assertParity(source:String, feed:BarFeed):Void {
		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(source), feed);

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			TradeBuiltins.resetCrossState();
			var hybridHarness = new HarnessContext();
			Reflect.setField(hybridHarness, "feed", feed);
			var hybridResult = StrategyWasmBackend.compile(new MuseParser().parse(source))(hybridHarness);
			Assert.equals(interpResult.trades, hybridResult.trades);
			Assert.floatEquals(interpResult.finalEquity, hybridResult.finalEquity);
		}
		#end
	}

	static final BOUNDARY_SRC = '{
		@strategy("frame_boundary")
		@on(bar) {
			var flag = str_contains("bull", "bu");
			var fast = sma(close, 3);
			var slow = sma(close, 9);
			if (flag && crossover(fast, slow)) long();
			if (crossunder(fast, slow)) flat();
		}
	}';

	public function testOnlyGenuinelyUnsupportedStatementEscapes() {
		var prog = new MuseParser().parse(BOUNDARY_SRC);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		// Exactly ONE escape region (str_contains) — F1 alone escalated all 5
		// statements here (the whole chain, via the bidirectional taint
		// fixpoint); F2's framing must bring that down to just the one
		// statement that's inherently unsupported.
		Assert.equals(1, emitted.escapeRegions.length);
		Assert.isTrue(emitted.wat.indexOf("call $host_eval") >= 0);
		// The sma/crossover/crossunder calls are still natively emitted.
		Assert.isTrue(emitted.wat.indexOf("call $sma") >= 0);
		Assert.isTrue(emitted.wat.indexOf("call $crossover") >= 0);
		Assert.isTrue(emitted.wat.indexOf("call $crossunder") >= 0);
	}

	public function testBoundaryNameGetsFramed() {
		var prog = new MuseParser().parse(BOUNDARY_SRC);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isTrue(emitted.framedNames.exists("flag"));
		// Frame offset must land inside StrategyWasmRuntimeWat's reserved
		// FRAME region, not collide with any other memory area.
		var off = emitted.framedNames.get("flag");
		Assert.isTrue(off >= StrategyWasmRuntimeWat.FRAME_BASE);
		Assert.isTrue(off < StrategyWasmRuntimeWat.FRAME_BASE + StrategyWasmRuntimeWat.FRAME_BYTES);
	}

	public function testFramedBoundaryStaysParityCorrect() {
		assertParity(BOUNDARY_SRC, BarFeed.synthetic(300, 21));
	}

	/** A DIFFERENT tape/seed than the diagnostic run, to catch any hidden
	 * dependence on a specific bar sequence. */
	public function testFramedBoundaryParityOnAnotherTape() {
		assertParity(BOUNDARY_SRC, BarFeed.synthetic(180, 5));
	}

	/**
	 * Multiple independent boundary-crossing names in the SAME program each
	 * get their OWN frame slot (not aliased onto one another).
	 */
	public function testMultipleFramedNamesGetDistinctSlots() {
		var source = '{
			@strategy("frame_multi")
			@on(bar) {
				var a = str_contains("x", "x");
				var b = str_contains("y", "y");
				var fastA = sma(close, 3);
				var fastB = sma(close, 5);
				if (a && fastA > 0.0) long();
				if (b && fastB > 0.0) flat();
			}
		}';
		var prog = new MuseParser().parse(source);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isTrue(emitted.framedNames.exists("a"));
		Assert.isTrue(emitted.framedNames.exists("b"));
		Assert.isFalse(emitted.framedNames.get("a") == emitted.framedNames.get("b"));
		assertParity(source, BarFeed.synthetic(200, 11));
	}

	/**
	 * A name that never crosses the boundary (native-only end to end) must
	 * NOT be framed — framing is strictly for genuine crossings, not a
	 * blanket policy, so ordinary native locals keep using plain WASM
	 * `(local)`s.
	 */
	public function testPurelyNativeNameIsNotFramed() {
		var source = '{
			@strategy("frame_native_only")
			@on(bar) {
				var fast = sma(close, 3);
				var slow = sma(close, 9);
				if (crossover(fast, slow)) long();
			}
		}';
		var prog = new MuseParser().parse(source);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.equals(0, emitted.escapeRegions.length);
		Assert.isFalse(emitted.framedNames.exists("fast"));
		Assert.isFalse(emitted.framedNames.exists("slow"));
	}
}

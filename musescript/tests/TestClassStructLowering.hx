package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.StrategyWasmBackend;
import musescript.builtins.TradeBuiltins;

/**
 * P4: class-WASM struct lowering — the real version (see
 * musescript-enums-classes-rollout memory for why "lower ENew inside on-bar"
 * alone wouldn't have helped: the cross-bar-persistence fix moved
 * construct-once instantiation ENTIRELY out of the per-bar body). Only
 * construct-once instances (ast/ConstructOnce.hx) of classes with no parent
 * and fully natively-emittable field defaults/ctor/methods get lowered —
 * each gets a FIXED compile-time offset into StrategyWasmRuntimeWat's HEAP
 * region (no runtime allocator), fields are `f64.load`/`f64.store` at
 * self-relative offsets, methods compile as standalone `(func $Class_method
 * (param $self i32) ...)` functions called DIRECTLY (no `host_eval`), and a
 * `construct_once_init` export runs the field-init + ctor exactly once,
 * called by the host right after instantiation.
 *
 * The load-bearing bug this suite guards against (found via manual memory
 * inspection, not by chance): `StrategyWasmRuntimeWat.helpers`'s
 * `$init_state` — called by BOTH `reset` and `configure_tape`, which run
 * AFTER `construct_once_init` in the actual host call order — used to zero
 * the WHOLE `[0, STATE_BYTES)` region, silently wiping every lowered
 * instance's freshly-initialized fields back to zero before the first bar
 * ever ran. Fixed by narrowing that sweep to stop at `HEAP_BASE` (the
 * construct-once heap initializes itself completely via its own run-once
 * call; nothing needs `init_state` to ALSO zero it).
 */
class TestClassStructLowering extends Test {
	function assertNativeParity(source:String, feed:BarFeed):Void {
		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext())
			.runBacktest(new MuseParser().parse(source), feed);

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			TradeBuiltins.resetCrossState();
			var nativeHarness = new HarnessContext();
			Reflect.setField(nativeHarness, "feed", feed);
			var nativeResult = StrategyWasmBackend.compile(new MuseParser().parse(source))(nativeHarness);
			Assert.equals(interpResult.trades, nativeResult.trades);
			Assert.floatEquals(interpResult.finalEquity, nativeResult.finalEquity);
		}
		#end
	}

	static final COUNTER_SRC = 'class Counter {\n'
		+ '  n = 0.0;\n'
		+ '  function bump() {\n'
		+ '    n = n + 1.0\n'
		+ '    return n\n'
		+ '  }\n'
		+ '}\n'
		+ 'strategy CounterProbe {\n'
		+ '  c = new Counter();\n'
		+ '  onBar {\n'
		+ '    var v = c.bump()\n'
		+ '    plot(v, "n")\n'
		+ '  }\n'
		+ '}\n';

	public function testNoArgCtorClassLowersNatively() {
		var prog = new MuseParser().parse(COUNTER_SRC);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isFalse(StringTools.contains(emitted.wat, "call $host_eval"));
		Assert.isTrue(StringTools.contains(emitted.wat, "call $Counter_bump"));
		Assert.isTrue(StringTools.contains(emitted.wat, "construct_once_init"));
	}

	public function testNoArgCtorClassPersistsStateNatively() {
		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			var feed = BarFeed.synthetic(5, 1);
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", feed);
			StrategyWasmBackend.compile(new MuseParser().parse(COUNTER_SRC))(harness);
			var series = [for (c in harness.chart.commands) c.series];
			Assert.same([1.0, 2.0, 3.0, 4.0, 5.0], series);
		}
		#end
	}

	static final AVERAGER_SRC = 'class Averager {\n'
		+ '  sum = 0.0;\n'
		+ '  count = 0.0;\n'
		+ '  new(seed) {\n'
		+ '    sum = seed\n'
		+ '    count = 1.0\n'
		+ '  }\n'
		+ '  function add(x) {\n'
		+ '    sum = sum + x\n'
		+ '    count = count + 1.0\n'
		+ '    return sum / count\n'
		+ '  }\n'
		+ '}\n'
		+ 'strategy AveragerProbe {\n'
		+ '  a = new Averager(2.0);\n'
		+ '  onBar {\n'
		+ '    var avg = a.add(close)\n'
		+ '    plot(avg, "avg")\n'
		+ '    when avg > close: { long() }\n'
		+ '    when avg <= close: { flat() }\n'
		+ '  }\n'
		+ '}\n';

	/** Constant-arg ctor, real trading signal driven off the method's return
	 * value, over a real 300-bar tape — the load-bearing end-to-end proof. */
	public function testConstArgCtorClassMatchesInterpExactly() {
		var prog = new MuseParser().parse(AVERAGER_SRC);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		Assert.isFalse(StringTools.contains(emitted.wat, "call $host_eval"));
		assertNativeParity(AVERAGER_SRC, BarFeed.synthetic(300, 21));
	}

	/** A different seed/tape than the diagnostic run that found the bug — to
	 * catch anything narrowly tuned to one specific bar sequence. */
	public function testConstArgCtorClassMatchesOnAnotherTape() {
		assertNativeParity(AVERAGER_SRC, BarFeed.synthetic(180, 5));
	}

	/**
	 * A class that DOESN'T qualify for native lowering (has a parent — no
	 * inheritance support in this MVP) must still work correctly via the
	 * existing escape-region fallback (F1/F2), exactly as before this
	 * feature existed — this is the safety net this whole feature is built
	 * on top of, still exercised.
	 */
	public function testClassWithParentFallsBackToEscapeCorrectly() {
		var source = 'class Animal {\n'
			+ '  sound = "quiet";\n'
			+ '}\n'
			+ 'class Dog extends Animal {\n'
			+ '  n = 0.0;\n'
			+ '  function bump() {\n'
			+ '    n = n + 1.0\n'
			+ '    return n\n'
			+ '  }\n'
			+ '}\n'
			+ 'strategy DogProbe {\n'
			+ '  d = new Dog();\n'
			+ '  onBar {\n'
			+ '    var v = d.bump()\n'
			+ '    plot(v, "n")\n'
			+ '  }\n'
			+ '}\n';
		var prog = new MuseParser().parse(source);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		// Not natively lowered (has a parent) — must still correctly escape.
		Assert.isTrue(StringTools.contains(emitted.wat, "call $host_eval"));
		assertNativeParity(source, BarFeed.synthetic(5, 1));
	}

	/**
	 * A ctor call with a NON-constant argument (reads `close`) can't be
	 * lowered (P4 restriction — construct-once runs before any bar is
	 * bound) — must fall back safely, not crash or mis-emit.
	 */
	public function testNonConstantCtorArgFallsBackSafely() {
		var source = 'class Seeded {\n'
			+ '  v = 0.0;\n'
			+ '  new(x) {\n'
			+ '    v = x\n'
			+ '  }\n'
			+ '  function get() {\n'
			+ '    return v\n'
			+ '  }\n'
			+ '}\n'
			+ 'strategy SeededProbe {\n'
			+ '  s = new Seeded(close);\n'
			+ '  onBar {\n'
			+ '    plot(s.get(), "v")\n'
			+ '  }\n'
			+ '}\n';
		var prog = new MuseParser().parse(source);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);
		assertNativeParity(source, BarFeed.synthetic(5, 1));
	}

	/** Two separate construct-once instances of DIFFERENT classes get
	 * distinct heap offsets and don't interfere with each other. */
	public function testTwoDistinctInstancesDontAlias() {
		var source = 'class Counter {\n'
			+ '  n = 0.0;\n'
			+ '  function bump() {\n'
			+ '    n = n + 1.0\n'
			+ '    return n\n'
			+ '  }\n'
			+ '}\n'
			+ 'strategy TwoCounters {\n'
			+ '  a = new Counter();\n'
			+ '  b = new Counter();\n'
			+ '  onBar {\n'
			+ '    var va = a.bump()\n'
			+ '    var vb = b.bump()\n'
			+ '    var vb2 = b.bump()\n'
			+ '    plot(va, "a")\n'
			+ '    plot(vb2, "b")\n'
			+ '  }\n'
			+ '}\n';
		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			var feed = BarFeed.synthetic(3, 1);
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", feed);
			StrategyWasmBackend.compile(new MuseParser().parse(source))(harness);
			var series = [for (c in harness.chart.commands) c.series];
			// a bumps once per bar: 1,2,3 (plotted first each bar); b bumps
			// TWICE per bar: 2,4,6 (plotted second each bar) — interleaved.
			Assert.same([1.0, 2.0, 2.0, 4.0, 3.0, 6.0], series);
		}
		#end
	}
}

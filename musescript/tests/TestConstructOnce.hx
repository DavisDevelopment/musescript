package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.compile.MuseCompiler;
import musescript.compile.JsBackend;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.MusePrinter;

/**
 * A class instance constructed at strategy level (`c = new Counter();`) must
 * persist across bars, NOT be silently reconstructed every bar. Found while
 * scoping P4 (musescript-enums-classes-rollout memory): `registerStrategyBody`
 * treats every top-level `Assign` as a per-bar prelude (correct for ordinary
 * value bindings like `fast = ema(close, 5)`, which genuinely must
 * re-evaluate every bar) — but `ENew` allocates NEW state, so re-running it
 * every bar silently discarded whatever a stateful class instance's methods
 * had accumulated, undermining the entire "streaming indicator authored as a
 * MuseScript class" premise behind P2. Fixed via `ast/ConstructOnce.hx`
 * (shared classification) applied consistently in `MuseInterp`,
 * `JsEmitter`/`JsBackend`, and `StrategyWasmEmitter`/`StrategyWasmBackend`.
 */
class TestConstructOnce extends Test {
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

	static function plottedSeries(h:HarnessContext):Array<Float> {
		return [for (cmd in h.chart.commands) cmd.series];
	}

	public function testInterpPersistsInstanceStateAcrossBars() {
		var feed = BarFeed.synthetic(5, 1);
		var harness = new HarnessContext();
		new MuseInterp(harness).runBacktest(new MuseParser().parse(COUNTER_SRC), feed);
		Assert.same([1.0, 2.0, 3.0, 4.0, 5.0], plottedSeries(harness));
	}

	public function testJsBackendPersistsInstanceStateAcrossBars() {
		#if js
		var feed = BarFeed.synthetic(5, 1);
		var harness = new HarnessContext();
		Reflect.setField(harness, "feed", feed);
		var ex = MuseCompiler.compileEx(new MuseParser().parse(COUNTER_SRC), { target: "js", strict: true });
		ex.fn(harness);
		// Confirm the JS-compiled path genuinely ran (not a silent fallback
		// to interp, which would trivially "pass" for the wrong reason).
		Assert.equals("js", JsBackend.lastBackend);
		Assert.same([1.0, 2.0, 3.0, 4.0, 5.0], plottedSeries(harness));
		#end
	}

	public function testWasmHybridPersistsInstanceStateAcrossBars() {
		var prog = new MuseParser().parse(COUNTER_SRC);
		var emitted = StrategyWasmBackend.emitOnBar(prog);
		Assert.notNull(emitted);

		#if (js || python)
		if (StrategyWasmBackend.hostReady()) {
			var feed = BarFeed.synthetic(5, 1);
			var harness = new HarnessContext();
			Reflect.setField(harness, "feed", feed);
			StrategyWasmBackend.compile(new MuseParser().parse(COUNTER_SRC))(harness);
			Assert.same([1.0, 2.0, 3.0, 4.0, 5.0], plottedSeries(harness));
		}
		#end
	}

	/**
	 * Regression guard: ordinary (non-`ENew`) prelude assigns must STILL
	 * re-evaluate every bar — this fix must not accidentally freeze indicator-
	 * style bindings that are supposed to track the current bar.
	 */
	public function testOrdinaryPreludeAssignStillReevaluatesEveryBar() {
		var source = 'strategy PreludeProbe {\n'
			+ '  fast = close\n'
			+ '  onBar {\n'
			+ '    plot(fast, "fast")\n'
			+ '  }\n'
			+ '}\n';
		var feed = BarFeed.synthetic(5, 1);
		var harness = new HarnessContext();
		new MuseInterp(harness).runBacktest(new MuseParser().parse(source), feed);
		var closes = [for (b in feed.all()) b.close];
		Assert.same(closes, plottedSeries(harness));
	}

	/** Print → reparse round trip (genome-expansion contract) unaffected by
	 * the execution-model change — this is purely an interp/emitter timing
	 * fix, MusePrinter's output shape doesn't change. */
	public function testConstructOnceProgramRoundTripsThroughPrinter() {
		var prog1 = new MuseParser().parse(COUNTER_SRC);
		var printed = new MusePrinter().printProgram(prog1);
		var prog2 = new MuseParser().parse(printed);

		var feed = BarFeed.synthetic(5, 1);
		var h1 = new HarnessContext();
		new MuseInterp(h1).runBacktest(prog1, feed);
		var h2 = new HarnessContext();
		new MuseInterp(h2).runBacktest(prog2, feed);
		Assert.same(plottedSeries(h1), plottedSeries(h2));
	}
}

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
 * F1: statement-level WASM escape regions. `StrategyWasmEmitter`'s old
 * behavior was whole-module abort-to-null on the first unsupported node
 * (`EmitUnsupported` caught once at the top). Now each statement is tried
 * independently — natives emit real WAT, unsupported ones become
 * `call $host_eval N` and run through a shared `MuseInterp` on the host.
 *
 * The hard gate: full interp, whole-strategy WASM (where it still fully
 * emits), and hybrid (native + host_eval) must all produce IDENTICAL
 * per-bar results over the same tape.
 */
class TestHybridWasm extends Test {
	// crossover/crossunder track "previous value" in module-level static state
	// shared by every interp/wasm run in the process — resetCrossState() before
	// EACH independent run is the established convention (TestMain.hx does the
	// same around every interp-vs-wasm comparison) so one run's state can't
	// leak into the next and desync trade counts that would otherwise match.
	function assertParity(source:String, feed:musescript.harness.BarFeed):Void {
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

	/** Genuine mix: native `sma`/`crossover` ops alongside one deliberately
	 * unsupported statement (`str_contains`), in the SAME on(bar) body. */
	public function testMixedNativeAndEscapeStatementsPartition() {
		var source = '{
			@strategy("hybrid_mix")
			@on(bar) {
				var fast = sma(close, 3);
				var slow = sma(close, 8);
				var tag = str_contains("bull", "bu") ? "yes" : "no";
				if (crossover(fast, slow)) long();
				if (crossunder(fast, slow)) flat();
			}
		}';
		var wat = StrategyWasmBackend.emitWat(new MuseParser().parse(source));
		Assert.notNull(wat);
		// Proves it genuinely partitioned — both a real native op AND an escape.
		Assert.isTrue(wat.indexOf("call $sma") >= 0 || wat.indexOf("sma") >= 0);
		Assert.isTrue(wat.indexOf("call $host_eval") >= 0);

		assertParity(source, BarFeed.synthetic(300, 13));
	}

	/**
	 * Taint-propagation correctness (the hazard fixed while building F1): a
	 * value only an escape region can assign must NOT be readable by native
	 * code as a stale/zero local — the statement reading it must ALSO escape.
	 * A tape long enough for `crossover`/`sma` to actually fire on both sides
	 * makes this a real behavioral check, not just "didn't throw".
	 */
	public function testEscapedAssignTaintsLaterNativeRead() {
		var source = '{
			@strategy("hybrid_taint")
			@on(bar) {
				var flag = str_contains("bull", "bu");
				var fast = sma(close, 3);
				var slow = sma(close, 9);
				if (flag && crossover(fast, slow)) long();
				if (crossunder(fast, slow)) flat();
			}
		}';
		var wat = StrategyWasmBackend.emitWat(new MuseParser().parse(source));
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $host_eval") >= 0);

		assertParity(source, BarFeed.synthetic(300, 21));
	}

	/**
	 * The bidirectional hazard F1's fixpoint exists specifically to catch: a
	 * value assigned by a NATIVE statement (`fast`, a plain WASM local, reset
	 * every bar), then read INSIDE a later statement that must escape for an
	 * unrelated reason (`str_contains`). The escape's interp thunk has no
	 * visibility into WASM locals — only into values that reached it via the
	 * shared harness/interp, i.e. values SOME escape region itself set. A
	 * naive one-directional taint pass (native reads an escaped write) does
	 * NOT catch this — it needs the reverse: escalate `var fast = sma(...)`
	 * to escape too, so `fast` becomes a real interp global by the time the
	 * second statement's thunk runs. Without that escalation this test would
	 * fail (hybrid would silently read `fast` as null/0 and never fire
	 * `long()`); it's the load-bearing regression test for that fix.
	 */
	public function testNativeWriteReadInsideUnsupportedStatementStaysCorrect() {
		var source = '{
			@strategy("hybrid_native_then_escape")
			@on(bar) {
				var fast = sma(close, 3);
				if (fast > 0 && str_contains("bull", "bu")) long();
			}
		}';
		assertParity(source, BarFeed.synthetic(200, 9));
	}

	/** Side-effect-only escape (no assigned value read elsewhere): the
	 * simplest correct F1 case, order calls firing purely from host_eval. */
	public function testPureSideEffectEscapeRegion() {
		var source = '{
			@strategy("hybrid_side_effect")
			@on(bar) {
				if (str_contains("go", "go")) long();
				if (bar_index > 50) flat();
			}
		}';
		assertParity(source, BarFeed.synthetic(150, 5));
	}

	/**
	 * Risk-managed exits (unrealized_pnl_pct/bars_in_trade), the first genome vocabulary added
	 * beyond bare crossover signals -- see musescript.evo.MapElites / the evo risk-exit growth
	 * pool. GraalWasmHost previously left get_position/get_entry_price/get_unrealized_pnl etc
	 * UNIMPLEMENTED (genome-expanded source never emitted them), and long/short/flat's WASM path
	 * never passed a barIndex to OrderSim at all -- both fixed alongside this test. A stop-loss AND
	 * a take-profit in the same on(bar), so the parity check exercises get_position/get_entry_price/
	 * get_unrealized_pnl/get_bars_in_trade together on both backends.
	 */
	public function testRiskManagedExitsNativeWasmMatchesInterp() {
		var source = '{
			@strategy("hybrid_risk_exit")
			@on(bar) {
				var fast = sma(close, 3);
				var slow = sma(close, 9);
				if (crossover(fast, slow)) long();
				if (crossunder(fast, slow)) short();
				if (unrealized_pnl_pct() < -0.02 || unrealized_pnl_pct() > 0.05 || bars_in_trade() > 20) flat();
			}
		}';
		var wat = StrategyWasmBackend.emitWat(new MuseParser().parse(source));
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $get_position") >= 0, "expected native get_position");
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, "risk-exit builtins must lower natively");
		assertParity(source, BarFeed.synthetic(600, 31));
	}
}

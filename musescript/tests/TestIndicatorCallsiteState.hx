package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * Regression test for the @indicator callsite-state-aliasing bug: an
 * `@indicator` declaration called TWICE with different arguments in the same
 * strategy used to share one state map (IndicatorInstance.state), so the two
 * calls silently corrupted each other's running state. Fixed by generalizing
 * CallsiteIds (previously scoped to crossover/rising/etc.) to also assign a
 * per-callsite id to program-declared @indicator calls, and keying state by
 * that id (IndicatorInstance.stateFor) instead of one shared map per
 * declaration name. See MuseInterp.setupRun's CallsiteIds.assign call and
 * IndicatorInstance.stateFor's doc comment.
 */
class TestIndicatorCallsiteState extends Test {
	function run(src:String, bars:Int = 3):Map<String, Array<Dynamic>> {
		var prog = new MuseParser().parse(src, "<test>");
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		interp.runBacktest(prog, BarFeed.synthetic(bars, 1));
		var out = new Map<String, Array<Dynamic>>();
		for (l in harness.logs) {
			var parts = l.msg.split("|");
			var key = parts[0];
			if (!out.exists(key)) out.set(key, []);
			out.get(key).push(Std.parseFloat(parts[1]));
		}
		return out;
	}

	public function testTwoCallsitesOfSameIndicatorDoNotShareState() {
		var src = '
		@indicator("probe_sum") function(n) {
			if (state.total == null) state.total = 0.0;
			state.total = state.total + n;
			return state.total;
		}

		@strategy("probe")
		@on(bar) {
			var a = probe_sum(1);
			var b = probe_sum(10);
			log("a|" + a);
			log("b|" + b);
		}
		';
		var out = run(src);
		Assert.same([1.0, 2.0, 3.0], out.get("a"));
		Assert.same([10.0, 20.0, 30.0], out.get("b"));
	}

	public function testSingleCallsiteStillAccumulatesAcrossBars() {
		var src = '
		@indicator("probe_count") function() {
			if (state.n == null) state.n = 0.0;
			state.n = state.n + 1.0;
			return state.n;
		}

		@strategy("probe2")
		@on(bar) {
			var c = probe_count();
			log("c|" + c);
		}
		';
		var out = run(src, 4);
		Assert.same([1.0, 2.0, 3.0, 4.0], out.get("c"));
	}

	public function testIndicatorCalledFromTwoDistinctStrategyLinesStaysIndependent() {
		// Same indicator, same args at both call sites -- still two DIFFERENT
		// syntactic callsites, so must NOT alias just because the args match.
		var src = '
		@indicator("probe_seq") function() {
			if (state.n == null) state.n = 0.0;
			state.n = state.n + 1.0;
			return state.n;
		}

		@strategy("probe3")
		@on(bar) {
			var x = probe_seq();
			var y = probe_seq();
			log("x|" + x);
			log("y|" + y);
		}
		';
		var out = run(src);
		Assert.same([1.0, 2.0, 3.0], out.get("x"));
		Assert.same([1.0, 2.0, 3.0], out.get("y"));
	}
}

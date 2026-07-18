package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.parse.MuseParser;
import musescript.parse.StrategyParser;
import musescript.plan.MusePlanner;
import musescript.plan.MuseIR;
import musescript.plan.PlanStep;
import musescript.harness.HarnessContext;
import musescript.harness.PlanRunner;
import musescript.harness.BarFeed;
import musescript.harness.Bar;

/**
 * The `pipeline` discovery-process construct (this codebase's own recurring
 * lesson — walk-forward validation, honest NaN over fake zero, promotion
 * gates on OOS not in-sample numbers — made into real language primitives:
 * `walkforward(folds, ?embargo)` + `promote(fn)`, recognized by MusePlanner
 * and executed for real by PlanRunner.walkForwardOptimize.
 *
 * `promote`'s predicate is written differently per dialect (a real, tested
 * gap found while building this): the typed surface (`pipeline { }`) has
 * arrow lambdas (`(r) => r.sharpe > 0.5`); the legacy `@macro`/`@strategy`
 * annotation dialect (vendored hscript) reserves `=>` exclusively for match
 * arms, so the same predicate there needs `function(r) return r.sharpe > 0.5`.
 * Both are exercised below — see testPipelineTypedSurfaceEndToEnd vs the
 * @macro-dialect tests.
 */
class TestWalkForwardPipeline extends Test {
	static function trendingBars(n:Int, seed:Int):Array<Bar> {
		var s = seed;
		function rnd():Float {
			s = (s * 1103515245 + 12345) & 0x7fffffff;
			return (s % 1000) / 1000.0;
		}
		var price = 100.0;
		var out = [];
		for (i in 0...n) {
			var drift = 0.05 + (rnd() - 0.5) * 1.5;
			var c = price + drift;
			out.push({
				open: price, high: Math.max(price, c) + 0.5, low: Math.min(price, c) - 0.5,
				close: c, volume: 1000.0, time: (i : Float), index: i
			});
			price = c;
		}
		return out;
	}

	static function smaSource():String {
		return '
			@strategy("t")
			@param("fast", 10)
			@param("slow", 30)
			@macro("d") {
				walkforward(4, 5);
				tune(fast, slow);
				optimize(sharpe);
			}
			@on(bar) {
				var a = sma("close", fast);
				var b = sma("close", slow);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		';
	}

	static function harnessWithParams():HarnessContext {
		var h = new HarnessContext();
		h.params.register("fast", 10, 5, 15, 5, "grid");
		h.params.register("slow", 30, 25, 35, 5, "grid");
		return h;
	}

	// ── planner recognition ──────────────────────────────────────────────────

	public function testWalkforwardAndPromoteRecognizedByPlanner() {
		var source = '
			@macro("d") {
				walkforward(5, 3);
				promote(function(r) return r.sharpe > 0.5);
				tune(fast);
				optimize(sharpe);
			}
		';
		var plan = new MusePlanner().plan(new MuseParser().parse(source));
		var sawWf = false, sawGate = false;
		for (s in plan.steps) {
			switch (s) {
				case WalkForwardStep(_, folds, embargo):
					sawWf = true;
					Assert.equals(5, folds);
					Assert.equals(3, embargo);
				case PromotionGateStep(_, _): sawGate = true;
				default:
			}
		}
		Assert.isTrue(sawWf);
		Assert.isTrue(sawGate);
	}

	public function testWalkforwardDefaultEmbargoIsZero() {
		var plan = new MusePlanner().plan(new MuseParser().parse('@macro("d") { walkforward(3); }'));
		switch (plan.steps[0]) {
			case WalkForwardStep(_, folds, embargo):
				Assert.equals(3, folds);
				Assert.equals(0, embargo);
			default:
				Assert.fail("expected WalkForwardStep");
		}
	}

	public function testMuseIrSerializesNewSteps() {
		var source = '@macro("d") { walkforward(2, 1); promote(function(r) return r.sharpe > 0.0); }';
		var json = MuseIR.toJson(new MusePlanner().plan(new MuseParser().parse(source)));
		Assert.isTrue(json.indexOf("WalkForward") >= 0);
		Assert.isTrue(json.indexOf("PromotionGate") >= 0);
	}

	// ── real execution ───────────────────────────────────────────────────────

	public function testWalkForwardOptimizeProducesExpandingFolds() {
		var harness = harnessWithParams();
		var prog = new MuseParser().parse(smaSource());
		var plan = new MusePlanner().plan(prog);
		var feed = new BarFeed(trendingBars(400, 7));
		var opt = new PlanRunner(harness).bindProgram(prog, feed).optimize(plan, "sharpe");

		Assert.notNull(opt.walkForward);
		Assert.equals(4, opt.walkForward.folds.length);
		var prevTrain = 0;
		for (f in opt.walkForward.folds) {
			Assert.isTrue(f.trainBars > prevTrain); // expanding window
			Assert.isTrue(f.testBars > 0);
			prevTrain = f.trainBars;
		}
	}

	public function testAggregateIsMeanOfFoldOosMetrics() {
		var harness = harnessWithParams();
		var prog = new MuseParser().parse(smaSource());
		var plan = new MusePlanner().plan(prog);
		var feed = new BarFeed(trendingBars(400, 11));
		var opt = new PlanRunner(harness).bindProgram(prog, feed).optimize(plan, "sharpe");

		var wf = opt.walkForward;
		var manualMean = 0.0;
		for (f in wf.folds) manualMean += f.oosSharpe;
		manualMean /= wf.folds.length;
		Assert.floatEquals(manualMean, wf.aggregateSharpe);
		Assert.floatEquals(manualMean, opt.bestMetric); // top-level bestMetric mirrors the OOS aggregate
	}

	public function testPromotionGatePasses() {
		var source = '
			@strategy("t")
			@param("fast", 10)
			@param("slow", 30)
			@macro("d") {
				walkforward(3, 5);
				promote(function(r) return r.sharpe > -999.0 && r.trades >= 0);
				tune(fast, slow);
				optimize(sharpe);
			}
			@on(bar) {
				var a = sma("close", fast);
				var b = sma("close", slow);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		';
		var harness = harnessWithParams();
		var prog = new MuseParser().parse(source);
		var plan = new MusePlanner().plan(prog);
		var feed = new BarFeed(trendingBars(300, 3));
		var opt = new PlanRunner(harness).bindProgram(prog, feed).optimize(plan, "sharpe");
		Assert.equals(true, opt.walkForward.promoted);
	}

	public function testPromotionGateFails() {
		var source = '
			@strategy("t")
			@param("fast", 10)
			@param("slow", 30)
			@macro("d") {
				walkforward(3, 5);
				promote(function(r) return r.sharpe > 999.0);
				tune(fast, slow);
				optimize(sharpe);
			}
			@on(bar) {
				var a = sma("close", fast);
				var b = sma("close", slow);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		';
		var harness = harnessWithParams();
		var prog = new MuseParser().parse(source);
		var plan = new MusePlanner().plan(prog);
		var feed = new BarFeed(trendingBars(300, 5));
		var opt = new PlanRunner(harness).bindProgram(prog, feed).optimize(plan, "sharpe");
		Assert.equals(false, opt.walkForward.promoted);
	}

	public function testNoPromoteLeavesPromotedNull() {
		var harness = harnessWithParams();
		var prog = new MuseParser().parse(smaSource()); // no promote() in this source
		var plan = new MusePlanner().plan(prog);
		var feed = new BarFeed(trendingBars(300, 13));
		var opt = new PlanRunner(harness).bindProgram(prog, feed).optimize(plan, "sharpe");
		Assert.isNull(opt.walkForward.promoted);
	}

	public function testNoWalkforwardStepKeepsLegacyBehaviorUnchanged() {
		var source = '
			@strategy("t")
			@param("fast", 10)
			@param("slow", 30)
			@macro("d") {
				tune(fast, slow);
				optimize(sharpe);
			}
			@on(bar) {
				var a = sma("close", fast);
				var b = sma("close", slow);
				if (crossover(a, b)) long();
				if (crossunder(a, b)) flat();
			}
		';
		var harness = harnessWithParams();
		var prog = new MuseParser().parse(source);
		var plan = new MusePlanner().plan(prog);
		var opt = new PlanRunner(harness).bindProgram(prog, BarFeed.synthetic(120, 9)).optimize(plan, "sharpe");
		Assert.isTrue(opt.trials > 0);
		Assert.isTrue(Math.isFinite(opt.bestMetric));
		Assert.isNull(opt.walkForward); // absent, not just empty — same shape as before this feature existed
	}

	public function testInsufficientDataIsHonestNotFabricated() {
		var harness = harnessWithParams();
		var prog = new MuseParser().parse(smaSource()); // walkforward(4, 5)
		var plan = new MusePlanner().plan(prog);
		var feed = new BarFeed(trendingBars(15, 17)); // far too short for 4 folds
		var opt = new PlanRunner(harness).bindProgram(prog, feed).optimize(plan, "sharpe");
		Assert.equals(0, opt.trials);
		Assert.isTrue(Math.isNaN(opt.bestMetric));
	}

	// ── real `pipeline { ... }` syntax, not just the @macro alias ───────────

	public function testPipelineTypedSurfaceEndToEnd() {
		var source = '
			strategy PipeStrat {
				param fast = 10
				param slow = 30
				onBar {
					a = sma(close, fast)
					b = sma(close, slow)
					when crossover(a, b): long()
					when crossunder(a, b): flat()
				}
			}
			pipeline Discover {
				walkforward(3, 5)
				promote((r) => r.sharpe > -999.0)
				tune(fast, slow)
				optimize(sharpe)
			}
		';
		Assert.isTrue(StrategyParser.looksLike(source));
		var prog = new MuseParser().parse(source);
		var plan = new MusePlanner().plan(prog);

		var harness = harnessWithParams();
		var feed = new BarFeed(trendingBars(300, 19));
		var opt = new PlanRunner(harness).bindProgram(prog, feed).optimize(plan, "sharpe");
		Assert.notNull(opt.walkForward);
		Assert.equals(3, opt.walkForward.folds.length);
		Assert.equals(true, opt.walkForward.promoted);
	}
}

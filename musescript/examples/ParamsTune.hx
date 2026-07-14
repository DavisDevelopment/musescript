package musescript.examples;

import musescript.parse.MuseParser;
import musescript.plan.MusePlanner;
import musescript.plan.MuseIR;
import musescript.harness.HarnessContext;
import musescript.harness.PlanRunner;
import musescript.harness.BarFeed;

class ParamsTune {
	static function main() {
		var source = '
		{
			@strategy("tuned_ma")
			@param("fast", 10)
			@param("slow", 30)

			@macro("discover") {
				tune(fast, slow);
				optimize(sharpe);
			}

			@on(bar) {
				var maFast = sma("close", fast);
				var maSlow = sma("close", slow);
				if (crossover(maFast, maSlow)) long();
				if (crossunder(maFast, maSlow)) flat();
			}
		}
		';

		var harness = new HarnessContext();
		harness.params.register("fast", 10, 5, 40, 5, "grid");
		harness.params.register("slow", 30, 20, 80, 10, "grid");

		var prog = new MuseParser().parse(source, "02-params-tune.ms");
		var plan = new MusePlanner().plan(prog);
		Sys.println("=== MuseScript 02-params-tune ===");
		Sys.println(MuseIR.toJson(plan));

		var runner = new PlanRunner(harness).bindProgram(prog, BarFeed.synthetic(300, 42));
		var opt = runner.optimize(plan, "sharpe");
		Sys.println("trials: " + opt.trials);
		Sys.println("bestMetric: " + opt.bestMetric);
		for (k => v in opt.bestParams) Sys.println('best $k = $v');
	}
}

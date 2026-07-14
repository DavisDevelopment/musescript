package musescript.examples;

import musescript.parse.MuseParser;
import musescript.plan.MusePlanner;
import musescript.plan.MuseIR;
import musescript.harness.HarnessContext;
import musescript.harness.PlanRunner;
import musescript.harness.BarFeed;

class DiscoveryPipeline {
	static function main() {
		var source = '
		{
			@strategy("discovery")
			@param("learningRate", 0.1)
			@param("maxDepth", 5)
			@param("threshold", 0.5)
			@param("holdBars", 3)

			@macro("discover") {
				sample(universe, 22);
				llm.suggestEncodings(features, 5);
				pickBest(encodings, function(enc) {
					return ensemble(enc, 100);
				});
				tune(learningRate, maxDepth);
				optimize(sharpe);
				distill(best);
			}
		}
		';

		var harness = new HarnessContext();
		harness.params.register("learningRate", 0.1, 0.01, 0.5, 0.05, "grid");
		harness.params.register("maxDepth", 5, 2, 12, 1, "grid");

		var prog = new MuseParser().parse(source, "03-discovery.ms");
		var plan = new MusePlanner().plan(prog);
		Sys.println("=== MuseScript 03-discovery-pipeline ===");
		Sys.println(MuseIR.toJson(plan));

		var results = new PlanRunner(harness).bindProgram(prog, BarFeed.synthetic(300, 7)).run(plan);
		for (k => v in results) {
			Sys.println('step $k => ' + haxe.Json.stringify(v));
		}
	}
}

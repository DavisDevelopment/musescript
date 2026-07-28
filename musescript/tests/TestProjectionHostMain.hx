package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused smoke: Claude projection scaffold + EW host boundary X + FeatureViz. */
class TestProjectionHostMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestProjectionScaffold());
		runner.addCase(new TestEwHostProjection());
		runner.addCase(new TestFeatureViz());
		runner.addCase(new TestEwBenchmark());
		runner.addCase(new TestRegimeMcmc());
		Report.create(runner);
		runner.run();
	}
}

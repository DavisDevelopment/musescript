package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused smoke: Claude projection scaffold + EW host boundary X + FeatureViz. */
class TestProjectionHostMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestProjectionScaffold());
		runner.addCase(new TestPipelineHardening());
		runner.addCase(new TestPitDiscipline());
		runner.addCase(new TestP1Hardening());
		runner.addCase(new TestFrostAdversarial());
		runner.addCase(new TestDetParity());
		runner.addCase(new TestReproDeterminism());
		runner.addCase(new TestForecastHostParity());
		runner.addCase(new TestTapeLinter());
		runner.addCase(new TestEwHostProjection());
		runner.addCase(new TestFeatureViz());
		runner.addCase(new TestEwBenchmark());
		runner.addCase(new TestRegimeMcmc());
		runner.addCase(new TestRegimeHost());
		Report.create(runner);
		runner.run();
	}
}

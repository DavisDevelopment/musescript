package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused smoke: Claude projection scaffold + EW host boundary X. */
class TestProjectionHostMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestProjectionScaffold());
		runner.addCase(new TestEwHostProjection());
		Report.create(runner);
		runner.run();
	}
}

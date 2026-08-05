package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for muse.pd M0–M4 + MultiIndex lite. */
class TestPdMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestPd());
		runner.addCase(new TestPdM1());
		runner.addCase(new TestPdM2());
		runner.addCase(new TestPdM3());
		runner.addCase(new TestPdM4());
		runner.addCase(new TestPdMultiIndex());
		runner.addCase(new TestPdStrSidecar());
		runner.addCase(new TestPdParquet());
		Report.create(runner);
		runner.run();
	}
}

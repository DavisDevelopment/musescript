package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for muse.pd M0–M3. */
class TestPdMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestPd());
		runner.addCase(new TestPdM1());
		runner.addCase(new TestPdM2());
		runner.addCase(new TestPdM3());
		Report.create(runner);
		runner.run();
	}
}

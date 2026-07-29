package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused Initiative 4 suite: determinism proof + seed stamp + DetParity foundation. */
class TestReproMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestDetParity());
		runner.addCase(new TestReproDeterminism());
		Report.create(runner);
		runner.run();
	}
}

package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for muse.diag / DiagPack chart pack. */
class TestDiagPackMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestDiagPack());
		Report.create(runner);
		runner.run();
	}
}

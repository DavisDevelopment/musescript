package musescript.tests;

import utest.Runner;
import utest.ui.Report;

class TestGeomEwStackMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestGeomEwStack());
		Report.create(runner);
		runner.run();
	}
}

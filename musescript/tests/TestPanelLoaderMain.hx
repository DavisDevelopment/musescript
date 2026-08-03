package musescript.tests;

import utest.Runner;
import utest.ui.Report;

class TestPanelLoaderMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestPanelLoader());
		runner.addCase(new TestPanelFitness());
		Report.create(runner);
		runner.run();
	}
}

package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused runner for plugin-kind capability table tests. */
class TestPluginKindsMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestPluginKinds());
		Report.create(runner);
		runner.run();
	}
}

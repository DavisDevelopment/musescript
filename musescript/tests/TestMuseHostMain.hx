package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for the namespaced `muse.*` host stdlib slice. */
class TestMuseHostMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestMuseHost());
		runner.addCase(new TestPanelWasmParity());
		runner.addCase(new TestLangClassStrategy());
		Report.create(runner);
		runner.run();
	}
}

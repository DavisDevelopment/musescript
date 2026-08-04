package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for the namespaced `muse.*` host stdlib slice. */
class TestMuseHostMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestMuseHost());
		runner.addCase(new TestMuseStrPath());
		runner.addCase(new TestNdArray());
		runner.addCase(new TestWasmNp());
		runner.addCase(new TestPanelWasmParity());
		runner.addCase(new TestPanelEvoGenomes());
		runner.addCase(new TestNpPdEvoPalette());
		runner.addCase(new TestPanelFitness());
		runner.addCase(new TestLangClassStrategy());
		Report.create(runner);
		runner.run();
	}
}

package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for NdArray + muse.np. */
class TestNdArrayMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestNdArray());
		runner.addCase(new TestWasmNp());
		Report.create(runner);
		runner.run();
	}
}

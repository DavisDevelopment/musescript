package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for M0 muse.str / muse.path / IoDenied spine. */
class TestMuseStrPathMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestMuseStrPath());
		Report.create(runner);
		runner.run();
	}
}

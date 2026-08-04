package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for M1 muse.re / muse.fs + M2 muse.http / fixtures + ingest tier. */
class TestMuseIoMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestMuseIo());
		runner.addCase(new TestMuseHttp());
		runner.addCase(new TestMuseIngest());
		Report.create(runner);
		runner.run();
	}
}

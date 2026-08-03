package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for MuseEvents / MuseRuntime event-bus facades. */
class TestMuseEventsMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestMuseEvents());
		Report.create(runner);
		runner.run();
	}
}

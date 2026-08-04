package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused suite for OrderBook groups / partial flat / bracket sugar. */
class TestOrderBookMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestOrderBook());
		Report.create(runner);
		runner.run();
	}
}

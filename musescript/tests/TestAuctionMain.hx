package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Dedicated runner for auction / volume-profile forecast host (idea ②). */
class TestAuctionMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestVolumeProfile());
		runner.addCase(new TestAuctionForecastHost());
		Report.create(runner);
		runner.run();
	}
}

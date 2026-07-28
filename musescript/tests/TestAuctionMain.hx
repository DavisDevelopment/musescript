package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Dedicated runner for auction / volume-profile forecast host (idea ②). */
class TestAuctionMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestVolumeProfile());
		runner.addCase(new TestAuctionForecastHost());
		runner.addCase(new TestPitDiscipline());
		runner.addCase(new TestTapeLinter());
		Report.create(runner);
		runner.run();
	}
}

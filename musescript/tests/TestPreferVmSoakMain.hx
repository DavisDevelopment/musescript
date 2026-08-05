package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/**
 * Dedicated runner for the preferVm soak / regression gate (Fitness evaluateVm / preferVm routes
 * + DetParityDump VM tiers). Not part of the default engine-matrix — see docs/ENGINE_MATRIX.md.
 */
class TestPreferVmSoakMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestPreferVmSoak());
		runner.addCase(new TestDetParity());
		Report.create(runner);
		runner.run();
	}
}

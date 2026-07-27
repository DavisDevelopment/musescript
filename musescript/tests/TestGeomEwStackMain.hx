package musescript.tests;

import utest.Runner;
import utest.ui.Report;
import musescript.tests.ports.TestPortBatch31;
import musescript.tests.ports.TestPortBatch32;
import musescript.tests.ports.TestPortBatch36;

/** Geom/EW stack + Fib/harmonic port batches touched by the geometry rewrite. */
class TestGeomEwStackMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestGeomEwStack());
		runner.addCase(new TestEwHandbookCh01());
		runner.addCase(new TestEwDegreeNesting());
		runner.addCase(new TestEwPhiFinetune());
		runner.addCase(new TestPortBatch31());
		runner.addCase(new TestPortBatch32());
		runner.addCase(new TestPortBatch36());
		Report.create(runner);
		runner.run();
	}
}

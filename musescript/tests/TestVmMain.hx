package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Dedicated runner for the Tier-A bytecode VM parity gate (SPEC_BYTECODE_VM.md
 * §4 / BYTECODE_VM_TODO.md V1). Scoped so CI gates on interp↔VM byte-identity
 * without dragging in the full TestMain suite the maintainers don't gate on. */
class TestVmMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestBytecodeVmParity());
		Report.create(runner);
		runner.run();
	}
}

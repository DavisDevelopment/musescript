package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for host/evo follow-ups (palette aux, muse namespaces, wasm). */
class TestHostEvoFollowupsMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestMuseHost());
		runner.addCase(new TestPanelWasmParity());
		runner.addCase(new TestPanelEvoGenomes());
		runner.addCase(new TestPanelFitness());
		runner.addCase(new TestEvoVariation());
		runner.addCase(new TestAuthorHoles());
		runner.addCase(new TestNmaFitness());
		runner.addCase(new TestHybridWasm());
		Report.create(runner);
		runner.run();
	}
}

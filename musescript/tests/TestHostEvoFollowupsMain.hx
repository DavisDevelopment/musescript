package musescript.tests;

import utest.Runner;
import utest.ui.Report;

/** Focused gate for host/evo follow-ups (palette aux, muse namespaces, wasm).
 * Also runs OPEN_ITEMS 1.2 `TestIndicatorLibHygiene` so engine-matrix executes
 * the RingBuffer `.shift()` ban, not only the node preflight grep.
 */
class TestHostEvoFollowupsMain {
	static function main() {
		var runner = new Runner();
		runner.addCase(new TestMuseHost());
		runner.addCase(new TestPanelWasmParity());
		runner.addCase(new TestPanelEvoGenomes());
		runner.addCase(new TestNpPdEvoPalette());
		runner.addCase(new TestPanelFitness());
		runner.addCase(new TestEvoVariation());
		runner.addCase(new TestEvoScaling());
		runner.addCase(new TestNmaAttr());
		runner.addCase(new TestAuthorHoles());
		runner.addCase(new TestNmaFitness());
		runner.addCase(new TestHybridWasm());
		runner.addCase(new TestIndicatorLibHygiene());
		Report.create(runner);
		runner.run();
	}
}

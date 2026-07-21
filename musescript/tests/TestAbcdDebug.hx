package musescript.tests;

import musescript.indicators.lib.Abcd;
import musescript.harness.Bar;

class TestAbcdDebug {
	static function main() {
		Sys.println("Testing Abcd...");
		var a = new Abcd();
		var bars:Array<Bar> = [];
		for (i in 0...10) {
			bars.push({open: 100.0 + i, high: 100.0 + i + 1.0, low: 100.0 + i - 1.0, close: 100.0 + i, volume: 100.0, time: i, index: i});
		}
		for (b in bars) {
			var v = a.update(b);
		}
		Sys.println("Abcd test passed!");
	}
}

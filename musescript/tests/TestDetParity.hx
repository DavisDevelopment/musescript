package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.ew.mcmc.DetParityDump;

/**
 * Bucket D4 — lock DetParityDump.render() against testdata/det-parity.golden.txt.
 * Cross-target JVM↔node auto-diff: `tools/det_parity_ci.ps1` / `tools/det_parity_ci.sh`.
 */
class TestDetParity extends Test {
	static function loadGolden():String {
		var paths = [
			"testdata/det-parity.golden.txt",
			"../testdata/det-parity.golden.txt"
		];
		for (p in paths) {
			if (sys.FileSystem.exists(p)) {
				var s = sys.io.File.getContent(p);
				return StringTools.replace(s, "\r\n", "\n");
			}
		}
		return null;
	}

	public function testRenderMatchesGoldenFile() {
		var got = StringTools.replace(DetParityDump.render(), "\r\n", "\n");
		var golden = loadGolden();
		Assert.isTrue(golden != null && golden.length > 0, "missing testdata/det-parity.golden.txt");
		// Trim possible trailing whitespace from editors
		got = StringTools.trim(got) + "\n";
		golden = StringTools.trim(golden) + "\n";
		Assert.equals(golden, got, "DetParityDump.render drifted from golden — regenerate testdata if intentional");
	}

	public function testRenderIdempotent() {
		Assert.equals(DetParityDump.render(), DetParityDump.render());
	}
}

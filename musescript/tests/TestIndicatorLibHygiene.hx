package musescript.tests;

import utest.Assert;
import utest.Test;

/**
 * OPEN_ITEMS 1.2 — runtime grep twin of `IndicatorRegistryMacro.checkShiftBan`.
 *
 * The compile-time scan fails any IndicatorRegistry build; this test keeps the
 * invariant greppable from `.\run.ps1 test` even if someone comments the macro
 * out. Scope is `musescript/indicators/lib/` only (not `prim/`). `.unshift(` is
 * allowed — the pattern requires a preceding `.` immediately before `shift`.
 */
class TestIndicatorLibHygiene extends Test {
	static inline var LIB_DIR = "musescript/indicators/lib";
	static var SHIFT_CALL_RE = ~/\.shift\s*\(/;

	public function testShiftCallBannedInIndicatorLib() {
		Assert.isTrue(sys.FileSystem.exists(LIB_DIR) && sys.FileSystem.isDirectory(LIB_DIR),
			"missing " + LIB_DIR + " (run tests from repo root)");
		var files = sys.FileSystem.readDirectory(LIB_DIR);
		files.sort(Reflect.compare);
		var nHx = 0;
		var hits:Array<String> = [];
		for (f in files) {
			if (!StringTools.endsWith(f, ".hx")) continue;
			nHx++;
			var src = sys.io.File.getContent(LIB_DIR + "/" + f);
			var lines = src.split("\n");
			for (i in 0...lines.length) {
				if (SHIFT_CALL_RE.match(lines[i]))
					hits.push(f + ":" + (i + 1));
			}
		}
		Assert.isTrue(nHx > 100, "expected a populated indicators/lib/, scanned " + nHx);
		Assert.equals(0, hits.length,
			"OPEN_ITEMS 1.2: `.shift()` banned in indicators/lib/ — use RingBuffer. Hits: "
			+ hits.join(", "));
	}

	public function testBanPatternDoesNotMatchUnshift() {
		Assert.isFalse(SHIFT_CALL_RE.match("buf.unshift(v)"), "unshift must remain legal");
		Assert.isTrue(SHIFT_CALL_RE.match("window.shift()"));
		Assert.isTrue(SHIFT_CALL_RE.match("buf.shift (x)"));
	}
}

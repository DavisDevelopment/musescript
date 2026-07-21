package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.compile.CommonSubexprElim;
import musescript.compile.MusePrinter;
import musescript.compile.MuseCompiler;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * CommonSubexprElim (2026-07-20): deduplicates a repeated, PURE, non-trivial value within the
 * same flat statement list (a duplicate `Assign` RHS aliases to the earlier local; a duplicate
 * `when` condition hoists to one shared temp). Deliberately narrow — see the pass's own doc
 * comment for why. The one test that matters most here isn't "does it dedupe" but "does it ever
 * touch a CALL" — CallsiteIds assigns stateful builtins (crossover/rising/...) identity per
 * syntactic call site specifically because two textually-identical calls can carry independent
 * runtime state, so conflating them would be a correctness bug, not just a missed optimization.
 */
class TestCommonSubexprElim extends Test {
	public function testDuplicateAssignRhsAliasesToEarlierLocal() {
		var src = "strategy Dup { onBar {\n"
			+ "  a = (high - low) * 2.0\n"
			+ "  b = (high - low) * 2.0\n"
			+ "  when a > 0.0: { long(1); }\n"
			+ "} }";
		var printed = new MusePrinter().printProgram(CommonSubexprElim.transform(new MuseParser().parse(src)));
		Assert.isTrue(StringTools.contains(printed, "b = a"));
	}

	public function testDuplicateWhenConditionHoistsToOneSharedTemp() {
		var src = "strategy DupWhen { onBar {\n"
			+ "  when (high - low) > 1.0: { long(1); }\n"
			+ "  when (high - low) > 1.0: { short(1); }\n"
			+ "} }";
		var printed = new MusePrinter().printProgram(CommonSubexprElim.transform(new MuseParser().parse(src)));
		var occurrences = 0, idx = 0;
		while (true) { idx = printed.indexOf("(high - low)", idx); if (idx < 0) break; occurrences++; idx++; }
		Assert.equals(1, occurrences);
	}

	public function testSingleOccurrenceValueIsNotWrappedInATemp() {
		var src = "strategy Single { onBar {\n  when (high - low) > 1.0: { long(1); }\n} }";
		var printed = new MusePrinter().printProgram(CommonSubexprElim.transform(new MuseParser().parse(src)));
		Assert.isFalse(StringTools.contains(printed, "__cse"));
	}

	public function testRepeatedStatefulCallIsNeverDeduplicated() {
		var src = "strategy CallSafety { onBar {\n"
			+ "  a = rising(close, 3)\n"
			+ "  b = rising(close, 3)\n"
			+ "  when a: { long(1); }\n"
			+ "} }";
		var printed = new MusePrinter().printProgram(CommonSubexprElim.transform(new MuseParser().parse(src)));
		Assert.isFalse(StringTools.contains(printed, "b = a"));
	}

	public function testDuplicateAssignBehaviorPreserved() {
		var src = "strategy Dup { onBar {\n"
			+ "  a = (high - low) * 2.0\n"
			+ "  b = (high - low) * 2.0\n"
			+ "  when a > 0.0: { long(1); }\n"
			+ "} }";
		var feed = BarFeed.synthetic(300, 8);
		var before = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		#if js
		var h = new HarnessContext();
		Reflect.setField(h, "feed", feed);
		var after = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(h);
		Assert.equals(before.trades, after.trades);
		Assert.floatEquals(before.finalEquity, after.finalEquity);
		#end
	}

	public function testDuplicateWhenBehaviorPreserved() {
		var src = "strategy DupWhen { onBar {\n"
			+ "  when (high - low) > 1.0: { long(1); }\n"
			+ "  when (high - low) > 1.0: { short(1); }\n"
			+ "} }";
		var feed = BarFeed.synthetic(300, 8);
		var before = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		#if js
		var h = new HarnessContext();
		Reflect.setField(h, "feed", feed);
		var after = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(h);
		Assert.equals(before.trades, after.trades);
		Assert.floatEquals(before.finalEquity, after.finalEquity);
		#end
	}

	public function testCallSafetyBehaviorPreserved() {
		var src = "strategy CallSafety { onBar {\n"
			+ "  a = rising(close, 3)\n"
			+ "  b = rising(close, 3)\n"
			+ "  when a: { long(1); }\n"
			+ "} }";
		var feed = BarFeed.synthetic(300, 8);
		var before = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), feed);
		#if js
		var h = new HarnessContext();
		Reflect.setField(h, "feed", feed);
		var after = MuseCompiler.compileEx(new MuseParser().parse(src), { target: "js", strict: true }).fn(h);
		Assert.equals(before.trades, after.trades);
		Assert.floatEquals(before.finalEquity, after.finalEquity);
		#end
	}
}

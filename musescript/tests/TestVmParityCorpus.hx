package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.harness.BarFeed;
import musescript.evo.CorpusSeed;
import musescript.evo.Expand;
import musescript.evo.RegistryPalette;
import musescript.evo.StrategyGenome;
import musescript.vm.VmParityDump;

/**
 * V2 standing parity gate (BYTECODE_VM_TODO.md): runs the interp↔VM byte-identity
 * check over the REAL evo gen-0 corpus (indicator-cross seeds + fib + fourier,
 * built via `CorpusSeed` exactly as `CorpusEvoRun` seeds them) plus the P0 subset
 * programs. The invariant is `diverged == 0` — a program either runs on the VM
 * byte-identically to the interp, or cleanly falls back (`VmUnsupported`), never
 * silently differs. Today most genome seeds are `fallback` (they use indicators/
 * crossovers — out of the P0 subset); that bucket shrinks as V3 lands `SERIES`/
 * `CROSS`/`LOOKBACK`, and every newly-covered genome is byte-checked here for free.
 */
class TestVmParityCorpus extends Test {
	// Subset programs guarantee the gate has LIVE coverage (identical > 0) today,
	// so a regression that makes the VM silently fall back everywhere is caught too.
	static final SUBSET:Array<String> = [
		"strategy S { onBar {\n  when close > open: { long(1); }\n  when close < open: { flat(); }\n} }",
		"strategy S { onBar {\n  a = (high - low) * 2.0\n  when a > 1.0: { long(1); }\n  when a <= 1.0: { flat(); }\n} }",
		"strategy S { onBar {\n  when (close > open) && (high > low): { long(2); }\n  when close < open: { short(1); }\n} }"
	];

	public function testEvoCorpusInterpVsVmNeverDiverges() {
		var items:Array<VmParityItem> = [];
		for (src in SUBSET) items.push({ name: "subset:" + items.length, src: src });

		// Real gen-0 seeds — bounded name sample keeps CI fast; the harness accepts any size.
		var names = RegistryPalette.compatibleNames();
		var sample = names.length > 24 ? names.slice(0, 24) : names;
		var genomes:Array<StrategyGenome> = CorpusSeed.seedFromIndicators(sample)
			.concat(CorpusSeed.seedFromFibRetracement())
			.concat(CorpusSeed.seedFromFourierProjection());
		for (g in genomes) {
			var src = try Expand.expand(g) catch (_:Dynamic) null;
			if (src != null) items.push({ name: g.name, src: src });
		}

		var rep = VmParityDump.run(items, BarFeed.synthetic(400, 11));
		// Visible in CI logs so we can watch `fallback` shrink as V3 broadens coverage.
		trace(VmParityDump.format(rep));
		Assert.equals(0, rep.diverged.length, "interp/VM divergence:\n" + VmParityDump.format(rep));
		Assert.isTrue(rep.identical > 0, "expected the P0 subset programs to run on the VM (identical > 0)");
	}
}

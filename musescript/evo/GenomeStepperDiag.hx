package musescript.evo;

import musescript.harness.Bar;

/**
 * Throwaway diagnostic for the open GenomeStepper/raw-MuseInterp fault (see
 * `MurmurationSim x corpus-evo integration` memory note, 2026-07-23/24): ~24% of the real
 * corpus-seeded genome population crashes `MuseInterp.execBar` with a `ClassCastException`
 * (a stateful-builtin closure reaching `binop` as if it were a numeric value), even after
 * `GenomeStepper` runs the full `MuseCompiler.compileEx` transform pipeline. Iterates the EXACT
 * same seed population `CorpusEvoRun.hx`'s gen 0 builds, feeds each genome a short synthetic bar
 * sequence, and prints the first few failing genomes' NAME + EXPANDED SOURCE (not just a fault
 * count) so the actual triggering construct can be inspected directly.
 */
class GenomeStepperDiag {
	static function main() {
		var allowed = new Map<String, Bool>();
		for (n in RegistryPalette.compatibleNames()) allowed.set(n, true);
		var tournament = CorpusSeed.seedFromDirectory("examples/strategy-tournament", allowed);
		var indicatorNames = [for (n in allowed.keys()) if (n != "fourier_projection") n];
		var indicatorSeeds = CorpusSeed.seedFromIndicators(indicatorNames);
		var fibSeeds = CorpusSeed.seedFromFibRetracement();
		var fourierSeeds = CorpusSeed.seedFromFourierProjection();
		var seedPop = tournament.genomes.concat(indicatorSeeds).concat(fibSeeds).concat(fourierSeeds);
		Sys.println('seed population: ${seedPop.length} genomes (${tournament.genomes.length} corpus-derived + ${indicatorSeeds.length} indicator + ${fibSeeds.length} fib + ${fourierSeeds.length} fourier)');

		var bars:Array<Bar> = [];
		var price = 100.0;
		var rng = 12345;
		for (i in 0...500) {
			rng = (rng * 1103515245 + 12345) & 0x7fffffff;
			var noise = ((rng % 1000) / 1000.0 - 0.5) * 2.0;
			var o = price;
			var c = price * (1 + noise * 0.02);
			var h = Math.max(o, c) * 1.003;
			var l = Math.min(o, c) * 0.997;
			// DIAG: attach the same aux columns MurmurationTape.toBars puts on every bar --
			// testing whether the aux `data` map's mere PRESENCE (regardless of GenomeStepper's
			// own logic) is what triggers the JVM-only fault seen under --compete.
			var data = new Map<String, Float>();
			data.set("ret", noise * 0.01);
			data.set("mom", noise * 0.005);
			data.set("value_gap", noise * 0.002);
			data.set("vol", Math.abs(noise) * 0.01);
			data.set("imb", noise * 0.1);
			data.set("spread", 0.02);
			data.set("g", noise * 0.001);
			data.set("infl", 0.0);
			data.set("inv_norm", 0.0);
			data.set("unreal_pnl", 0.0);
			data.set("capital_norm", 0.5);
			bars.push({open: o, high: h, low: l, close: c, volume: 1000.0, time: i * 1.0, index: i, data: data});
			price = c;
		}

		// Mirrors --compete's EXACT pattern: ALL steppers constructed upfront (each constructor
		// call resets TradeBuiltins' legacy GLOBAL slot-keyed cross-state -- see
		// TradeBuiltins.resetCrossState's doc comment), then decide() calls INTERLEAVED
		// round-robin across genomes tick-by-tick (matching MurmurationSim.step()'s per-tick
		// agent loop), not one genome run to completion before the next starts. Testing whether
		// cross-instance interleaving -- not aux data, not the JVM target alone -- is what
		// triggers the fault.
		var steppers = [for (g in seedPop) new GenomeStepper(g)];
		var errMsgs = [for (_ in seedPop) ""];
		for (b in bars) {
			for (i in 0...steppers.length) {
				if (steppers[i].faulted) continue;
				try {
					steppers[i].decide(b);
				} catch (e:Dynamic) {
					errMsgs[i] = Std.string(e);
				}
			}
		}
		var failed = 0;
		var shown = 0;
		var seenPatterns = new Map<String, Bool>();
		for (i in 0...seedPop.length) {
			if (errMsgs[i] == "") continue;
			failed++;
			if (!seenPatterns.exists(errMsgs[i]) && shown < 8) {
				seenPatterns.set(errMsgs[i], true);
				shown++;
				Sys.println('\n--- FAULT #$shown (genome "${seedPop[i].name}") ---');
				Sys.println('error: ${errMsgs[i]}');
				Sys.println(Expand.expand(seedPop[i]));
			}
		}
		Sys.println('\n${failed}/${seedPop.length} genomes faulted, ${[for (k in seenPatterns.keys()) k].length} distinct error messages, showed $shown examples');
	}
}

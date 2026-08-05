package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.ew.mcmc.DetParityDump;
import musescript.evo.CorpusSeed;
import musescript.evo.Fitness;
import musescript.evo.RegistryPalette;
import musescript.evo.StrategyGenome;
import musescript.evo.Variation;
import musescript.harness.BarFeed;

/**
 * preferVm soak / standing gate (BYTECODE_VM_TODO V5–V6): catch Fitness-path bit-drift
 * with `Fitness.preferVm` default ON.
 *
 * Distinct from `TestBytecodeVmParity` / `TestVmParityCorpus` (direct MuseVm.runBacktest):
 * this exercises `evaluateVm` / `vmParityCheck` / `evaluate()` with `preferVm=true` — the
 * same route CorpusEvoRun uses after its startup self-check (opt out with `--no-vm`).
 *
 * Soak tooling (`tools/prefer_vm_soak.*`) remains available as a regression harness.
 */
class TestPreferVmSoak extends Test {
	public function testPreferVmDefaultIsOn() {
		Assert.isTrue(Fitness.preferVm, "preferVm must default ON after soak green (opt out with Fitness.preferVm=false / --no-vm)");
	}

	/** DetParityDump VM tiers stay match=1 (cheap foundation lock; golden covers JVM↔node too). */
	public function testDetParityVmTiersMatch() {
		var dump = DetParityDump.render();
		Assert.isTrue(dump.indexOf("-- MuseVm vs MuseInterp") >= 0);
		Assert.isTrue(dump.indexOf("-- MuseVm np_mean(window)") >= 0);
		Assert.isTrue(dump.indexOf("-- MuseVm np handle") >= 0);
		Assert.isTrue(dump.indexOf("-- MuseVm pd_rank1d handle") >= 0);
		var matches = 0;
		for (line in dump.split("\n")) {
			if (StringTools.startsWith(StringTools.trim(line), "match=")) {
				Assert.equals("match=1", StringTools.trim(line), "DetParityDump VM tier drifted:\n" + dump);
				matches++;
			}
		}
		Assert.isTrue(matches >= 3, "expected >=3 match= lines (interp+np+handle VM tiers), got " + matches);
	}

	/** Gen-0 corpus through Fitness.vmParityCheck — sacred-path twin of TestVmParityCorpus. */
	public function testCorpusVmParityCheckClean() {
		var prev = Fitness.preferVm;
		Fitness.preferVm = false;
		var genomes = corpusSeeds();
		var bars = BarFeed.synthetic(400, 11).all();
		var pc = Fitness.vmParityCheck(genomes, bars, 0);
		Fitness.preferVm = prev;
		trace('preferVm soak corpus: ${pc.identical}/${pc.covered} identical'
			+ ' (${pc.fallback} fallback of ${genomes.length})');
		if (pc.firstError != null)
			Assert.fail("vm-error on corpus soak: " + pc.firstError);
		if (pc.firstMismatch != null)
			Assert.fail("Fitness-path VM bit-drift (corpus): " + pc.firstMismatch);
		Assert.equals(pc.covered, pc.identical);
		Assert.isTrue(pc.covered > 0, "soak needs VM-covered gen-0 genomes");
	}

	/**
	 * With preferVm armed, evaluate() must claim backend "vm" on covered genomes and match
	 * Expand→interp (preferVm off) on trades + finalEquity bits.
	 */
	public function testPreferVmEvaluateRouteParity() {
		var prevNma = Fitness.preferNma;
		var prevVm = Fitness.preferVm;
		Fitness.preferNma = false;
		var bars = BarFeed.synthetic(200, 5).all();
		var sample = corpusSeeds();
		if (sample.length > 32) sample = sample.slice(0, 32);
		var routed = 0;
		for (g in sample) {
			Fitness.preferVm = false;
			var ref = Fitness.evaluate(g, bars, "js", false);
			if (!ref.ok) continue;
			var direct = Fitness.evaluateVm(g, bars);
			if (!direct.ok) continue; // out-of-subset — Expand→interp fallback is fine
			Fitness.preferVm = true;
			var via = Fitness.evaluate(g, bars, "js", false);
			Assert.isTrue(via.ok, g.name + " preferVm evaluate failed: " + via.error);
			Assert.equals("vm", via.backend, g.name + " expected backend=vm, got " + via.backend);
			Assert.equals(ref.trades, via.trades, g.name + " trades drifted under preferVm");
			Assert.equals(
				haxe.io.FPHelper.doubleToI64(ref.finalEquity),
				haxe.io.FPHelper.doubleToI64(via.finalEquity),
				g.name + " finalEquity bits drifted under preferVm");
			routed++;
		}
		Fitness.preferNma = prevNma;
		Fitness.preferVm = prevVm;
		Assert.isTrue(routed > 0, "preferVm soak expected >=1 VM-routed corpus genome");
		trace("preferVm soak evaluate route: " + routed + " genomes backend=vm bit-identical");
	}

	/**
	 * Evolved stress through Fitness.vmParityCheck (Variation rounds). Silent divergence fails;
	 * fallback is allowed (objects/match/… grow out of subset).
	 */
	public function testEvolvedVmParityCheckNeverDiverges() {
		var prev = Fitness.preferVm;
		Fitness.preferVm = false;
		var pool = RegistryPalette.compatibleNames();
		var v = new Variation(4242, pool);
		var pop:Array<StrategyGenome> = CorpusSeed.seedFromIndicators(pool.length > 16 ? pool.slice(0, 16) : pool)
			.concat(CorpusSeed.seedFromFibRetracement());
		var evolved:Array<StrategyGenome> = [];
		// Two rounds keep soak wall time sensible while still stressing grown ASTs.
		for (_ in 0...2) {
			var next:Array<StrategyGenome> = [];
			for (i in 0...pop.length) {
				var m = try v.pointMutate(pop[i]) catch (_:Dynamic) null;
				if (m != null) { evolved.push(m); next.push(m); }
				var x = try v.subtreeCrossover(pop[i], pop[(i + 1) % pop.length]) catch (_:Dynamic) null;
				if (x != null) { evolved.push(x); next.push(x); }
				var mm = try v.mutate(pop[i]) catch (_:Dynamic) null;
				if (mm != null) evolved.push(mm);
			}
			pop = next.length > 0 ? next : pop;
		}
		Assert.isTrue(evolved.length > 50, "evolved soak batch too small: " + evolved.length);
		var bars = BarFeed.synthetic(300, 7).all();
		var pc = Fitness.vmParityCheck(evolved, bars, 0);
		Fitness.preferVm = prev;
		trace('preferVm soak evolved: ${pc.identical}/${pc.covered} identical'
			+ ' (${pc.fallback} fallback of ${evolved.length})');
		// Same policy as CorpusEvoRun: abort only on bit mismatch. vm-error on evolved
		// genomes (invalid params from Variation) counts as fallback — both tiers refuse.
		if (pc.firstError != null)
			trace("preferVm soak evolved first vm-error (non-fatal): " + pc.firstError);
		if (pc.firstMismatch != null)
			Assert.fail("Fitness-path VM bit-drift (evolved): " + pc.firstMismatch);
		Assert.equals(pc.covered, pc.identical);
	}

	static function corpusSeeds():Array<StrategyGenome> {
		var names = RegistryPalette.compatibleNames();
		var sample = names.length > 24 ? names.slice(0, 24) : names;
		return CorpusSeed.seedFromIndicators(sample)
			.concat(CorpusSeed.seedFromFibRetracement())
			.concat(CorpusSeed.seedFromFourierProjection());
	}
}

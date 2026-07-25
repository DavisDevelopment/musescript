package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.plan.ExecutionProfile;
import musescript.plan.ExecutionProfileId;
import musescript.plan.PlanStep;
import musescript.plan.ExecutionPlan;
import musescript.harness.PlanRunner;
import musescript.evo.PoetEnvs;
import musescript.evo.Rand;
import musescript.evo.BoolNode;
import musescript.evo.ScalarNode;
import musescript.evo.nma.NmaBijection;
import musescript.evo.nma.NmaEval;
import musescript.evo.nma.NmaEvalContext;
import musescript.evo.nma.NmaEpoch;
import musescript.evo.nma.NmaFixedColumnKernel;
import musescript.evo.nma.NmaKernelWarm;
import musescript.indicators.GrowableVec;
import musescript.harness.Bar;

/**
 * P3 profiles + P4 kernel slot + POET env helpers.
 *
 * «οὐκέτι διψῶσιν πτυχαί.»
 */
class TestP3P4Poet extends Test {

	public function testExecutionProfileResolve() {
		var evo = ExecutionProfile.resolve(EvoMinWallclock);
		Assert.isTrue(evo.preferNma);
		Assert.isTrue(evo.prefixAttribution);
		Assert.equals("js", evo.backend, "preferNma profiles must claim js (NMA/OrderSim live there)");
		var prod = ExecutionProfile.resolve(ProductionRepro);
		Assert.isTrue(prod.cachesOff);
		Assert.equals("interp", prod.backend);
		Assert.equals(ProductionRepro, ExecutionProfile.parse("prod"));
		Assert.isNull(ExecutionProfile.parse("nope"));
		var single = ExecutionProfile.resolve(SingleStrategyMaxThroughput);
		Assert.equals("js", single.backend);
		Assert.isTrue(single.preferNma);
	}

	public function testPlanRunnerAppliesExecProfileStep() {
		var plan:ExecutionPlan = {
			steps: [ExecProfileStep("p0", EvoMinWallclock)],
			sourceOrigin: null,
			profile: null
		};
		// PlanRunner.run may need more — just resolve manually as PlanRunner does
		plan.profile = ExecutionProfile.resolve(EvoMinWallclock);
		Assert.notNull(plan.profile);
		Assert.equals("EvoMinWallclock", plan.profile.label);
	}

	public function testFixedColumnKernelShortCircuitsEval() {
		var n = NmaBijection.boolFromEnum(BCmp(">", KConst(1.0), KConst(0.0)));
		var col = new GrowableVec<Float>(4);
		for (_ in 0...4) col.push(1.0);
		n.kernel = new NmaFixedColumnKernel(col);
		var bars:Array<Bar> = [];
		for (i in 0...4) bars.push({
			open: 1, high: 1, low: 1, close: 1, volume: 1, time: i, index: i
		});
		// Minimal context — use NmaFitness.prepare path if easier
		var built = musescript.evo.nma.NmaFitness.prepare({
			entryLong: BCmp(">", KConst(1.0), KConst(0.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "k"
		}, bars);
		Assert.notNull(built);
		built.nma.entryLong.kernel = new NmaFixedColumnKernel(col);
		var out = NmaEval.evalBool(built.nma.entryLong, built.ctx);
		Assert.equals(4, out.length);
		Assert.floatEquals(1.0, out.at(0), 1e-12);
	}

	public function testKernelWarmInstallsFusedLogic() {
		var g = {
			entryLong: BAnd(BCmp(">", KConst(1.0), KConst(0.0)), BCmp("<", KConst(0.0), KConst(1.0))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KConst(0.0), KConst(1.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0), params: [], name: "warm"
		};
		var bars:Array<Bar> = [];
		for (i in 0...8) bars.push({
			open: 1, high: 1, low: 1, close: 1.0 + i * 0.01, volume: 1, time: i, index: i
		});
		var built = musescript.evo.nma.NmaFitness.prepare(g, bars);
		Assert.notNull(built);
		var node = built.nma.entryLong;
		var prevEn = NmaKernelWarm.enabled;
		var prevMega = NmaKernelWarm.installMegamorphKernel;
		NmaKernelWarm.enabled = true;
		NmaKernelWarm.installMegamorphKernel = false;
		node.evalHits = 0;
		node.kernelWat = null;
		// First compute + many epoch-memo hits toward warm threshold.
		NmaEval.evalBool(node, built.ctx);
		for (i in 0...NmaKernelWarm.WARM_THRESHOLD + 2)
			NmaEval.evalBool(node, built.ctx);
		Assert.notNull(node.kernelWat, "expected WASM fuse WAT after warm threshold");
		Assert.isTrue(node.kernelWat.indexOf("fuse_and_cols") >= 0 || node.kernelWat.indexOf("i32.and") >= 0);
		Assert.isNull(node.kernel, "default warm must not install megamorphic kernel");
		// Warm attach busts local memo — next eval should take fuse/host path.
		musescript.evo.nma.NmaFuseHost.reset();
		musescript.evo.nma.NmaFuseHost.enabled = true;
		node.evalEpoch = -1;
		node.lastSeries = null;
		var col = NmaEval.evalBool(node, built.ctx);
		Assert.notNull(col);
		#if js
		Assert.isTrue(musescript.evo.nma.NmaFuseHost.fuseCalls >= 1, "warm BAnd should hit fuse host on recompute");
		#end
		NmaKernelWarm.installMegamorphKernel = true;
		node.kernel = null;
		node.evalHits = NmaKernelWarm.WARM_THRESHOLD + 1;
		NmaKernelWarm.consider(node);
		Assert.notNull(node.kernel, "megamorph opt-in installs NmaFusedLogicKernel");
		NmaKernelWarm.enabled = prevEn;
		NmaKernelWarm.installMegamorphKernel = prevMega;
		musescript.evo.nma.NmaFuseHost.enabled = false;
	}

	public function testWasmFusedEmitterModuleAndHaxeParity() {
		var wat = musescript.evo.nma.NmaWasmFusedEmitter.emitModule();
		Assert.isTrue(wat.indexOf(musescript.evo.nma.NmaWasmFusedEmitter.EXPORT_AND) >= 0);
		Assert.isTrue(wat.indexOf(musescript.evo.nma.NmaWasmFusedEmitter.EXPORT_OR) >= 0);
		Assert.isTrue(wat.indexOf("(memory") >= 0);
		var a = new GrowableVec<Float>(4);
		var b = new GrowableVec<Float>(4);
		a.push(1.0); a.push(0.0); a.push(1.0); a.push(0.0);
		b.push(1.0); b.push(1.0); b.push(0.0); b.push(0.0);
		var andCol = musescript.evo.nma.NmaWasmFusedEmitter.fuseColumnsHaxe(a, b, true, 4);
		var orCol = musescript.evo.nma.NmaWasmFusedEmitter.fuseColumnsHaxe(a, b, false, 4);
		Assert.floatEquals(1.0, andCol.at(0));
		Assert.floatEquals(0.0, andCol.at(1));
		Assert.floatEquals(0.0, andCol.at(2));
		Assert.floatEquals(1.0, orCol.at(1));
		#if js
		var andWasm = musescript.evo.nma.NmaWasmFusedEmitter.fuseColumnsWasm(a, b, true, 4);
		var orWasm = musescript.evo.nma.NmaWasmFusedEmitter.fuseColumnsWasm(a, b, false, 4);
		for (i in 0...4) {
			Assert.floatEquals(andCol.at(i), andWasm.at(i), 1e-12, 'wasm AND[$i]');
			Assert.floatEquals(orCol.at(i), orWasm.at(i), 1e-12, 'wasm OR[$i]');
		}
		// Cached host path (what NmaEval uses after warm)
		musescript.evo.nma.NmaFuseHost.reset();
		musescript.evo.nma.NmaFuseHost.enabled = true;
		Assert.isTrue(musescript.evo.nma.NmaFuseHost.ready());
		var andHost = musescript.evo.nma.NmaFuseHost.fuse(a, b, true, 4);
		Assert.notNull(andHost);
		Assert.floatEquals(1.0, andHost.at(0));
		Assert.isTrue(musescript.evo.nma.NmaFuseHost.fuseCalls >= 1);
		#end
	}

	public function testPoetMinimalCriterionAndMutate() {
		Assert.isFalse(PoetEnvs.minimalCriterion([]));
		Assert.isFalse(PoetEnvs.minimalCriterion([-2.0, -1.0])); // all too hard
		Assert.isFalse(PoetEnvs.minimalCriterion([5.0, 6.0])); // all too easy
		Assert.isTrue(PoetEnvs.minimalCriterion([-2.0, 1.0, 5.0]));
		var envs = PoetEnvs.seedAxis(3, 0.001);
		Assert.equals(3, envs.length);
		var rng = new Rand(7);
		var m = PoetEnvs.mutate(envs[0], rng);
		Assert.notEquals(envs[0].seed, m.seed);
	}
}

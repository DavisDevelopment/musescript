package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.ew.EwPhiParams;
import musescript.indicators.offline.EwFinetuneExport;
import musescript.indicators.offline.PhiParamsDump;

/** Offline EwPhiParams export / finetune load smoke tests. */
class TestEwPhiFinetune extends Test {
	public function testExportSyntheticProducesRows() {
		var bars = EwFinetuneExport.syntheticBars();
		var ex = new EwFinetuneExport();
		var n = ex.exportFromBars(bars, { swingThreshold: 0.02, horizon: 5 });
		var closes = [for (b in bars) b.close];
		ex.fillForwardReturns(closes, 5);
		Assert.isTrue(n >= 0);
		Assert.isTrue(ex.rows.length >= 0);
		if (ex.rows.length > 0) {
			var r = ex.rows[ex.rows.length - 1];
			Assert.isTrue(Math.isFinite(r.close));
			Assert.isTrue(r.hypLabel != null && r.hypLabel.length > 0);
		}
		var json = ex.toJson(true);
		Assert.isTrue(json.indexOf('"rows"') >= 0);
	}

	public function testApplyMapChangesBestHit() {
		var p = new EwPhiParams();
		p.fibHitTol = 0.02;
		p.w2RetraceTargets[0] = 0.55;
		p.w2RetraceN = 1;
		var ratio = 0.57;
		var hitTight = p.bestHit(ratio, p.w2RetraceTargets, 1);

		var m = PhiParamsDump.toMap(p);
		m.set("fibHitTol", 0.25);
		m.set("w2Retrace_0", 0.55);
		var pLoose = PhiParamsDump.applyMap(m, new EwPhiParams());
		var hitLoose = pLoose.bestHit(ratio, pLoose.w2RetraceTargets, 1);

		Assert.isTrue(hitLoose > hitTight);
		Assert.floatEquals(0.55, pLoose.w2RetraceTargets[0], 1e-9);
	}

	public function testLoadFromMapRoundtrip() {
		var base = new EwPhiParams();
		base.fibHitTol = 0.11;
		base.w2RetraceTargets[1] = 0.64;
		var m = PhiParamsDump.toMap(base);
		var loaded = EwPhiParams.loadFromMap(m);
		Assert.floatEquals(0.11, loaded.fibHitTol, 1e-9);
		Assert.floatEquals(0.64, loaded.w2RetraceTargets[1], 1e-9);
	}

	#if (sys || node)
	public function testJsonFileLoad() {
		var path = "build/test_finetuned_phi.json";
		if (!sys.FileSystem.exists("build")) sys.FileSystem.createDirectory("build");
		var base = new EwPhiParams();
		base.fibHitTol = 0.13;
		PhiParamsDump.saveJsonFile(path, base);
		var loaded = EwPhiParams.loadFromJsonFile(path);
		Assert.floatEquals(0.13, loaded.fibHitTol, 1e-9);
	}
	#end

	public function testFinetunedParamsAffectBestHit() {
		var p = new EwPhiParams();
		var ratio = 0.618;
		var defaultHit = p.bestHit(ratio, p.w2RetraceTargets, p.w2RetraceN);

		var tuned = p.clone();
		tuned.w2RetraceTargets[0] = ratio;
		tuned.w2RetraceN = 1;
		tuned.fibHitTol = 0.04;
		var tunedHit = tuned.bestHit(ratio, tuned.w2RetraceTargets, 1);

		Assert.isTrue(tunedHit > defaultHit || tunedHit >= 0.99);
	}
}

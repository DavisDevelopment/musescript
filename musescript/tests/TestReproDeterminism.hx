package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.repro.DeterminismProof;
import musescript.repro.EquityDigest;
import musescript.repro.ReproStamp;
import musescript.runtime.MuseRuntime;
import musescript.ew.mcmc.DetParityDump;

/**
 * Initiative 4 — reproducibility product surface (determinism proof + seed stamp).
 */
class TestReproDeterminism extends Test {
	static inline var BUY_HOLD = "
strategy BuyHold {
  onBar {
    when position() == 0: long()
  }
}
";

	function testEquityDigestEmpty() {
		Assert.equals("empty", EquityDigest.of(null));
		Assert.equals("empty", EquityDigest.of([]));
	}

	function testEquityDigestBitIdentity() {
		var a = [100.0, 101.5, 99.25];
		var b = [100.0, 101.5, 99.25];
		var c = [100.0, 101.5, 99.2500001];
		Assert.isTrue(EquityDigest.identical(a, b));
		Assert.equals(EquityDigest.of(a), EquityDigest.of(b));
		Assert.isFalse(EquityDigest.identical(a, c));
		Assert.notEquals(EquityDigest.of(a), EquityDigest.of(c));
	}

	function testReproStampDefaults() {
		var s = ReproStamp.make();
		Assert.equals(42, s.seed);
		Assert.equals(42, s.bootSeed);
		Assert.equals(1, s.schemaVersion);
		var j:Dynamic = s.toJson();
		Assert.equals(42, Reflect.field(j, "seed"));
	}

	function testFoundationDigestStable() {
		var d1 = DeterminismProof.foundationDigest();
		var d2 = DeterminismProof.foundationDigest();
		Assert.equals(16, d1.length);
		Assert.equals(d1, d2);
		// Same content as hashing DetParityDump.render directly.
		Assert.equals(d1, haxe.crypto.Sha1.encode(DetParityDump.render()).substr(0, 16));
	}

	function testMuseRuntimeAttachesRepro() {
		var bars = synthBars(80, 7);
		var r:Dynamic = MuseRuntime.run(BUY_HOLD, bars, { tier: "js", instrument: true, seed: 7 });
		Assert.equals(true, Reflect.field(r, "ok"), "run failed: " + Std.string(Reflect.field(r, "error")));
		var repro:Dynamic = Reflect.field(r, "repro");
		Assert.notNull(repro);
		Assert.equals(7, Reflect.field(repro, "seed"));
		Assert.equals(7, Reflect.field(repro, "bootSeed"));
		Assert.equals("js", Reflect.field(repro, "backend"));
		var dig:String = Reflect.field(r, "equityDigest");
		Assert.notNull(dig);
		Assert.equals(dig, EquityDigest.of(Reflect.field(r, "equity")));
	}

	function testProveInterpJsBitIdentical() {
		var bars = synthBars(120, 42);
		var proof:Dynamic = DeterminismProof.prove(BUY_HOLD, bars, {
			seed: 42,
			engines: ["interp", "js"]
		});
		Assert.equals(true, Reflect.field(proof, "ok"));
		Assert.equals(true, Reflect.field(proof, "identical"));
		Assert.equals("BIT_IDENTICAL", Reflect.field(proof, "badge"));
		Assert.equals(42, Reflect.field(proof, "seed"));
		Assert.notNull(Reflect.field(proof, "equityDigest"));
		Assert.notNull(Reflect.field(proof, "foundationDigest"));
		var engines:Array<Dynamic> = Reflect.field(proof, "engines");
		Assert.equals(2, engines.length);
		Assert.equals(Reflect.field(engines[0], "equityDigest"), Reflect.field(engines[1], "equityDigest"));
	}

	function testProveIdempotentDigest() {
		var bars = synthBars(60, 3);
		var a:Dynamic = MuseRuntime.proveDeterminism(BUY_HOLD, bars, { seed: 3, engines: ["js"] });
		var b:Dynamic = MuseRuntime.proveDeterminism(BUY_HOLD, bars, { seed: 3, engines: ["js"] });
		Assert.equals(Reflect.field(a, "equityDigest"), Reflect.field(b, "equityDigest"));
		Assert.equals(true, Reflect.field(a, "identical"));
	}

	static function synthBars(n:Int, seed:Int):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		var price = 100.0;
		var s = seed;
		for (i in 0...n) {
			s = (s * 1103515245 + 12345) & 0x7fffffff;
			var ret = ((s % 2001) / 10000.0) - 0.1;
			var o = price;
			var c = price * (1 + ret);
			var h = Math.max(o, c) * 1.001;
			var l = Math.min(o, c) * 0.999;
			out.push({ open: o, high: h, low: l, close: c, volume: 1000.0, time: i });
			price = c;
		}
		return out;
	}
}

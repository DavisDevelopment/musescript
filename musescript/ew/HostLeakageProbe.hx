package musescript.ew;

import musescript.harness.Bar;

/**
 * Bucket C1 leakage probe: for a host that claims PIT causality, scramble all
 * bars > t and assert `cloudAt(t)` is byte-identical.
 *
 * Default mode streams only bars `0..t` (the `ProjectionProvider.materialize` contract:
 * `onBar(i)` then `cloudAt(i)` before any future bar). `fullStream=true` feeds the entire
 * tape first — required for hosts that retain history and claim `cloudAt(t)` ignores `> t`
 * (Auction). Lattice/Mcmc graphs mutate irreversibly on `onBar`, so they are probed under
 * the streaming contract.
 *
 * `hostFactory` receives the tape so oracles / batch hosts bind to the (possibly scrambled) bars.
 */
class HostLeakageProbe {
	/**
	 * Returns null on pass, or a diagnostic string on the first divergent field.
	 */
	public static function probe(
		hostFactory:Array<Bar>->EwForecastHost,
		bars:Array<Bar>,
		?probeT:Int = -1,
		?fullStream:Bool = false
	):Null<String> {
		if (bars.length < 4) return "tape too short";
		var t = probeT >= 0 ? probeT : Std.int(bars.length / 2);
		if (t < 1 || t >= bars.length - 1) t = Std.int(bars.length / 2);

		var cloudA = runOnce(hostFactory, bars, t, fullStream);

		var scrambled = bars.copy();
		var i = t + 1;
		while (i < scrambled.length) {
			var span = scrambled.length - t - 1;
			var j = t + 1 + (((i * 1103515245 + 12345) >>> 0) % span);
			if (j < scrambled.length && j > t) {
				var tmp = scrambled[i];
				scrambled[i] = scrambled[j];
				scrambled[j] = tmp;
			}
			i++;
		}

		var cloudB = runOnce(hostFactory, scrambled, t, fullStream);
		return diffCloud(cloudA, cloudB, t);
	}

	static function runOnce(
		hostFactory:Array<Bar>->EwForecastHost, bars:Array<Bar>, t:Int, fullStream:Bool
	):ForecastCloud {
		var host = hostFactory(bars);
		var end = fullStream ? bars.length - 1 : t;
		var i = 0;
		while (i <= end) {
			host.onBar(bars[i], i);
			i++;
		}
		return host.cloudAt(t);
	}

	static function diffCloud(a:ForecastCloud, b:ForecastCloud, t:Int):Null<String> {
		function chk(name:String, x:Float, y:Float):Null<String> {
			if (Math.isNaN(x) && Math.isNaN(y)) return null;
			if (x != y) return 'leak at t=$t field=$name: $x vs $y';
			return null;
		}
		var d:Null<String>;
		d = chk("priceLo", a.priceLo, b.priceLo); if (d != null) return d;
		d = chk("priceHi", a.priceHi, b.priceHi); if (d != null) return d;
		d = chk("priceMid", a.priceMid, b.priceMid); if (d != null) return d;
		d = chk("spread", a.spread, b.spread); if (d != null) return d;
		d = chk("probUp", a.probUp, b.probUp); if (d != null) return d;
		d = chk("topMass", a.topMass, b.topMass); if (d != null) return d;
		d = chk("countEntropy", a.countEntropy, b.countEntropy); if (d != null) return d;
		d = chk("invalidatePrice", a.invalidatePrice, b.invalidatePrice); if (d != null) return d;
		d = chk("nestScore", a.nestScore, b.nestScore); if (d != null) return d;
		if (a.samples != b.samples) return 'leak at t=$t field=samples: ${a.samples} vs ${b.samples}';
		if (a.horizon != b.horizon) return 'leak at t=$t field=horizon: ${a.horizon} vs ${b.horizon}';
		return null;
	}

	/** ForecastCloud invariant checks (Bucket E5). Returns null on pass. */
	public static function checkInvariants(c:ForecastCloud):Null<String> {
		if (Math.isFinite(c.priceLo) && Math.isFinite(c.priceMid) && c.priceLo > c.priceMid)
			return 'priceLo > priceMid';
		if (Math.isFinite(c.priceMid) && Math.isFinite(c.priceHi) && c.priceMid > c.priceHi)
			return 'priceMid > priceHi';
		if (Math.isFinite(c.probUp) && (c.probUp < 0 || c.probUp > 1))
			return 'probUp out of [0,1]: ${c.probUp}';
		if (Math.isFinite(c.topMass) && (c.topMass < 0 || c.topMass > 1))
			return 'topMass out of [0,1]: ${c.topMass}';
		if (Math.isFinite(c.countEntropy) && c.countEntropy < 0)
			return 'entropy < 0';
		if (c.samples < 0)
			return 'samples < 0';
		return null;
	}
}

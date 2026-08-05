package musescript.ew.mcmc;

import haxe.Int64;
import haxe.io.FPHelper;

/**
 * Cross-target parity proof for the MCMC determinism foundation. Prints the RAW bit patterns of a
 * DetRng stream + DetMath.exp/log results as hex. Compiled to BOTH node (WASM/JS proxy) and JVM and
 * diffed: identical output ⇒ our operation set is byte-identical across the two backends the
 * dual-compiled kernel will run on. (Compare bits, never decimals — decimal formatting itself can
 * differ across targets even when the underlying double is identical.)
 *
 * Also locks the Tier-A bytecode VM vs MuseInterp on a fixed strategy (SPEC_BYTECODE_VM.md §4/§8:
 * the fourth execution tier). `match=1` is part of the golden — a VM/interp drift fails CI.
 *
 * Bucket D4: `render()` is the CI surface — utest locks the bit string on node; `tools/det_parity_ci.*`
 * builds JVM + node and diffs the same string.
 */
class DetParityDump {
	static function main() {
		#if (sys || node)
		Sys.print(render());
		#end
	}

	/** Full parity transcript (stable across targets). Used by CI golden + JVM↔node diff. */
	public static function render():String {
		var buf = new StringBuf();

		var rng = new DetRng(Int64.make(0x12345678, 0x9ABCDEF0));
		buf.add("-- rng.next (hex32) --\n");
		for (_ in 0...20) buf.add(hex32(rng.next()) + "\n");

		buf.add("-- rng.nextUnit (raw f64 bits) --\n");
		for (_ in 0...10) buf.add(fbits(rng.nextUnit()) + "\n");

		buf.add("-- rng.nextInt(7) --\n");
		for (_ in 0...15) buf.add(Std.string(rng.nextInt(7)) + "\n");

		buf.add("-- DetMath.log / exp (raw f64 bits) --\n");
		var xs = [0.1, 0.5, 1.0, 1.5, 2.0, 2.718281828459045, 3.14159265, 10.0, 42.0, 100.0];
		for (x in xs) {
			buf.add("log(" + x + ")=" + fbits(DetMath.log(x)) + "\n");
			buf.add("exp(" + (x - 5.0) + ")=" + fbits(DetMath.exp(x - 5.0)) + "\n");
		}

		// Whole-chain parity: a short regime MCMC composes only DetRng/DetMath/sqrt/± ops, so its
		// posterior must also be byte-identical across targets — prove it, don't assume ("by
		// construction" is exactly what the compactParams bug looked like).
		buf.add("-- RegimeMcmc posterior (raw f64 bits) --\n");
		var tape = new haxe.ds.Vector<Float>(160);
		var trng = new DetRng(Int64.make(0x5A5A, 0xC3C3));
		for (t in 0...160) tape[t] = (t < 80 ? 0.004 : 0.02) * trng.nextGaussian();
		var m = new musescript.ew.mcmc.RegimeMcmc(Int64.make(0, 99), tape, 2);
		m.run(2000, 800);
		for (t in [10, 40, 90, 150]) for (k in 0...2)
			buf.add("P(z" + t + "=" + k + ")=" + fbits(m.regimeProb(t, k)) + "\n");
		buf.add("sig0=" + fbits(m.regimeSigma(0)) + " sig1=" + fbits(m.regimeSigma(1)) + "\n");

		// Bucket D4: parity for BlockBootstrap + NullForecastHost (new randomized paths).
		buf.add("-- BlockBootstrap sharpeCi point (raw f64 bits) --\n");
		var rets:Array<Float> = [];
		var brng = new DetRng(Int64.make(0xB007, 0x51D));
		for (_ in 0...64) rets.push(0.001 + 0.01 * brng.nextGaussian());
		var ci = musescript.evo.rigor.BlockBootstrap.sharpeCi(rets, 42, 50, 4);
		buf.add("point=" + fbits(ci.point) + " lo=" + fbits(ci.lo) + " hi=" + fbits(ci.hi) + "\n");

		buf.add("-- NullForecastHost cloudAt mid (raw f64 bits) --\n");
		var host = new musescript.ew.NullForecastHost(0x11, 5);
		var bar:{open:Float, high:Float, low:Float, close:Float, volume:Float, time:Float, index:Int} =
			{open: 100, high: 101, low: 99, close: 100.5, volume: 1, time: 0, index: 0};
		for (i in 0...10) {
			host.onBar(cast bar, i);
			var c = host.cloudAt(i);
			buf.add("t" + i + "=" + fbits(c.priceMid) + "\n");
		}

		// SPEC_BYTECODE_VM.md §4 / §8 — fourth execution tier (interp ↔ Tier-A VM).
		// Fixed program + synthetic feed; dump raw trades + equity bits from BOTH so CI golden
		// catches silent VM/interp drift (DetParityDump is the standing cross-target bit lock).
		buf.add("-- MuseVm vs MuseInterp (trades + raw f64 equity bits) --\n");
		var vmSrc = "strategy S { onBar {\n"
			+ "  when crossover(close, sma(close, 8)): { long(1); }\n"
			+ "  when crossunder(close, sma(close, 8)): { flat(); }\n"
			+ "} }";
		var feed = musescript.harness.BarFeed.synthetic(200, 11);
		var prog = new musescript.parse.MuseParser().parse(vmSrc);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var interpRes = new musescript.interp.MuseInterp(new musescript.harness.HarnessContext())
			.runBacktest(prog, feed);
		feed.reset();
		musescript.builtins.TradeBuiltins.resetCrossState();
		var vmRes = musescript.vm.MuseVm.runBacktest(
			new musescript.harness.HarnessContext(),
			new musescript.parse.MuseParser().parse(vmSrc),
			feed
		);
		buf.add("interp trades=" + interpRes.trades + " eq=" + fbits(interpRes.finalEquity) + "\n");
		buf.add("vm trades=" + vmRes.trades + " eq=" + fbits(vmRes.finalEquity) + "\n");
		var eqMatch = interpRes.trades == vmRes.trades
			&& fbits(interpRes.finalEquity) == fbits(vmRes.finalEquity);
		buf.add("match=" + (eqMatch ? "1" : "0") + "\n");
		// Spot-check mid-tape equity (catches length/padding drift the final alone can miss).
		var mid = Std.int(interpRes.equity.length / 2);
		if (interpRes.equity.length > 0 && vmRes.equity.length > 0) {
			var ii = mid < interpRes.equity.length ? mid : interpRes.equity.length - 1;
			var vi = mid < vmRes.equity.length ? mid : vmRes.equity.length - 1;
			buf.add("interp eq[" + ii + "]=" + fbits(interpRes.equity[ii]) + "\n");
			buf.add("vm eq[" + vi + "]=" + fbits(vmRes.equity[vi]) + "\n");
		}

		// Cliff 4 — scalar np_mean(window) VM↔interp (no NdArray on unboxed stack).
		buf.add("-- MuseVm np_mean(window) vs MuseInterp --\n");
		var npSrc = "strategy S { onBar {\n"
			+ "  when np_mean(window(close, 5)) > open: { long(1); }\n"
			+ "  when np_mean(window(close, 5)) < open: { flat(); }\n"
			+ "} }";
		var npFeed = musescript.harness.BarFeed.synthetic(200, 11);
		var npProg = new musescript.parse.MuseParser().parse(npSrc);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var npInterp = new musescript.interp.MuseInterp(new musescript.harness.HarnessContext())
			.runBacktest(npProg, npFeed);
		npFeed.reset();
		musescript.builtins.TradeBuiltins.resetCrossState();
		var npVm = musescript.vm.MuseVm.runBacktest(
			new musescript.harness.HarnessContext(),
			new musescript.parse.MuseParser().parse(npSrc),
			npFeed
		);
		buf.add("interp trades=" + npInterp.trades + " eq=" + fbits(npInterp.finalEquity) + "\n");
		buf.add("vm trades=" + npVm.trades + " eq=" + fbits(npVm.finalEquity) + "\n");
		var npMatch = npInterp.trades == npVm.trades
			&& fbits(npInterp.finalEquity) == fbits(npVm.finalEquity);
		buf.add("match=" + (npMatch ? "1" : "0") + "\n");

		// Cliff 2 — OBJ-lane NdArrayF64 handle (zeros/asarray → mean/get_flat); nums lane stays Float.
		buf.add("-- MuseVm np handle (zeros/asarray) vs MuseInterp --\n");
		var hSrc = "strategy S { onBar {\n"
			+ "  xs = np_asarray([1.0, 2.0, 3.0])\n"
			+ "  zs = np_zeros(3)\n"
			+ "  when np_get_flat(xs, 1) == 2.0 && np_mean(zs) == 0.0: { long(1); }\n"
			+ "  when np_sum(xs) != 6.0: { flat(); }\n"
			+ "} }";
		var hFeed = musescript.harness.BarFeed.synthetic(200, 11);
		var hProg = new musescript.parse.MuseParser().parse(hSrc);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var hInterp = new musescript.interp.MuseInterp(new musescript.harness.HarnessContext())
			.runBacktest(hProg, hFeed);
		hFeed.reset();
		musescript.builtins.TradeBuiltins.resetCrossState();
		var hVm = musescript.vm.MuseVm.runBacktest(
			new musescript.harness.HarnessContext(),
			new musescript.parse.MuseParser().parse(hSrc),
			hFeed
		);
		buf.add("interp trades=" + hInterp.trades + " eq=" + fbits(hInterp.finalEquity) + "\n");
		buf.add("vm trades=" + hVm.trades + " eq=" + fbits(hVm.finalEquity) + "\n");
		var hMatch = hInterp.trades == hVm.trades
			&& fbits(hInterp.finalEquity) == fbits(hVm.finalEquity);
		buf.add("match=" + (hMatch ? "1" : "0") + "\n");

		// Cliff PD — packed pd_rank1d OBJ-lane NdArray → get_flat (nums lane stays Float).
		buf.add("-- MuseVm pd_rank1d handle vs MuseInterp --\n");
		var pdSrc = "strategy S { onBar {\n"
			+ "  when np_get_flat(pd_rank1d([1.0, 2.0, 3.0], true), 1) > 0.5: { long(1); }\n"
			+ "  when np_get_flat(pd_rank1d([1.0, 2.0, 3.0], true), 0) < 0.5: { flat(); }\n"
			+ "} }";
		var pdFeed = musescript.harness.BarFeed.synthetic(200, 11);
		var pdProg = new musescript.parse.MuseParser().parse(pdSrc);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var pdInterp = new musescript.interp.MuseInterp(new musescript.harness.HarnessContext())
			.runBacktest(pdProg, pdFeed);
		pdFeed.reset();
		musescript.builtins.TradeBuiltins.resetCrossState();
		var pdVm = musescript.vm.MuseVm.runBacktest(
			new musescript.harness.HarnessContext(),
			new musescript.parse.MuseParser().parse(pdSrc),
			pdFeed
		);
		buf.add("interp trades=" + pdInterp.trades + " eq=" + fbits(pdInterp.finalEquity) + "\n");
		buf.add("vm trades=" + pdVm.trades + " eq=" + fbits(pdVm.finalEquity) + "\n");
		var pdMatch = pdInterp.trades == pdVm.trades
			&& fbits(pdInterp.finalEquity) == fbits(pdVm.finalEquity);
		buf.add("match=" + (pdMatch ? "1" : "0") + "\n");

		// Cliff PD Series — pd_series / pd_shift OBJ Series → series_values → get_flat.
		buf.add("-- MuseVm pd_series/shift handle vs MuseInterp --\n");
		var serSrc = "strategy S { onBar {\n"
			+ "  when np_get_flat(pd_series_values(pd_shift(pd_series(window(close, 4)), 1)), 3) > 0.0: { long(1); }\n"
			+ "  when np_get_flat(pd_series_values(pd_shift(pd_series([5.0, 6.0, 7.0]), 1)), 1) != 5.0: { flat(); }\n"
			+ "} }";
		var serFeed = musescript.harness.BarFeed.synthetic(200, 11);
		var serProg = new musescript.parse.MuseParser().parse(serSrc);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var serInterp = new musescript.interp.MuseInterp(new musescript.harness.HarnessContext())
			.runBacktest(serProg, serFeed);
		serFeed.reset();
		musescript.builtins.TradeBuiltins.resetCrossState();
		var serVm = musescript.vm.MuseVm.runBacktest(
			new musescript.harness.HarnessContext(),
			new musescript.parse.MuseParser().parse(serSrc),
			serFeed
		);
		buf.add("interp trades=" + serInterp.trades + " eq=" + fbits(serInterp.finalEquity) + "\n");
		buf.add("vm trades=" + serVm.trades + " eq=" + fbits(serVm.finalEquity) + "\n");
		var serMatch = serInterp.trades == serVm.trades
			&& fbits(serInterp.finalEquity) == fbits(serVm.finalEquity);
		buf.add("match=" + (serMatch ? "1" : "0") + "\n");


		// Cliff PD Series extras — length/name + gated ctor index/name.
		buf.add("-- MuseVm pd_series length/name vs MuseInterp --\n");
		var serXSrc = "strategy S { onBar {\n"
			+ "  s = pd_series([1.0, 2.0, 3.0], [10.0, 20.0, 30.0], \"x\")\n"
			+ "  when pd_series_length(s) == 3.0 && pd_series_name(s) == \"x\": { long(1); }\n"
			+ "  when np_get_flat(pd_series_values(s), 0) != 1.0: { flat(); }\n"
			+ "} }";
		var serXFeed = musescript.harness.BarFeed.synthetic(200, 11);
		var serXProg = new musescript.parse.MuseParser().parse(serXSrc);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var serXInterp = new musescript.interp.MuseInterp(new musescript.harness.HarnessContext())
			.runBacktest(serXProg, serXFeed);
		serXFeed.reset();
		musescript.builtins.TradeBuiltins.resetCrossState();
		var serXVm = musescript.vm.MuseVm.runBacktest(
			new musescript.harness.HarnessContext(),
			new musescript.parse.MuseParser().parse(serXSrc),
			serXFeed
		);
		buf.add("interp trades=" + serXInterp.trades + " eq=" + fbits(serXInterp.finalEquity) + "\n");
		buf.add("vm trades=" + serXVm.trades + " eq=" + fbits(serXVm.finalEquity) + "\n");
		var serXMatch = serXInterp.trades == serXVm.trades
			&& fbits(serXInterp.finalEquity) == fbits(serXVm.finalEquity);
		buf.add("match=" + (serXMatch ? "1" : "0") + "\n");

		// Cliff PD Frame — from_columns / xs_rank / get / groupby / join / frame shift.
		buf.add("-- MuseVm pd_frame handle vs MuseInterp --\n");
		var frSrc = "strategy S { onBar {\n"
			+ "  df = pd_from_columns({a: [1.0, 3.0], b: [2.0, 4.0]})\n"
			+ "  when pd_nrows(df) == 2.0 && np_get_flat(pd_series_values(pd_get(df, \"a\")), 1) == 3.0: { long(1); }\n"
			+ "  when np_get_flat(pd_series_values(pd_get(pd_shift(df, 1), \"a\")), 1) != 1.0: { flat(); }\n"
			+ "} }";
		var frFeed = musescript.harness.BarFeed.synthetic(200, 11);
		var frProg = new musescript.parse.MuseParser().parse(frSrc);
		musescript.builtins.TradeBuiltins.resetCrossState();
		var frInterp = new musescript.interp.MuseInterp(new musescript.harness.HarnessContext())
			.runBacktest(frProg, frFeed);
		frFeed.reset();
		musescript.builtins.TradeBuiltins.resetCrossState();
		var frVm = musescript.vm.MuseVm.runBacktest(
			new musescript.harness.HarnessContext(),
			new musescript.parse.MuseParser().parse(frSrc),
			frFeed
		);
		buf.add("interp trades=" + frInterp.trades + " eq=" + fbits(frInterp.finalEquity) + "\n");
		buf.add("vm trades=" + frVm.trades + " eq=" + fbits(frVm.finalEquity) + "\n");
		var frMatch = frInterp.trades == frVm.trades
			&& fbits(frInterp.finalEquity) == fbits(frVm.finalEquity);
		buf.add("match=" + (frMatch ? "1" : "0") + "\n");

		return buf.toString();
	}

	static function hex32(v:Int):String
		return StringTools.hex(v, 8);

	/** Raw IEEE-754 bits of a double as 16 hex chars (high32:low32) — the true byte-identity check. */
	static function fbits(f:Float):String {
		var b = FPHelper.doubleToI64(f);
		return StringTools.hex(b.high, 8) + StringTools.hex(b.low, 8);
	}
}

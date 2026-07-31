package musescript.vm;

import haxe.io.FPHelper;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.BacktestResult;
import musescript.vm.MuseBytecodeCompiler.VmUnsupported;

/**
 * The standing interp↔VM parity gate (SPEC_BYTECODE_VM.md §4 / BYTECODE_VM_TODO.md
 * V2) — kept a plain reusable harness, NOT a test, so opcode growth (V3+) happens
 * against it and it can also back a CLI/golden dump later. Given a set of
 * MuseScript programs and a feed, it runs each through BOTH the tree-walking
 * `MuseInterp` and the Tier-A `MuseVm` and classifies:
 *
 *  - **identical**  — VM compiled the program AND its trades + raw-f64 equity bits
 *                     match the interp exactly. (compare BITS, never decimals.)
 *  - **fallback**   — program is outside the P0 subset (`VmUnsupported`); expected,
 *                     not a failure. This bucket SHRINKS as V3 adds opcodes.
 *  - **interpError**— the interp itself faults on the program (some corpus genomes
 *                     do; see the murmuration integration notes) — skipped, can't compare.
 *  - **diverged**   — the failure the gate exists to catch: VM ran but produced
 *                     different trades/equity, OR VM crashed where interp succeeded.
 *                     `diverged.length == 0` is the invariant callers assert.
 *
 * `vm/` deliberately does not depend on `evo/`: the corpus (genomes → sources) is
 * assembled by the caller (`TestVmParityCorpus`) and handed in as `{name, src}`.
 */
typedef VmParityItem = { var name:String; var src:String; };
typedef VmParityReport = {
	var total:Int;
	var identical:Int;
	var fallback:Int;
	var interpError:Int;
	var diverged:Array<{name:String, detail:String}>;
};

class VmParityDump {
	/** Run the gate over `items` against `feed`. The feed is replayable across
	 * runs (BarFeed.synthetic), so a fresh program is parsed per tier but the feed
	 * is shared — matching how the interp/compiled-JS parity tests already reuse it. */
	public static function run(items:Array<VmParityItem>, feed:BarFeed):VmParityReport {
		var rep:VmParityReport = { total: 0, identical: 0, fallback: 0, interpError: 0, diverged: [] };
		for (item in items) {
			rep.total++;
			var interpRes:BacktestResult;
			try {
				interpRes = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(item.src), feed);
			} catch (_:Dynamic) {
				rep.interpError++;
				continue;
			}
			var vmRes:BacktestResult;
			try {
				vmRes = MuseVm.runBacktest(new HarnessContext(), new MuseParser().parse(item.src), feed);
			} catch (u:VmUnsupported) {
				rep.fallback++;
				continue;
			} catch (e:Dynamic) {
				// VM threw where the interp succeeded — a real Tier-A bug, not a clean fallback.
				rep.diverged.push({ name: item.name, detail: "VM crashed where interp ran: " + Std.string(e) });
				continue;
			}
			var detail = compare(interpRes, vmRes);
			if (detail == null) rep.identical++;
			else rep.diverged.push({ name: item.name, detail: detail });
		}
		return rep;
	}

	/** null == byte-identical; else a human-readable first-divergence detail. */
	static function compare(a:BacktestResult, b:BacktestResult):Null<String> {
		if (a.trades != b.trades) return 'trades ${a.trades} vs ${b.trades}';
		if (fbits(a.finalEquity) != fbits(b.finalEquity))
			return 'finalEquity ${a.finalEquity} vs ${b.finalEquity} (bits ${fbits(a.finalEquity)} vs ${fbits(b.finalEquity)})';
		if (a.equity.length != b.equity.length)
			return 'equity length ${a.equity.length} vs ${b.equity.length}';
		for (i in 0...a.equity.length)
			if (fbits(a.equity[i]) != fbits(b.equity[i]))
				return 'equity[$i] ${a.equity[i]} vs ${b.equity[i]}';
		return null;
	}

	/** One-line summary + any divergences, for CI logs / golden diffs. */
	public static function format(rep:VmParityReport):String {
		var buf = new StringBuf();
		buf.add('VM parity: ${rep.total} progs -> identical=${rep.identical} fallback=${rep.fallback}'
			+ ' interpError=${rep.interpError} diverged=${rep.diverged.length}\n');
		for (d in rep.diverged) buf.add('  DIVERGED ${d.name}: ${d.detail}\n');
		return buf.toString();
	}

	static function fbits(f:Float):String {
		var b = FPHelper.doubleToI64(f);
		return StringTools.hex(b.high, 8) + StringTools.hex(b.low, 8);
	}
}

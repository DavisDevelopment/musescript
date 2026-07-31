package musescript.tests;

import musescript.parse.MuseParser;
import musescript.compile.MuseCompiler;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.vm.MuseVm;

/**
 * Isolated per-eval microbench (portable/JS tier — no Graal JIT, no WASM workers), the interactive
 * backtest tier where the VM is the only fast option. Times the run loop only: prog is parsed+lowered
 * ONCE, the VM chunk compiled ONCE, so this is interp-run vs VM-run, not compile. A couple of
 * arithmetic+indicator strategy shapes to show the spread (builtin-dominated vs arithmetic-heavy).
 */
class VmBenchJs {
	static final CASES:Array<{name:String, src:String}> = [
		{ name: "sma-cross (2 builtins/bar)", src: "strategy S { onBar {\n  fast = sma(close, 10)\n  slow = sma(close, 30)\n  when crossover(fast, slow): { long(1); }\n  when crossunder(fast, slow): { flat(); }\n} }" },
		{ name: "arith-heavy (0 builtins/bar)", src: "strategy S { onBar {\n  a = (high - low) * 2.0\n  b = (close - open) / (a + 1.0)\n  c = a * b - close + (open + high + low) / 3.0\n  when c > close[1]: { long(1); }\n  when c < close[1]: { flat(); }\n} }" }
	];

	static function main() {
		var feed = BarFeed.synthetic(5161, 42);
		var N = 30;
		var K = 8;
		for (c in CASES) {
			var progL = MuseCompiler.lower(new MuseParser().parse(c.src));
			var chunk = MuseVm.compileProgram(progL);
			for (_ in 0...16) { new MuseInterp(new HarnessContext()).runBacktest(progL, feed); MuseVm.runChunk(new HarnessContext(), chunk, feed); }
			// Min-of-interleaved-blocks (see the JVM bench): stable against JIT-warmup / load noise.
			var iMs = 1e9;
			var vMs = 1e9;
			for (_ in 0...K) {
				var t0 = haxe.Timer.stamp();
				for (_ in 0...N) new MuseInterp(new HarnessContext()).runBacktest(progL, feed);
				var mi = (haxe.Timer.stamp() - t0) / N * 1000; if (mi < iMs) iMs = mi;
				var t1 = haxe.Timer.stamp();
				for (_ in 0...N) MuseVm.runChunk(new HarnessContext(), chunk, feed);
				var mv = (haxe.Timer.stamp() - t1) / N * 1000; if (mv < vMs) vMs = mv;
			}
			Sys.println('JS-BENCH [${c.name}] bars=5161 reps=${N}x${K} min: interp=${Math.round(iMs * 100) / 100}ms vm=${Math.round(vMs * 100) / 100}ms  speedup=${Math.round(iMs / vMs * 100) / 100}x');
		}
	}
}

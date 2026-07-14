package musescript.examples;

import musescript.parse.MuseParser;
import musescript.compile.MathCompiler;
import musescript.compile.MathOnly;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.runtime.FnClosure;
import musescript.ast.FnKind;

/**
 * Example 07 — math-only kernel stress across runtimes:
 *   JS eval | WASM | pure Python | Python+numba | MuseInterp
 */
class RuntimeStress {
	static function main() {
		Sys.println("=== MuseScript 07-runtime-stress ===");

		var source = '
		{
			function polySum(n) {
				var acc = 0.0;
				var i = 0;
				while (i < n) {
					var x = i * 0.0000001;
					acc = acc + (((x * x) * x) - ((2.0 * x) * x) + x);
					i = i + 1;
				}
				return acc;
			}
		}
		';

		var prog = new MuseParser().parse(source, "stress.ms");
		var mathFns = MathOnly.extract(prog);
		Sys.println("math-only fns: " + [for (f in mathFns) f.name].join(", "));
		if (mathFns.length == 0) {
			Sys.println("FAIL: polySum not recognized as math-only");
			return;
		}

		var n = 2_000_000;
		var interpN = 50_000; // MuseInterp is intentionally slower; scale down for baseline
		var rounds = 3;
		Sys.println('n=$n (interp_n=$interpN) rounds=$rounds');

		var jsSrc = MathCompiler.emit(prog, "polySum", { target: "js" });
		var pySrc = MathCompiler.emit(prog, "polySum", { target: "python" });
		var wat = MathCompiler.emit(prog, "polySum", { target: "wasm" });
		Sys.println("emit js chars: " + (jsSrc != null ? jsSrc.length : 0));
		Sys.println("emit py chars: " + (pySrc != null ? pySrc.length : 0));
		Sys.println("emit wat chars: " + (wat != null ? wat.length : 0));

		var results:Array<{name:String, ms:Float, value:Float, ok:Bool}> = [];

		function bench(label:String, fn:Null<Dynamic>, ?argN:Int):Void {
			var useN = argN != null ? argN : n;
			if (fn == null) {
				Sys.println(pad(label) + " SKIP (unavailable on this target)");
				results.push({ name: label, ms: -1, value: 0, ok: false });
				return;
			}
			// warmup
			fn([1000]);
			var t0 = haxe.Timer.stamp();
			var v:Float = 0;
			for (_ in 0...rounds) v = fn([useN]);
			var ms = (haxe.Timer.stamp() - t0) * 1000 / rounds;
			// normalize to equivalent ms @ n for ranking when using scaled interp
			var scaled = useN != n ? ms * (n / useN) : ms;
			Sys.println(pad(label) + ' ${round2(ms)} ms  value=${round6(v)}'
				+ (useN != n ? '  (scaled@${n}=${round2(scaled)}ms)' : ''));
			results.push({ name: label, ms: scaled, value: v, ok: true });
		}

		// MuseInterp baseline (all targets) — smaller n, scaled for ranking
		var harness = new HarnessContext();
		var interp = new MuseInterp(harness);
		var decl = mathFns[0];
		var clo = new FnClosure(decl.args, decl.body, null, decl.name, Normal);
		interp.globals.set(decl.name, clo);
		bench("muse-interp", function(args:Array<Dynamic>):Dynamic {
			return interp.callClosure(clo, args);
		}, interpN);

		#if js
		bench("pure-js", MathCompiler.compile(prog, "polySum", { target: "js" }));
		bench("wasm", MathCompiler.compile(prog, "polySum", { target: "wasm" }));
		#end

		#if python
		bench("pure-python", MathCompiler.compile(prog, "polySum", { target: "python" }));
		bench("python/numba", MathCompiler.compile(prog, "polySum", { target: "numba" }));
		bench("wasm", MathCompiler.compile(prog, "polySum", { target: "wasm" }));
		#end

		var okVals = [for (r in results) if (r.ok && r.name != "muse-interp") r.value];
		if (okVals.length >= 2) {
			var base = okVals[0];
			var maxDiff = 0.0;
			for (v in okVals) {
				var d = Math.abs(v - base);
				if (d > maxDiff) maxDiff = d;
			}
			Sys.println('max value delta (compiled hosts): ${round6(maxDiff)}');
		}

		var timed = [for (r in results) if (r.ok && r.ms > 0) r];
		if (timed.length > 0) {
			timed.sort(function(a, b) return a.ms < b.ms ? -1 : (a.ms > b.ms ? 1 : 0));
			Sys.println("ranking (fastest first): " + [for (r in timed) r.name + '@' + round2(r.ms) + 'ms'].join("  "));
		}
	}

	static function pad(s:String):String {
		var out = s;
		while (out.length < 14) out += " ";
		return out;
	}

	static function round2(x:Float):Float {
		return Math.round(x * 100) / 100;
	}

	static function round6(x:Float):Float {
		return Math.round(x * 1e6) / 1e6;
	}
}

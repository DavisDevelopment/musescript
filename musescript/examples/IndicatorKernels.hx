package musescript.examples;

import musescript.parse.MuseParser;
import musescript.compile.MathCompiler;
import musescript.compile.MathOnly;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;

/**
 * Example 09 — Indicator *kernel* stress on fast targets (js / wasm / python / numba).
 *
 * Same SMA/EMA/RSI/ATR computational work as example 08, but as a math-only
 * MuseScript tape kernel over OHLCV float arrays (no harness/chart/orders).
 */
class IndicatorKernels {
	public static final SOURCE = '
	{
		function run_suite(closes, highs, lows, n, smaLen, emaLen, rsiLen, atrLen) {
			var i = 0;
			var ema = closes[0];
			var alpha = 2.0 / (emaLen + 1.0);
			var avgGain = 0.0;
			var avgLoss = 0.0;
			var atr = highs[0] - lows[0];
			var rsiCount = 0;
			var atrCount = 1;
			var sum = 0.0;
			while (i < n) {
				var c = closes[i];
				var h = highs[i];
				var l = lows[i];

				if (i + 1 >= smaLen) {
					var s = 0.0;
					var j = 0;
					while (j < smaLen) {
						s = s + closes[i - j];
						j = j + 1;
					}
					sum = sum + (s / smaLen);
				}

				if (i == 0) ema = c;
				else ema = (alpha * c) + ((1.0 - alpha) * ema);
				sum = sum + ema;

				if (i > 0) {
					var ch = c - closes[i - 1];
					var gain = ch > 0 ? ch : 0.0;
					var loss = ch < 0 ? 0.0 - ch : 0.0;
					if (rsiCount < rsiLen) {
						avgGain = avgGain + gain;
						avgLoss = avgLoss + loss;
						rsiCount = rsiCount + 1;
						if (rsiCount == rsiLen) {
							avgGain = avgGain / rsiLen;
							avgLoss = avgLoss / rsiLen;
						}
					} else {
						avgGain = ((avgGain * (rsiLen - 1)) + gain) / rsiLen;
						avgLoss = ((avgLoss * (rsiLen - 1)) + loss) / rsiLen;
					}
					if (rsiCount >= rsiLen) {
						var rsi = avgLoss == 0 ? 100.0 : (100.0 - (100.0 / (1.0 + (avgGain / avgLoss))));
						sum = sum + rsi;
					}
				}

				var tr = h - l;
				if (i > 0) {
					var a = h - closes[i - 1];
					if (a < 0) a = 0.0 - a;
					var b = l - closes[i - 1];
					if (b < 0) b = 0.0 - b;
					if (a > tr) tr = a;
					if (b > tr) tr = b;
				}
				if (atrCount < atrLen) {
					atr = atr + tr;
					atrCount = atrCount + 1;
					if (atrCount == atrLen) atr = atr / atrLen;
				} else {
					atr = ((atr * (atrLen - 1)) + tr) / atrLen;
				}
				sum = sum + atr;

				i = i + 1;
			}
			return sum;
		}
	}
	';

	static function main() {
		Sys.println("=== MuseScript 09-indicator-kernels (fast targets) ===");

		var realPath = "data/real/tape.csv";
		var realBars = OhlcvCsv.exists(realPath) ? OhlcvCsv.load(realPath) : BarFeed.synthetic(8000, 7).all();
		Sys.println(OhlcvCsv.exists(realPath)
			? 'real tape: $realPath bars=${realBars.length}'
			: 'real tape missing — synthetic 8k fallback');

		var synthBars = BarFeed.synthetic(250000, 99).all();
		Sys.println('synthetic tape: bars=${synthBars.length}');

		var prog = new MuseParser().parse(SOURCE, "indicator_kernels.ms");
		if (MathOnly.find(prog, "run_suite") == null) {
			Sys.println("FAIL: run_suite not math-only");
			return;
		}

		var wat = MathCompiler.emit(prog, "run_suite", { target: "wasm" });
		var py = MathCompiler.emit(prog, "run_suite", { target: "python" });
		Sys.println('emit wat chars=${wat != null ? wat.length : 0}  py chars=${py != null ? py.length : 0}');

		benchTape("REAL", realBars, prog);
		benchTape("SYNTH", synthBars, prog);
	}

	static function benchTape(label:String, bars:Array<Bar>, prog:Dynamic):Void {
		Sys.println("--- " + label + " ---");
		var closes:Array<Float> = [for (b in bars) b.close];
		var highs:Array<Float> = [for (b in bars) b.high];
		var lows:Array<Float> = [for (b in bars) b.low];
		var n = bars.length;
		var args:Array<Dynamic> = [closes, highs, lows, n, 10, 30, 14, 14];

		var targets:Array<String> = [];
		#if js
		targets = ["js", "wasm"];
		#elseif python
		targets = ["python", "numba", "wasm"];
		#end

		var results:Array<{name:String, ms:Float, value:Float, ok:Bool}> = [];

		for (t in targets) {
			var fn = MathCompiler.compile(prog, "run_suite", { target: t });
			if (fn == null) {
				Sys.println(pad(t) + " SKIP");
				results.push({ name: t, ms: -1, value: 0, ok: false });
				continue;
			}
			// warmup
			try {
				fn(args);
			} catch (e:Dynamic) {
				Sys.println(pad(t) + " FAIL warmup: " + Std.string(e));
				results.push({ name: t, ms: -1, value: 0, ok: false });
				continue;
			}
			var rounds = n >= 100000 ? 2 : 3;
			var t0 = haxe.Timer.stamp();
			var v:Float = 0;
			for (_ in 0...rounds) v = fn(args);
			var ms = (haxe.Timer.stamp() - t0) * 1000 / rounds;
			Sys.println(pad(t) + ' ${round2(ms)} ms  checksum=${round2(v)}  ${Math.round(n / (ms / 1000.0))} bars/sec');
			results.push({ name: t, ms: ms, value: v, ok: true });
		}

		var ok = [for (r in results) if (r.ok) r];
		if (ok.length >= 2) {
			var base = ok[0].value;
			var maxDiff = 0.0;
			for (r in ok) {
				var d = Math.abs(r.value - base);
				if (d > maxDiff) maxDiff = d;
			}
			Sys.println('max checksum delta: ${round2(maxDiff)}');
			ok.sort(function(a, b) return a.ms < b.ms ? -1 : (a.ms > b.ms ? 1 : 0));
			Sys.println("ranking: " + [for (r in ok) r.name + "@" + round2(r.ms) + "ms"].join("  "));
		}
	}

	static function pad(s:String):String {
		var out = s;
		while (out.length < 10) out += " ";
		return out;
	}

	static function round2(x:Float):Float {
		return Math.round(x * 100) / 100;
	}
}

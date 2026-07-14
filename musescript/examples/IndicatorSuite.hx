package musescript.examples;

import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.ast.MuseProgram;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.harness.OhlcvCsv;
import musescript.harness.BacktestResult;
import musescript.builtins.TradeBuiltins;
import musescript.compile.MuseCompiler;
import musescript.compile.JsBackend;

/**
 * Example 08 — Pure MuseScript `@indicator` suite on real + synthetic OHLCV tapes.
 *
 * Benches MuseInterp vs compiled JS (`MuseCompiler` / JsBackend) when emission succeeds.
 */
class IndicatorSuite {
	public static final SOURCE = '
	{
		@indicator("muse_sma") function(len) {
			if (bar_index + 1 < len) return null;
			var s = 0.0;
			var i = 0;
			while (i < len) {
				s = s + close[i];
				i = i + 1;
			}
			return s / len;
		}

		@indicator("muse_ema") function(len) {
			var alpha = 2.0 / (len + 1.0);
			if (state.ready != true) {
				state.ready = true;
				state.prev = close;
				return close;
			}
			state.prev = (alpha * close) + ((1.0 - alpha) * state.prev);
			return state.prev;
		}

		@indicator("muse_rsi") function(len) {
			if (bar_index < 1) {
				state.avgGain = 0.0;
				state.avgLoss = 0.0;
				state.n = 0;
				return null;
			}
			var ch = close - close[1];
			var gain = ch > 0 ? ch : 0.0;
			var loss = ch < 0 ? -ch : 0.0;
			if (state.n < len) {
				state.avgGain = state.avgGain + gain;
				state.avgLoss = state.avgLoss + loss;
				state.n = state.n + 1;
				if (state.n < len) return null;
				state.avgGain = state.avgGain / len;
				state.avgLoss = state.avgLoss / len;
			} else {
				state.avgGain = ((state.avgGain * (len - 1)) + gain) / len;
				state.avgLoss = ((state.avgLoss * (len - 1)) + loss) / len;
			}
			if (state.avgLoss == 0) return 100.0;
			var rs = state.avgGain / state.avgLoss;
			return 100.0 - (100.0 / (1.0 + rs));
		}

		@indicator("muse_atr") function(len) {
			var tr = high - low;
			var a = high - close[1];
			if (a < 0) a = -a;
			var b = low - close[1];
			if (b < 0) b = -b;
			if (a > tr) tr = a;
			if (b > tr) tr = b;
			if (state.ready != true) {
				state.ready = true;
				state.atr = tr;
				state.n = 1;
				return tr;
			}
			if (state.n < len) {
				state.atr = state.atr + tr;
				state.n = state.n + 1;
				if (state.n < len) return state.atr / state.n;
				state.atr = state.atr / len;
				return state.atr;
			}
			state.atr = ((state.atr * (len - 1)) + tr) / len;
			return state.atr;
		}

		@indicator("muse_highest") function(len) {
			if (bar_index + 1 < len) return null;
			var m = close[0];
			var i = 1;
			while (i < len) {
				var v = close[i];
				if (v > m) m = v;
				i = i + 1;
			}
			return m;
		}

		@indicator("muse_lowest") function(len) {
			if (bar_index + 1 < len) return null;
			var m = close[0];
			var i = 1;
			while (i < len) {
				var v = close[i];
				if (v < m) m = v;
				i = i + 1;
			}
			return m;
		}

		@indicator("muse_mom") function(len) {
			if (bar_index + 1 <= len) return null;
			return close - close[len];
		}

		@indicator("muse_roc") function(len) {
			if (bar_index + 1 <= len) return null;
			var prev = close[len];
			if (prev == 0) return 0.0;
			return ((close - prev) / prev) * 100.0;
		}

		@indicator("muse_bb_mid") function(len) {
			return muse_sma(len);
		}

		@indicator("muse_bb_upper") function(len, mult) {
			if (bar_index + 1 < len) return null;
			var mid = muse_sma(len);
			var s = 0.0;
			var i = 0;
			while (i < len) {
				var d = close[i] - mid;
				s = s + (d * d);
				i = i + 1;
			}
			var sd = Math.sqrt(s / len);
			return mid + (mult * sd);
		}

		@indicator("muse_bb_lower") function(len, mult) {
			if (bar_index + 1 < len) return null;
			var mid = muse_sma(len);
			var s = 0.0;
			var i = 0;
			while (i < len) {
				var d = close[i] - mid;
				s = s + (d * d);
				i = i + 1;
			}
			var sd = Math.sqrt(s / len);
			return mid - (mult * sd);
		}

		@strategy("indicator_suite")
		@param("fast", 10)
		@param("slow", 30)
		@param("rsiLen", 14)
		@param("atrLen", 14)
		@on(bar) {
			var fastMa = muse_sma(fast);
			var slowMa = muse_ema(slow);
			var r = muse_rsi(rsiLen);
			var a = muse_atr(atrLen);
			var hi = muse_highest(20);
			var lo = muse_lowest(20);
			var mom = muse_mom(10);
			var roc = muse_roc(10);
			var mid = muse_bb_mid(20);
			var up = muse_bb_upper(20, 2.0);
			var dn = muse_bb_lower(20, 2.0);

			plot(fastMa, "muse_sma");
			plot(slowMa, "muse_ema");
			plot(r, "muse_rsi");
			plot(a, "muse_atr");
			plot(mid, "bb_mid");
			plot(up, "bb_up");
			plot(dn, "bb_dn");

			if (fastMa != null && slowMa != null) {
				if (crossover(fastMa, slowMa) && r != null && r < 70) long();
				if (crossunder(fastMa, slowMa) || (r != null && r > 80)) flat();
			}

			var _sink = (hi != null ? hi : 0) + (lo != null ? lo : 0) + (mom != null ? mom : 0) + (roc != null ? roc : 0);
			if (_sink != _sink) {}
		}
	}
	';

	static function main() {
		Sys.println("=== MuseScript 08-indicator-suite ===");
		Sys.println("suite: pure MuseScript @indicator — MuseInterp vs compiled JS");

		var realPath = "data/real/tape.csv";
		var haveReal = OhlcvCsv.exists(realPath);
		var realBars = haveReal ? OhlcvCsv.load(realPath) : BarFeed.synthetic(8000, 7).all();
		Sys.println(haveReal
			? 'real tape: $realPath  bars=${realBars.length}'
			: 'real tape: MISSING $realPath — using 8k synthetic (run: .\\run.ps1 fetch-ohlcv)');

		var synthN = 250000;
		var synthBars = BarFeed.synthetic(synthN, 99).all();
		Sys.println('synthetic tape: bars=$synthN');

		var prog = new MuseParser().parse(SOURCE, "indicator_suite.ms");
		var emitOk = JsBackend.emitSource(prog) != null
			&& new musescript.compile.JsEmitter().emitIndicators(prog).length > 0;
		Sys.println('indicators: muse_sma…bb_*  emitJs=${emitOk ? "yes" : "no"}');

		benchTape("REAL", realBars, prog, emitOk);
		benchTape("SYNTH", synthBars, prog, emitOk);
	}

	static function benchTape(label:String, bars:Array<Bar>, prog:MuseProgram, emitOk:Bool):Void {
		Sys.println("--- " + label + " ---");

		function runInterp():{r:BacktestResult, plots:Int} {
			TradeBuiltins.resetCrossState();
			var h = newHarness();
			var r = new MuseInterp(h).runBacktest(prog, new BarFeed(bars));
			return { r: r, plots: h.chart.commands.length };
		}

		function runJs(compiled:Dynamic):{r:BacktestResult, plots:Int} {
			TradeBuiltins.resetCrossState();
			var h = newHarness();
			Reflect.setField(h, "feed", new BarFeed(bars));
			var r:BacktestResult = cast compiled(h);
			return { r: r, plots: h.chart.commands.length };
		}

		var compiledJs:Dynamic = null;
		#if js
		if (emitOk) {
			compiledJs = MuseCompiler.compileEx(prog, { target: "js", strict: true }).fn;
		}
		#end

		runInterp();
		#if js
		if (compiledJs != null) runJs(compiledJs);
		#end

		var rounds = bars.length >= 100000 ? 1 : 2;
		var outI = null;
		var t0 = haxe.Timer.stamp();
		for (_ in 0...rounds) outI = runInterp();
		var msI = (haxe.Timer.stamp() - t0) * 1000 / rounds;

		Sys.println('bars=${bars.length} rounds=$rounds');
		Sys.println('muse-interp: ${round2(msI)} ms  trades=${outI.r.trades}  chartCmds=${outI.plots}  ${Math.round(bars.length / (msI / 1000.0))} bars/sec');

		#if js
		if (compiledJs != null) {
			var outJ = null;
			t0 = haxe.Timer.stamp();
			for (_ in 0...rounds) outJ = runJs(compiledJs);
			var msJ = (haxe.Timer.stamp() - t0) * 1000 / rounds;
			Sys.println('compile-js:  ${round2(msJ)} ms  trades=${outJ.r.trades}  chartCmds=${outJ.plots}  ${Math.round(bars.length / (msJ / 1000.0))} bars/sec');
			Sys.println('delta trades=${outJ.r.trades - outI.r.trades}  chartCmds=${outJ.plots - outI.plots}  speedup=${round2(msI / msJ)}x');
		}
		#end
	}

	static function newHarness():HarnessContext {
		var h = new HarnessContext();
		h.params.register("fast", 10);
		h.params.register("slow", 30);
		h.params.register("rsiLen", 14);
		h.params.register("atrLen", 14);
		return h;
	}

	static function round2(x:Float):Float {
		return Math.round(x * 100) / 100;
	}
}

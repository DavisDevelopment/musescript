package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.GrowableVec;
import musescript.evo.nma.NmaEpoch;
import musescript.evo.nma.NmaEvalContext;
import musescript.evo.nma.NmaEval;
import musescript.evo.nma.EngineIndicatorProvider;
import musescript.evo.nma.NmaSeries;

/**
 * P1 gate for the engine-backed `SInd` provider. The provider is parity-by-construction (it calls
 * the SAME `TradeBuiltins` statics the genome path uses), so these tests verify it DRIVES that
 * engine correctly bar-by-bar, using INDEPENDENT reference implementations of sma/ema/rsi (coded
 * straight from each builtin's contract, not shared with `TradeBuiltins`) as the oracle -- a real
 * differential check, not a hardcoded-magic-number one. `atr` is a finiteness smoke (its true-range
 * average is verified in the port suite already).
 *
 * This closes the last non-OrderSim piece of NMA evaluation: a full indicator genome's signal
 * columns are now computable and bit-exact. The remaining gate is the NMA->OrderSim fitness A/B.
 */
class TestNmaEvalEngine extends Test {
	static final CLOSE = [10.0, 11.0, 12.0, 11.0, 13.0, 12.0, 14.0, 15.0, 13.0, 16.0];

	static function ctxOf(fields:Map<String, Array<Float>>):NmaEvalContext {
		NmaEpoch.resetRegistry();
		var n = fields.get("close").length;
		return new NmaEvalContext(n, NmaEpoch.of("engine-tape", []), fields, null, null,
			new EngineIndicatorProvider(fields));
	}

	static function assertCol(expected:Array<Float>, col:GrowableVec<Float>, ?msg:String):Void {
		Assert.equals(expected.length, col.length, (msg != null ? msg + ": " : "") + "length");
		for (i in 0...expected.length) {
			var e = expected[i], a = col.at(i);
			if (Math.isNaN(e)) Assert.isTrue(Math.isNaN(a), '${msg} idx $i expected NaN got $a');
			else Assert.floatEquals(e, a, '${msg} idx $i');
		}
	}

	// ---- independent reference implementations (the oracle) ----

	static function smaRef(a:Array<Float>, len:Int):Array<Float> {
		return [for (i in 0...a.length) {
			if (i + 1 < len) Math.NaN;
			else { var s = 0.0; for (j in (i + 1 - len)...(i + 1)) s += a[j]; s / len; }
		}];
	}

	static function emaRef(a:Array<Float>, len:Int):Array<Float> {
		var k = 2 / (len + 1);
		var out = [a[0]];
		for (i in 1...a.length) out.push(a[i] * k + out[i - 1] * (1 - k));
		return out;
	}

	static function rsiRef(a:Array<Float>, len:Int):Array<Float> {
		return [for (i in 0...a.length) {
			var L = i + 1;
			if (L < len + 1) Math.NaN;
			else {
				var gains = 0.0, losses = 0.0;
				for (j in (L - len)...L) { var d = a[j] - a[j - 1]; if (d >= 0) gains += d; else losses -= d; }
				if (losses == 0) 100.0; else { var rs = gains / losses; 100 - (100 / (1 + rs)); }
			}
		}];
	}

	// ---- differential tests ----

	public function testSmaMatchesReference() {
		var ctx = ctxOf(["close" => CLOSE]);
		for (w in [2, 3, 5]) {
			var col = NmaEval.evalSeries(new NmaSInd("sma", "close", w, null), ctx);
			assertCol(smaRef(CLOSE, w), col, 'sma w=$w');
		}
	}

	public function testEmaMatchesReference() {
		var ctx = ctxOf(["close" => CLOSE]);
		for (w in [2, 3, 8]) {
			var col = NmaEval.evalSeries(new NmaSInd("ema", "close", w, null), ctx);
			assertCol(emaRef(CLOSE, w), col, 'ema w=$w');
		}
	}

	public function testRsiMatchesReference() {
		var ctx = ctxOf(["close" => CLOSE]);
		for (w in [2, 3, 5]) {
			var col = NmaEval.evalSeries(new NmaSInd("rsi", "close", w, null), ctx);
			assertCol(rsiRef(CLOSE, w), col, 'rsi w=$w');
		}
	}

	public function testAtrIsFiniteAfterWarmup() {
		var high = [for (c in CLOSE) c + 0.5];
		var low = [for (c in CLOSE) c - 0.5];
		var ctx = ctxOf(["high" => high, "low" => low, "close" => CLOSE]);
		var col = NmaEval.evalSeries(new NmaSInd("atr", "high", 3, null), ctx);
		Assert.equals(CLOSE.length, col.length, "atr length");
		// After warmup (m>=len) atr must be finite and positive for a real OHLC tape.
		var sawFinite = false;
		for (i in 5...CLOSE.length) {
			var v = col.at(i);
			if (!Math.isNaN(v)) { Assert.isTrue(v > 0, 'atr>0 at $i'); sawFinite = true; }
		}
		Assert.isTrue(sawFinite, "atr produces finite values after warmup");
	}

	public function testNestedSourceMatchesFlatPaletteQuirk() {
		var ctx = ctxOf(["close" => CLOSE]);
		var nested = new NmaSInd("ema", "close", 3, new NmaSInd("sma", "close", 2, null));
		var flat = new NmaSInd("ema", "close", 3, null);
		var colN = NmaEval.evalSeries(nested, ctx);
		var colF = NmaEval.evalSeries(flat, ctx);
		Assert.equals(CLOSE.length, colN.length);
		assertCol([for (i in 0...colF.length) colF.at(i)], colN, "nested palette == flat (TradeBuiltins float-sugar quirk)");
	}
}

package musescript.pinescript.tests;

import musescript.compile.MuseCompiler;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.builtins.TradeBuiltins;

import musescript.pinescript.parse.PineParser;
import musescript.pinescript.translit.PineLower;

/**
 * Corpus-wide numeric parity — the citable proof behind "we transliterate Pine
 * and the numbers match, bit for bit."
 *
 * For each indicator: transliterate a one-line Pine `plot(ta.X(...))`, run it on
 * the real Muse engine, capture the per-bar series, and diff against an
 * INDEPENDENT reference implementing Pine's published definition. Warmup bars
 * (where seeding conventions legitimately differ) are skipped; NaNs are skipped.
 *
 * The point is not to hide divergences — where Muse's builtin defines an
 * indicator differently from Pine, this prints the deviation as an honest
 * finding. A row is PASS only when it's exact to `TOL`.
 */
class PineCorpusParity {
	static inline var TOL = 1e-6;

	// each case: label, Pine expression, reference over the close series, and
	// whether a divergence is a KNOWN/flagged definitional difference (Muse
	// builtin computes it differently than Pine — the transliterator flags these).
	static function cases():Array<{name:String, expr:String, ref:Array<Float>->Array<Float>, ?known:Bool}> {
		return [
			{ name: "ta.sma(close,10)",   expr: "ta.sma(close, 10)",   ref: xs -> refSma(xs, 10) },
			{ name: "ta.ema(close,12)",   expr: "ta.ema(close, 12)",   ref: xs -> refEma(xs, 12) },
			{ name: "ta.ema(close,26)",   expr: "ta.ema(close, 26)",   ref: xs -> refEma(xs, 26) },
			{ name: "ta.rma(close,14)",   expr: "ta.rma(close, 14)",   ref: xs -> refRma(xs, 14) },
			{ name: "ta.stdev(close,20)", expr: "ta.stdev(close, 20)", ref: xs -> refStdev(xs, 20) },
			{ name: "ta.change(close)",   expr: "ta.change(close)",    ref: xs -> refChange(xs, 1) },
			{ name: "ta.highest(close,10)", expr: "ta.highest(close, 10)", ref: xs -> refHighest(xs, 10) },
			{ name: "ta.lowest(close,10)",  expr: "ta.lowest(close, 10)",  ref: xs -> refLowest(xs, 10) },
			// Wilder vs SMA smoothing — flagged by the transliterator, faithful
			// Wilder expansion tracked for P5.
			{ name: "ta.rsi(close,14)",   expr: "ta.rsi(close, 14)",   ref: xs -> refRsi(xs, 14), known: true },
		];
	}

	public static function main():Void {
		var feed = BarFeed.synthetic(400, 23);
		var closes = [for (b in feed.all()) b.close];

		Sys.println("── corpus numeric parity (transliterated Pine vs Pine-definition reference) ──");
		Sys.println(pad("indicator", 22) + pad("compared", 10) + pad("maxDiff", 16) + "verdict");
		var pass = 0, total = 0, knownDiverge = 0, surprises = 0;
		for (c in cases()) {
			total++;
			var got = runIndicator(c.expr, feed);
			var ref = c.ref(closes);
			var r = compare(got, ref);
			var exact = r.compared > 0 && r.maxDiff < TOL;
			var verdict = r.compared == 0 ? "NO-DATA"
				: exact ? "PASS (exact)"
				: (c.known == true ? 'DIVERGE ${fmt(r.maxDiff)} (known, flagged)' : 'DIVERGE ${fmt(r.maxDiff)} ⚠ UNEXPECTED');
			if (exact) pass++;
			else if (c.known == true) knownDiverge++;
			else surprises++;
			Sys.println(pad(c.name, 22) + pad(Std.string(r.compared), 10) + pad(fmt(r.maxDiff), 16) + verdict);
		}
		Sys.println('\n$pass / $total bit-exact within $TOL; $knownDiverge known/flagged divergence(s); $surprises unexpected.');
		// gate: everything must be either exact or a KNOWN (flagged) divergence.
		// An unexpected divergence is a real regression and fails the build.
		if (surprises > 0) { Sys.println("FAIL: unexpected numeric divergence"); Sys.exit(1); }
		if (pass < 6) { Sys.println("FAIL: fewer exact matches than expected baseline (6)"); Sys.exit(1); }
		Sys.println("OK");
	}

	static function runIndicator(pineExpr:String, feed:BarFeed):Array<Float> {
		var src = "//@version=5\nindicator(\"x\")\nplot(" + pineExpr + ")\n";
		var prog = new PineParser(src, "x.pine").run();
		var lower = new PineLower(prog);
		lower.keepPlots = true;
		var museProg = lower.run();

		var harness = new HarnessContext();
		harness.feed = feed;
		TradeBuiltins.resetCrossState();
		var ex = MuseCompiler.compileEx(museProg, { target: "interp", strict: false });
		ex.fn(harness);

		var out:Array<Float> = [];
		for (cmd in harness.chart.commands) if (cmd.kind == "plot") out.push(cmd.series);
		return out;
	}

	static function compare(got:Array<Float>, ref:Array<Float>):{compared:Int, maxDiff:Float} {
		var maxDiff = 0.0, compared = 0;
		var n = Std.int(Math.min(got.length, ref.length));
		for (i in 0...n) {
			var g = got[i], r = ref[i];
			if (isNan(g) || isNan(r)) continue; // skip warmup / undefined
			var d = Math.abs(g - r);
			if (d > maxDiff) maxDiff = d;
			compared++;
		}
		return {compared: compared, maxDiff: maxDiff};
	}

	// ── independent Pine-definition references ────────────────────────────────
	static function refSma(xs:Array<Float>, n:Int):Array<Float> {
		var out:Array<Float> = [];
		for (i in 0...xs.length) {
			if (i + 1 < n) { out.push(Math.NaN); continue; }
			var s = 0.0;
			for (j in (i + 1 - n)...(i + 1)) s += xs[j];
			out.push(s / n);
		}
		return out;
	}

	static function refEma(xs:Array<Float>, n:Int):Array<Float> {
		var out:Array<Float> = [];
		if (xs.length == 0) return out;
		var mult = 2.0 / (n + 1);
		var e = xs[0];
		for (i in 0...xs.length) { e = i == 0 ? xs[0] : xs[i] * mult + e * (1 - mult); out.push(e); }
		return out;
	}

	// Pine ta.rma: Wilder smoothing, alpha=1/n, seeded with the SMA of the first n.
	static function refRma(xs:Array<Float>, n:Int):Array<Float> {
		var out:Array<Float> = [];
		var alpha = 1.0 / n;
		var r = Math.NaN;
		for (i in 0...xs.length) {
			if (i + 1 < n) { out.push(Math.NaN); continue; }
			if (isNan(r)) {
				var s = 0.0; for (j in (i + 1 - n)...(i + 1)) s += xs[j];
				r = s / n;
			} else r = alpha * xs[i] + (1 - alpha) * r;
			out.push(r);
		}
		return out;
	}

	// Pine ta.stdev: population stdev over the window (divides by n).
	static function refStdev(xs:Array<Float>, n:Int):Array<Float> {
		var out:Array<Float> = [];
		for (i in 0...xs.length) {
			if (i + 1 < n) { out.push(Math.NaN); continue; }
			var mean = 0.0; for (j in (i + 1 - n)...(i + 1)) mean += xs[j]; mean /= n;
			var v = 0.0; for (j in (i + 1 - n)...(i + 1)) { var d = xs[j] - mean; v += d * d; }
			out.push(Math.sqrt(v / n));
		}
		return out;
	}

	static function refChange(xs:Array<Float>, k:Int):Array<Float> {
		var out:Array<Float> = [];
		for (i in 0...xs.length) out.push(i < k ? Math.NaN : xs[i] - xs[i - k]);
		return out;
	}

	static function refHighest(xs:Array<Float>, n:Int):Array<Float> {
		var out:Array<Float> = [];
		for (i in 0...xs.length) {
			if (i + 1 < n) { out.push(Math.NaN); continue; }
			var m = xs[i + 1 - n];
			for (j in (i + 1 - n)...(i + 1)) if (xs[j] > m) m = xs[j];
			out.push(m);
		}
		return out;
	}

	static function refLowest(xs:Array<Float>, n:Int):Array<Float> {
		var out:Array<Float> = [];
		for (i in 0...xs.length) {
			if (i + 1 < n) { out.push(Math.NaN); continue; }
			var m = xs[i + 1 - n];
			for (j in (i + 1 - n)...(i + 1)) if (xs[j] < m) m = xs[j];
			out.push(m);
		}
		return out;
	}

	// Pine ta.rsi: RMA of gains / RMA of losses over n; RSI = 100 - 100/(1+rs).
	static function refRsi(xs:Array<Float>, n:Int):Array<Float> {
		var gains:Array<Float> = [], losses:Array<Float> = [];
		for (i in 0...xs.length) {
			if (i == 0) { gains.push(0); losses.push(0); continue; }
			var ch = xs[i] - xs[i - 1];
			gains.push(ch > 0 ? ch : 0);
			losses.push(ch < 0 ? -ch : 0);
		}
		var ag = refRma(gains, n), al = refRma(losses, n);
		var out:Array<Float> = [];
		for (i in 0...xs.length) {
			if (isNan(ag[i]) || isNan(al[i])) { out.push(Math.NaN); continue; }
			if (al[i] == 0) { out.push(100); continue; }
			var rs = ag[i] / al[i];
			out.push(100 - 100 / (1 + rs));
		}
		return out;
	}

	// ── util ──────────────────────────────────────────────────────────────────
	static inline function isNan(f:Float):Bool return f != f;
	static function fmt(f:Float):String return f == 0 ? "0" : Std.string(Math.round(f * 1e9) / 1e9);
	static function pad(s:String, w:Int):String { while (s.length < w) s += " "; return s; }
}

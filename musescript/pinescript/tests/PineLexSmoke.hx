package musescript.pinescript.tests;

import musescript.pinescript.PineVersion;
import musescript.pinescript.lex.PineLexer;
import musescript.pinescript.lex.PineToken.PineTokens;

/**
 * P0 smoke check: tokenize a small real-shaped Pine indicator and dump the
 * stream with layout tokens. Not a golden test yet (that arrives with the
 * parser in P1) — this just proves the lexer + version sniff compile and run
 * end to end. `haxe pinescript-check.hxml` runs it.
 */
class PineLexSmoke {
	static final SAMPLE = "//@version=5
indicator(\"EMA Cross\", overlay=true)
fastLen = input.int(9, \"Fast\")
slowLen = input.int(21, \"Slow\")
fast = ta.ema(close, fastLen)
slow = ta.ema(close, slowLen)
cross = ta.crossover(fast, slow)
if cross
    strategy.entry(\"L\", strategy.long)
plot(fast, color=color.blue)
";

	public static function main():Void {
		var v = PineVersionSniff.detect(SAMPLE);
		Sys.println('detected version: v${v.toInt()}  (namespaces=${v.hasNamespaces()})');
		var toks = PineLexer.tokenize(SAMPLE, "sample.pine");
		Sys.println('token count: ${toks.length}');
		var buf = new StringBuf();
		for (t in toks) {
			buf.add(PineTokens.describe(t.kind));
			buf.add(" ");
			switch (t.kind) {
				case TNewline | TIndent | TDedent: buf.add("\n");
				default:
			}
		}
		Sys.println(buf.toString());

		// crude structural assertions so the smoke test actually fails loudly
		var indents = 0, dedents = 0;
		for (t in toks) switch (t.kind) {
			case TIndent: indents++;
			case TDedent: dedents++;
			default:
		}
		Sys.println('indents=$indents dedents=$dedents (expect balanced, >=1)');
		if (indents < 1 || indents != dedents) {
			Sys.println("FAIL: indentation tokens unbalanced");
			Sys.exit(1);
		}
		Sys.println("OK");
	}
}

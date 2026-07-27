package musescript.pinescript;

import musescript.compile.MusePrinter;
import musescript.pinescript.parse.PineParser;
import musescript.pinescript.translit.PineLower;
import musescript.pinescript.translit.BuiltinMap;
import musescript.pinescript.translit.Unsupported.UnsupportedKind;

/**
 * PineConvert — the flagship browser wedge (Asset 1).
 *
 * A pure Haxe→JS facade (`@:expose`, NO Sys / no hxnodejs), the same shape as
 * MuseRuntime: `haxe build-pine-web.hxml` emits `pine2muse-web.js` exposing
 * `window.PineConvert`, loadable with a single <script> tag, no backend, no
 * signup. `PineConvert.convert(pineSource)` returns a plain object the page
 * renders directly.
 *
 * Honesty is the product (per MARKETING_TRADINGVIEW.md §1, §4-Asset1):
 *   - Emits a coverage banner + line-cited `// TODO(pine2muse)` for every
 *     unsupported/approximated construct, INLINE at the top of the output —
 *     never a silent wrong translation.
 *   - Returns a machine-readable coverage matrix + a telemetry list of which
 *     constructs were unsupported (the self-updating roadmap the plan wants).
 *   - Surfaces repaint findings (the "your backtest was lying" wedge).
 *
 * JS shape returned by convert():
 *   {
 *     ok, version,
 *     museScript,                 // ready-to-run MuseScript, TODO-banner prepended
 *     coverage: { mapped, flagged, clean:Bool, builtinsInTable },
 *     todos:   [ { line, message } ],   // inline flags, also in the banner
 *     repaint: [ { line, detail } ],    // lookahead / realtime-branch findings
 *     unsupported: [ { kind, line } ],  // telemetry: what to build next
 *     errors:  [ { line, message } ]    // parse errors (still returns best-effort)
 *   }
 */
@:expose("PineConvert")
class PineConvert {
	/** No-op entry; the module exists to expose its static API to JS. */
	static function main() {}

	public static function convert(source:String, ?origin:String):Dynamic {
		if (source == null) source = "";
		var parser = new PineParser(source, origin != null ? origin : "<pine>");
		var prog = parser.run();

		var res = PineLower.lower(prog);
		var lo = res.lower;
		var body = new MusePrinter().printProgram(res.program);

		// ── build the telemetry + TODO lists ──────────────────────────────────
		var todos:Array<Dynamic> = [];
		var unsupported:Array<Dynamic> = [];
		for (n in lo.unsupported.notes) {
			var line = n.pos != null && n.pos.line != null ? n.pos.line : 0;
			todos.push({ line: line, message: lo.unsupported.describeBare(n) });
			unsupported.push({ kind: kindTag(n.kind), line: line });
		}
		var repaint:Array<Dynamic> = [];
		for (f in lo.audit.findings) {
			var line = f.pos != null && f.pos.line != null ? f.pos.line : 0;
			repaint.push({ line: line, detail: f.detail });
		}
		var errors:Array<Dynamic> = [];
		for (e in parser.errors)
			errors.push({ line: e.pos != null && e.pos.line != null ? e.pos.line : 0, message: e.msg });

		var clean = todos.length == 0 && repaint.length == 0 && errors.length == 0;

		// ── prepend the honest coverage banner (inline, at the top) ───────────
		var banner = new StringBuf();
		banner.add("// ─────────────────────────────────────────────────────────\n");
		banner.add('// Transliterated from Pine Script v${prog.version.toInt()} by pine2muse.\n');
		if (clean) {
			banner.add("// Clean conversion — no unsupported constructs detected.\n");
		} else {
			banner.add('// ${todos.length} construct(s) flagged, ${repaint.length} repaint warning(s), ${errors.length} parse error(s).\n');
			banner.add("// Review every TODO before trusting results — we never translate silently.\n");
		}
		for (e in errors) banner.add('// PARSE ERROR line ${e.line}: ${e.message}\n');
		for (r in repaint) banner.add('// ⚠ REPAINT line ${r.line}: ${r.detail}\n');
		for (t in todos) banner.add('// TODO(pine2muse) line ${t.line}: ${t.message}\n');
		banner.add("// ─────────────────────────────────────────────────────────\n");
		banner.add("// Educational/research software. Not investment advice.\n");
		banner.add("// Backtested results are hypothetical; not future performance.\n\n");

		var museScript = banner.toString() + body + "\n";

		return {
			ok: errors.length == 0,
			version: prog.version.toInt(),
			museScript: museScript,
			coverage: {
				builtinsSeen: lo.builtinsSeen,
				builtinsMapped: lo.builtinsSeen - lo.builtinsFlagged,
				builtinsFlagged: lo.builtinsFlagged,
				constructsFlagged: todos.length,
				clean: clean,
				builtinsInTable: BuiltinMap.mappedCount()
			},
			todos: todos,
			repaint: repaint,
			unsupported: unsupported,
			errors: errors
		};
	}

	/** Stable short tag for telemetry aggregation (which constructs hit most). */
	static function kindTag(k:UnsupportedKind):String {
		return switch (k) {
			case UnknownBuiltin(name): 'unknown-builtin:$name';
			case NamedArgsApprox(callee): 'named-args:$callee';
			case TupleDestructure(_): "tuple-destructure";
			case MultiTimeframe(name): 'multi-timeframe:$name';
			case LibraryImport(_): "library-import";
			case ElseIfChain: "else-if-chain";
			case Other(what): "semantic:" + what.split(":")[0];
		};
	}
}

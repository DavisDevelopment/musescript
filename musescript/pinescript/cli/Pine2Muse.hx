package musescript.pinescript.cli;

import musescript.pinescript.parse.PineParser;
import musescript.pinescript.translit.PineLower;
import musescript.pinescript.translit.BuiltinMap;
import musescript.compile.MusePrinter;

/**
 * `pine2muse` — import a Pine script, print the transliterated MuseScript, and
 * (with --audit) an honest coverage + repaint report.
 *
 *   node build/js/pine2muse.js --source strat.pine [-o strat.ms] [--audit] [--explain] [--gate]
 *   cat strat.pine | node build/js/pine2muse.js
 *
 * Exit codes:
 *   0 — parse clean; with --gate also requires zero unsupported notes
 *   1 — parse errors
 *   2 — --gate and unsupported / approximated notes present
 *
 * Without --gate, unsupported notes print to stderr but do not fail the run —
 * the emitted `.ms` stays usable and the gaps stay visible.
 */
class Pine2Muse {
	static function argVal(name:String, def:String):String {
		var a = Sys.args();
		for (i in 0...a.length) if (a[i] == name && i + 1 < a.length) return a[i + 1];
		return def;
	}
	static function argFlag(name:String):Bool {
		for (a in Sys.args()) if (a == name) return true;
		return false;
	}

	public static function main():Void {
		var srcPath = argVal("--source", "");
		var source = srcPath != "" ? sys.io.File.getContent(srcPath) : Sys.stdin().readAll().toString();
		var origin = srcPath != "" ? srcPath : "<stdin>";
		var gate = argFlag("--gate") || argFlag("--strict");

		var parser = new PineParser(source, origin);
		var prog = parser.run();

		var parseFailed = parser.errors.length > 0;
		if (parseFailed) {
			for (e in parser.errors) Sys.stderr().writeString('parse error: ${e.msg} @ line ${e.pos.line}\n');
		}

		var res = PineLower.lower(prog);
		var ms = new MusePrinter().printProgram(res.program);

		var outPath = argVal("-o", "");
		if (outPath != "") { sys.io.File.saveContent(outPath, ms + "\n"); Sys.println('wrote $outPath'); }
		else Sys.println(ms);

		var lo = res.lower;
		var hasUnsupported = lo.unsupported.any();

		if (argFlag("--audit") || argFlag("--explain") || gate) {
			var e = Sys.stderr();
			e.writeString("\n── transliteration report ─────────────────────────────\n");
			e.writeString('pine version: v${prog.version.toInt()}\n');
			e.writeString('builtins mapped in table: ${BuiltinMap.mappedCount()}\n');
			if (lo.audit.findings.length > 0) {
				e.writeString('\nrepaint findings (${lo.audit.findings.length}):\n');
				for (f in lo.audit.findings) e.writeString("  " + lo.audit.describe(f) + "\n");
			} else e.writeString("\nno repaint patterns detected.\n");
			if (hasUnsupported) {
				e.writeString('\nunsupported / approximated (${lo.unsupported.notes.length}):\n');
				for (n in lo.unsupported.notes) e.writeString("  • " + lo.unsupported.describe(n) + "\n");
			} else e.writeString("full coverage — nothing approximated.\n");
		}

		if (parseFailed) Sys.exit(1);
		if (gate && hasUnsupported) Sys.exit(2);
		Sys.exit(0);
	}
}

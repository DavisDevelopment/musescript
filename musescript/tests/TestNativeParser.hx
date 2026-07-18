package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.parse.MuseParser;
import musescript.ast.MuseAstJson;

/**
 * ROADMAP.md "Native front end" Stage A gate: for every corpus source, the
 * native tokenizer+parser must produce a MuseAST identical to the vendored
 * hscript front end's — compared as MuseAstJson (structural) AND Std.string
 * of the raw enums (exact, catches anything JSON canonicalizes away) — with
 * ZERO counted hscript fallbacks.
 *
 * Corpus: corpus/parse/*.ms (extracted inline test sources + musegene
 * expansions), corpus/strategies/*.ms and examples/strategy-kinds/*.ms
 * (typed surface — StrategyParser handles those identically under both
 * flags; included to pin the dispatch path).
 */
class TestNativeParser extends Test {
	static var CORPUS_DIRS = ["corpus/parse", "corpus/strategies", "examples/strategy-kinds"];

	function corpusFiles():Array<String> {
		var out:Array<String> = [];
		for (dir in CORPUS_DIRS) {
			if (!sys.FileSystem.exists(dir)) continue;
			for (f in sys.FileSystem.readDirectory(dir))
				if (StringTools.endsWith(f, ".ms"))
					out.push('$dir/$f');
		}
		out.sort(Reflect.compare);
		return out;
	}

	public function testCorpusParity() {
		var entering = MuseParser.native; // restore below — the suite may be running native-ON
		var files = corpusFiles();
		Assert.isTrue(files.length >= 100, 'corpus unexpectedly small: ${files.length} files');
		var mismatches:Array<String> = [];
		for (path in files) {
			var src = sys.io.File.getContent(path);
			MuseParser.native = false;
			var legacy = try new MuseParser().parse(src, path) catch (e:Dynamic) { mismatches.push('$path: legacy parse threw: $e'); continue; };
			MuseParser.native = true;
			var before = MuseParser.nativeFallbacks;
			var native = try new MuseParser().parse(src, path) catch (e:Dynamic) { mismatches.push('$path: native parse threw: $e'); MuseParser.native = false; continue; };
			MuseParser.native = false;
			if (MuseParser.nativeFallbacks != before) {
				mismatches.push('$path: native parser fell back to hscript');
				continue;
			}
			var a = haxe.Json.stringify(MuseAstJson.programToJson(legacy));
			var b = haxe.Json.stringify(MuseAstJson.programToJson(native));
			if (a != b) {
				mismatches.push('$path: AST JSON mismatch');
				continue;
			}
			var sa = Std.string(legacy.decls) + "||" + Std.string(legacy.stmts);
			var sb = Std.string(native.decls) + "||" + Std.string(native.stmts);
			if (sa != sb)
				mismatches.push('$path: enum-dump mismatch (JSON-invisible difference)');
		}
		MuseParser.native = entering;
		Assert.equals(0, mismatches.length,
			mismatches.length > 0 ? 'parity failures (${mismatches.length}):\n' + mismatches.slice(0, 12).join("\n") : null);
	}
}

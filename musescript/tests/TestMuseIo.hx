package musescript.tests;

import utest.Assert;
import utest.Test;
import haxe.Json;
import musescript.builtins.FsBuiltins;
import musescript.builtins.MuseHost;
import musescript.builtins.RegexBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.io.FsGrant;
import musescript.parse.MuseParser;
import musescript.runtime.MuseRuntime;
import musescript.types.PluginCapabilities;
import musescript.types.PluginKind;

/**
 * M1: portable muse.re goldens + sandboxed muse.fs under IoGrant.
 */
class TestMuseIo extends Test {
	static function sandboxRoot():String {
		#if (sys || nodejs)
		var base = sys.FileSystem.absolutePath("build/tmp/io-sandbox");
		if (!sys.FileSystem.exists(base)) sys.FileSystem.createDirectory(base);
		var muse = StringTools.replace(base, "\\", "/");
		return muse;
		#else
		return "/tmp/io-sandbox";
		#end
	}

	static function grant(read = true, write = false):IoGrant {
		return {
			fs: {
				roots: [{ name: "workspace", abs: sandboxRoot(), read: read, write: write }],
				mode: "sync"
			}
		};
	}

	public function testResolveFlatReAndFs() {
		Assert.equals("re_compile", MuseHost.resolveFlat("re", "compile"));
		Assert.equals("re_match", MuseHost.resolveFlat("re", "match"));
		Assert.equals("fs_read_text", MuseHost.resolveFlat("fs", "read_text"));
		Assert.equals("fs_list", MuseHost.resolveFlat("fs", "list"));
	}

	public function testMuseHostLowerRewritesReAndFs() {
		var src = '
			strategy S {
			  onBar {
			    muse.re.compile("a+")
			    muse.fs.read_text("x")
			  }
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("re_compile(") >= 0, printed);
		Assert.isTrue(printed.indexOf("fs_read_text(") >= 0, printed);
	}

	public function testRePortableGoldens() {
		#if (sys || nodejs)
		var json = sys.io.File.getContent("tools/re_golden/fixtures/portable.json");
		#else
		var json = "[]";
		#end
		var rows:Array<Dynamic> = Json.parse(json);
		for (row in rows) {
			var pat = RegexBuiltins.compile(row.pattern, row.flags);
			if (Reflect.hasField(row, "test")) {
				Assert.equals(row.test == true, RegexBuiltins.test(pat, row.input), Std.string(row.name));
			}
			var m = RegexBuiltins.matchOne(pat, row.input);
			if (row.match == null) {
				Assert.isNull(m, Std.string(row.name));
			} else {
				Assert.notNull(m, Std.string(row.name));
				Assert.equals(row.match.matched, m.matched, Std.string(row.name));
				Assert.equals(Std.int(row.match.start), Std.int(m.start), Std.string(row.name));
				Assert.equals(Std.int(row.match.end), Std.int(m.end), Std.string(row.name));
				var eg:Array<Dynamic> = cast row.match.groups;
				var ag:Array<Dynamic> = cast m.groups;
				Assert.equals(eg.length, ag.length, Std.string(row.name) + " groups len");
				for (i in 0...eg.length) Assert.equals(Std.string(eg[i]), Std.string(ag[i]));
			}
			if (Reflect.hasField(row, "replace")) {
				var r = row.replace;
				Assert.equals(r.expected, RegexBuiltins.replace(pat, row.input, r.repl), Std.string(row.name));
			}
			if (Reflect.hasField(row, "split")) {
				var s = row.split;
				var spat = Reflect.hasField(s, "pattern") ? s.pattern : row.pattern;
				var sflags = Reflect.hasField(s, "flags") ? s.flags : row.flags;
				var got = RegexBuiltins.split(RegexBuiltins.compile(spat, sflags), s.input, s.limit);
				var exp:Array<Dynamic> = cast s.expected;
				Assert.equals(exp.length, got.length, Std.string(row.name) + " split");
				for (i in 0...exp.length) Assert.equals(Std.string(exp[i]), got[i]);
			}
		}
	}

	public function testReRejectsUnicodeFlagAndCatastrophic() {
		var threw = false;
		try {
			RegexBuiltins.compile("a", "u");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("portable") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);

		threw = false;
		try {
			RegexBuiltins.compile("(a+)+");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("ReDoS") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);
	}

	public function testFsDeniedWithoutGrant() {
		var threw = false;
		try {
			FsBuiltins.readText(null, "x.txt");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("IoDenied") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);
	}

	public function testFsEscapeDenied() {
		var g = grant(true, false);
		var threw = false;
		try {
			FsGrant.resolve("fs_read_text", g, "../secret.txt", false);
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("IoDenied") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);

		threw = false;
		try {
			FsGrant.resolve("fs_read_text", g, "a/../../outside", false);
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("IoDenied") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);
	}

	public function testFsReadWriteListUnderGrant() {
		#if (sys || nodejs)
		var root = sandboxRoot();
		var gWrite = grant(true, true);
		FsBuiltins.writeText(gWrite, "workspace:hello.txt", "hi muse");
		Assert.isTrue(FsBuiltins.exists(gWrite, "hello.txt"));
		Assert.equals("hi muse", FsBuiltins.readText(gWrite, "workspace:hello.txt"));
		var names = FsBuiltins.list(gWrite, ".");
		Assert.isTrue(names.indexOf("hello.txt") >= 0, Std.string(names));

		var gRead = grant(true, false);
		var denied = false;
		try {
			FsBuiltins.writeText(gRead, "nope.txt", "x");
		} catch (e:Dynamic) {
			denied = true;
			Assert.isTrue(Std.string(e).indexOf("IoDenied") >= 0, Std.string(e));
		}
		Assert.isTrue(denied);
		// cleanup noise (best-effort)
		try sys.FileSystem.deleteFile(sys.FileSystem.absolutePath(root + "/hello.txt")) catch (_:Dynamic) {}
		#else
		Assert.isTrue(true);
		#end
	}

	public function testFitnessRunRefusesFsWithoutGrant() {
		var src = '
			@strategy("fs-probe")
			@on(bar) {
				fs_read_text("secret.txt");
			}
		';
		var bars = [for (i in 0...3) {
			open: 100.0, high: 101.0, low: 99.0, close: 100.0,
			volume: 1.0, time: (i : Float), index: i, data: null
		}];
		var out = MuseRuntime.run(src, bars, { tier: "interp", instrument: false, skipTruthReport: true });
		Assert.isFalse(out.ok == true, Std.string(out));
		Assert.isTrue(Std.string(out.error).indexOf("IoDenied") >= 0, Std.string(out.error));
	}

	public function testFsGrantedInterpRead() {
		#if (sys || nodejs)
		var g = grant(true, true);
		FsBuiltins.writeText(g, "probe.txt", "ok");
		var src = '
			@strategy("fs-ok")
			@on(bar) {
				var t = muse.fs.read_text("probe.txt");
				if (t == "ok") long();
			}
		';
		var bars = [for (i in 0...3) {
			open: 100.0, high: 101.0, low: 99.0, close: 100.0,
			volume: 1.0, time: (i : Float), index: i, data: null
		}];
		var h = new HarnessContext();
		h.ioGrants = g;
		var r = new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
		try sys.FileSystem.deleteFile(sys.FileSystem.absolutePath(sandboxRoot() + "/probe.txt")) catch (_:Dynamic) {}
		#else
		Assert.isTrue(true);
		#end
	}

	public function testPluginAllowsReDeniesFs() {
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Compute, "re_compile"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Panel, "re_match"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Panel, "fs_read_text"));

		var src = '{
			@strategy("w")
			@on(bar) {
				var p = muse.re.compile("a+");
				log(muse.re.test(p, "aaa"));
			}
		}';
		var prog = MuseRuntimeParseIo.parse(src);
		var a = PluginCapabilities.audit(prog, PluginKind.Panel);
		Assert.isTrue(a.ok == true, Std.string(a.error));
	}
}

private class MuseRuntimeParseIo {
	public static function parse(source:String):musescript.ast.MuseProgram {
		var prog = new MuseParser().parse(source, "<io-test>");
		prog = musescript.compile.ClassStrategyLower.expand(prog);
		prog = musescript.compile.MuseHostLower.lower(prog);
		prog = musescript.compile.TemplateExpand.expand(prog);
		prog = musescript.compile.ModuleExpand.expand(prog);
		return prog;
	}
}

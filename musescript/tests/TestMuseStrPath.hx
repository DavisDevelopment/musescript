package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.builtins.MuseHost;
import musescript.builtins.PathBuiltins;
import musescript.builtins.StringBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.parse.MuseParser;
import musescript.runtime.MuseRuntime;

/**
 * M0 IO/stdlib spine: `muse.str` / `muse.path`, path goldens, IoDenied stubs.
 */
class TestMuseStrPath extends Test {
	public function testResolveFlatStrAndPath() {
		Assert.equals("str_lower", MuseHost.resolveFlat("str", "lower"));
		Assert.equals("str_fmt", MuseHost.resolveFlat("str", "fmt"));
		Assert.equals("path_join", MuseHost.resolveFlat("path", "join"));
		Assert.equals("path_normalize", MuseHost.resolveFlat("path", "normalize"));
		Assert.equals("fs_read_text", MuseHost.resolveFlat("fs", "read_text"));
		Assert.equals("http_request", MuseHost.resolveFlat("http", "request"));
		Assert.isNull(MuseHost.resolveFlat("str", "nope"));
	}

	public function testMuseHostLowerRewritesStrAndPath() {
		var src = '
			strategy S {
			  onBar {
			    muse.str.lower("AbC")
			    muse.path.join("a", "b")
			    muse.path.normalize("/x/../y")
			  }
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("str_lower(") >= 0, printed);
		Assert.isTrue(printed.indexOf("path_join(") >= 0, printed);
		Assert.isTrue(printed.indexOf("path_normalize(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.str") < 0, printed);
		Assert.isTrue(printed.indexOf("muse.path") < 0, printed);
	}

	public function testMuseStrInterpParityWithFlat() {
		var src = '
			@strategy("str-host")
			@on(bar) {
				var a = muse.str.lower("AbC");
				var b = str_lower("AbC");
				var c = muse.str.fmt("x{0}y", "!");
				if (a == b && c == "x!y") long();
			}
		';
		var bars = [for (i in 0...5) {
			open: 100.0 + i, high: 101.0 + i, low: 99.0 + i, close: 100.5 + i,
			volume: 1000.0, time: (i : Float), index: i, data: null
		}];
		var h = new HarnessContext();
		var r = new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testStrFmtPositionalAndNamed() {
		Assert.equals("hi world", StringBuiltins.fmt("hi {0}", "world"));
		Assert.equals("a-b", StringBuiltins.fmt("{0}-{1}", ["a", "b"]));
		Assert.equals("hello muse", StringBuiltins.fmt("hello {name}", { name: "muse" }));
		Assert.equals("keep {z}", StringBuiltins.fmt("keep {z}", { name: "x" }));
	}

	public function testPathJoinNormalizeGoldens() {
		Assert.equals("a/b/c", PathBuiltins.joinParts(["a", "b", "c"]));
		Assert.equals("/a/b", PathBuiltins.joinParts(["/a", "b"]));
		Assert.equals("/a/b", PathBuiltins.joinParts(["/a/", "/b"]));

		Assert.equals("/a/c", PathBuiltins.normalize("/a/b/../c"));
		Assert.equals("/a/b", PathBuiltins.normalize("/a/./b"));
		Assert.equals("/", PathBuiltins.normalize("/a/.."));
		Assert.equals("../b", PathBuiltins.normalize("a/../../b"));
		Assert.equals(".", PathBuiltins.normalize(""));
		Assert.equals(".", PathBuiltins.normalize("."));
		Assert.equals("a/b", PathBuiltins.normalize("a//b"));

		Assert.equals("file.txt", PathBuiltins.basename("/tmp/file.txt"));
		Assert.equals("/tmp", PathBuiltins.dirname("/tmp/file.txt"));
		Assert.equals(".", PathBuiltins.dirname("file.txt"));
		Assert.equals("/", PathBuiltins.dirname("/file.txt"));
		Assert.equals(".txt", PathBuiltins.ext("/tmp/file.txt"));
		Assert.equals("", PathBuiltins.ext("file"));
		Assert.equals("", PathBuiltins.ext(".hidden"));

		Assert.isTrue(PathBuiltins.isAbsolute("/a/b"));
		Assert.isFalse(PathBuiltins.isAbsolute("a/b"));
		Assert.isTrue(PathBuiltins.isAbsolute("C:/data"));
	}

	public function testPathRejectDotDotEscapeUnderRoot() {
		Assert.isTrue(PathBuiltins.isWithin("/workspace", "ok/file.txt"));
		Assert.isFalse(PathBuiltins.isWithin("/workspace", "../secret"));
		Assert.isFalse(PathBuiltins.isWithin("/workspace", "a/../../outside"));
		Assert.isTrue(PathBuiltins.isWithin("/workspace", "a/../b"));
	}

	public function testIoGrantStubsDefaultNull() {
		Assert.isNull(MuseRuntime.resolveIoGrants(null));
		Assert.isNull(MuseRuntime.resolveIoGrants({}));
		Assert.isNull(MuseRuntime.resolveIoGrants({ grants: null }));

		var threw = false;
		try {
			MuseRuntime.requireIoGrant("fs_read_text", {});
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("IoDenied") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);

		var grant:IoGrant = {
			fs: { roots: [{ name: "workspace", abs: "/tmp/ws", read: true }] }
		};
		var got = MuseRuntime.requireIoGrant("fs_read_text", { grants: grant });
		Assert.isTrue(got.fs != null && got.fs.roots.length == 1);
		Assert.isTrue(IoDenied.isPresent(grant));
	}

	public function testIoDeniedToString() {
		Assert.equals(
			"IoDenied: fs_read_text (no IO grant; host must pass opts.grants)",
			new IoDenied("fs_read_text").toString());
	}
}

package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.builtins.HttpBuiltins;
import musescript.builtins.MuseHost;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.harness.HarnessContext;
import musescript.io.FixtureStore;
import musescript.io.HttpTransport;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.io.NetGrants;
import musescript.parse.MuseParser;
import musescript.runtime.MuseRuntime;
import musescript.types.PluginCapabilities;
import musescript.types.PluginKind;

/**
 * M2: muse.http + NetGrant + FixtureStore replay/record.
 */
class TestMuseHttp extends Test {
	static function fixtureRoot():String {
		#if (sys || nodejs)
		var base = sys.FileSystem.absolutePath("build/tmp/http-fixtures");
		if (!sys.FileSystem.exists(base)) sys.FileSystem.createDirectory(base);
		return StringTools.replace(base, "\\", "/");
		#else
		return "/tmp/http-fixtures";
		#end
	}

	static function clearFixtures():Void {
		#if (sys || nodejs)
		var dir = fixtureRoot();
		if (!sys.FileSystem.exists(dir)) return;
		for (name in sys.FileSystem.readDirectory(dir)) {
			try sys.FileSystem.deleteFile(dir + "/" + name) catch (_:Dynamic) {}
		}
		#end
	}

	static function netGrant(mode:String, ?hosts:Array<String>):IoGrant {
		return {
			net: {
				allow_hosts: hosts != null ? hosts : ["api.example.com", "*.github.com"],
				allow_schemes: ["https", "http"],
				timeout_ms: 5000,
				max_bytes: 1024 * 1024,
				fixture_mode: mode,
				fixture_dir: fixtureRoot()
			}
		};
	}

	public function testResolveFlatHttp() {
		Assert.equals("http_request", MuseHost.resolveFlat("http", "request"));
		Assert.equals("http_get", MuseHost.resolveFlat("http", "get"));
		Assert.equals("http_post", MuseHost.resolveFlat("http", "post"));
	}

	public function testMuseHostLowerRewritesHttp() {
		var src = '
			strategy S {
			  onBar {
			    muse.http.get("https://api.example.com/x")
			  }
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("http_get(") >= 0, printed);
	}

	public function testDeniedWithoutNetGrant() {
		var threw = false;
		try {
			HttpBuiltins.get(null, null, "https://api.example.com/x");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("IoDenied") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);
	}

	public function testReplayMissingFixtureHardError() {
		clearFixtures();
		var g = netGrant(NetGrants.MODE_REPLAY);
		var h = new HarnessContext();
		h.ioGrants = g;
		h.isBacktest = true;
		var threw = false;
		try {
			HttpBuiltins.get(g, h, "https://api.example.com/missing");
		} catch (e:Dynamic) {
			threw = true;
			var msg = Std.string(e);
			Assert.isTrue(msg.indexOf("IoDenied") >= 0, msg);
			Assert.isTrue(msg.indexOf("fixture miss") >= 0, msg);
		}
		Assert.isTrue(threw);
	}

	public function testRecordThenReplayBodyMatch() {
		clearFixtures();
		var url = "https://api.example.com/v1/quote";
		var expectedBody = '{"ok":true,"px":42}';
		HttpTransport.testLive = function(method, u, headers, body, timeoutMs, maxBytes, follow) {
			return {
				status: 200,
				headers: { "content-type": "application/json" },
				body_text: expectedBody,
				url_final: u
			};
		};
		var ok = false;
		try {
			var gRecord = netGrant(NetGrants.MODE_RECORD);
			var h = new HarnessContext();
			h.ioGrants = gRecord;
			h.isBacktest = true;
			h.isFitness = false;
			var recorded = HttpBuiltins.get(gRecord, h, url);
			Assert.equals(200, Std.int(recorded.status));
			Assert.equals(expectedBody, Std.string(recorded.body_text));

			HttpTransport.testLive = function(method, u, headers, body, timeoutMs, maxBytes, follow) {
				return throw "live must not run in replay";
			};

			var gReplay = netGrant(NetGrants.MODE_REPLAY);
			h.ioGrants = gReplay;
			var replayed = HttpBuiltins.get(gReplay, h, url);
			Assert.equals(expectedBody, Std.string(replayed.body_text));
			Assert.equals(200, Std.int(replayed.status));
			ok = true;
		} catch (e:Dynamic) {
			HttpTransport.testLive = null;
			clearFixtures();
			throw e;
		}
		HttpTransport.testLive = null;
		clearFixtures();
		Assert.isTrue(ok);
	}

	public function testFitnessPathDeniesHttp() {
		var src = '
			@strategy("http-probe")
			@on(bar) {
				http_get("https://api.example.com/x");
			}
		';
		var bars = [for (i in 0...3) {
			open: 100.0, high: 101.0, low: 99.0, close: 100.0,
			volume: 1.0, time: (i : Float), index: i, data: null
		}];
		var out = MuseRuntime.run(src, bars, {
			tier: "interp", instrument: false, skipTruthReport: true, fitness: true
		});
		Assert.isFalse(out.ok == true, Std.string(out));
		Assert.isTrue(Std.string(out.error).indexOf("IoDenied") >= 0, Std.string(out.error));
	}

	public function testFitnessRefusesRecordEvenWithGrant() {
		clearFixtures();
		HttpTransport.testLive = function(method, u, headers, body, timeoutMs, maxBytes, follow) {
			return { status: 200, headers: {}, body_text: "nope", url_final: u };
		};
		var threw = false;
		try {
			var g = netGrant(NetGrants.MODE_RECORD);
			var h = new HarnessContext();
			h.ioGrants = g;
			h.isFitness = true;
			h.isBacktest = true;
			try {
				HttpBuiltins.get(g, h, "https://api.example.com/x");
			} catch (e:Dynamic) {
				threw = true;
				Assert.isTrue(Std.string(e).indexOf("fitness") >= 0, Std.string(e));
			}
		} catch (e:Dynamic) {
			HttpTransport.testLive = null;
			throw e;
		}
		HttpTransport.testLive = null;
		Assert.isTrue(threw);
	}

	public function testStrictRefusedInBacktest() {
		HttpTransport.testLive = function(method, u, headers, body, timeoutMs, maxBytes, follow) {
			return { status: 200, headers: {}, body_text: "live", url_final: u };
		};
		var threw = false;
		try {
			var g = netGrant(NetGrants.MODE_STRICT);
			var h = new HarnessContext();
			h.ioGrants = g;
			h.isBacktest = true;
			try {
				HttpBuiltins.get(g, h, "https://api.example.com/x");
			} catch (e:Dynamic) {
				threw = true;
				Assert.isTrue(Std.string(e).indexOf("silent-live") >= 0
					|| Std.string(e).indexOf("backtest") >= 0, Std.string(e));
			}
		} catch (e:Dynamic) {
			HttpTransport.testLive = null;
			throw e;
		}
		HttpTransport.testLive = null;
		Assert.isTrue(threw);
	}

	public function testHostAllowlistDenies() {
		var g = netGrant(NetGrants.MODE_REPLAY, ["api.example.com"]);
		var h = new HarnessContext();
		var threw = false;
		try {
			HttpBuiltins.get(g, h, "https://evil.example.org/x");
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("allow_hosts") >= 0, Std.string(e));
		}
		Assert.isTrue(threw);
	}

	public function testPluginDeniesIoNet() {
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Panel, "http_get"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Compute, "http_request"));
		var src = '{
			@strategy("w")
			@on(bar) {
				muse.http.get("https://api.example.com/x");
			}
		}';
		var prog = MuseRuntimeParseHttp.parse(src);
		var a = PluginCapabilities.audit(prog, PluginKind.Panel);
		Assert.isFalse(a.ok == true);
		Assert.isTrue(Std.string(a.error).indexOf("io_net") >= 0
			|| Std.string(a.error).indexOf("http_get") >= 0, Std.string(a.error));
	}

	public function testCliHttpModeOverride() {
		clearFixtures();
		var store = new FixtureStore(fixtureRoot());
		store.save("GET", "https://api.example.com/cli", null, {
			status: 200, headers: {}, body_text: "from-fixture", url_final: "https://api.example.com/cli"
		});
		var g = netGrant(NetGrants.MODE_STRICT); // would refuse live in backtest
		var h = new HarnessContext();
		MuseRuntime.applyIoGrants(h, { grants: g, http: "replay", isBacktest: true });
		Assert.equals(NetGrants.MODE_REPLAY, h.ioGrants.net.fixture_mode);
		var resp = HttpBuiltins.get(h.ioGrants, h, "https://api.example.com/cli");
		Assert.equals("from-fixture", Std.string(resp.body_text));
		clearFixtures();
	}
}

private class MuseRuntimeParseHttp {
	public static function parse(source:String):musescript.ast.MuseProgram {
		var prog = new MuseParser().parse(source, "<http-test>");
		prog = musescript.compile.ClassStrategyLower.expand(prog);
		prog = musescript.compile.MuseHostLower.lower(prog);
		prog = musescript.compile.TemplateExpand.expand(prog);
		prog = musescript.compile.ModuleExpand.expand(prog);
		return prog;
	}
}

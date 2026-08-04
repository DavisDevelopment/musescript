package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.HarnessContext;
import musescript.harness.OhlcvCsv;
import musescript.io.CliIoGrants;
import musescript.io.HttpTransport;
import musescript.io.IoGrant;
import musescript.io.NetGrants;
import musescript.runtime.MuseRuntime;
import musescript.types.PluginCapabilities;
import musescript.types.PluginKind;

/**
 * Ingest program kind: muse.http → muse.fs / pd_read_csv → PIT tape;
 * fitness keeps io=null.
 */
class TestMuseIngest extends Test {
	static function sandboxRoot():String {
		#if (sys || nodejs)
		var base = sys.FileSystem.absolutePath("build/tmp/ingest-sandbox");
		if (!sys.FileSystem.exists(base)) sys.FileSystem.createDirectory(base);
		return StringTools.replace(base, "\\", "/");
		#else
		return "/tmp/ingest-sandbox";
		#end
	}

	static function fixtureRoot():String {
		#if (sys || nodejs)
		var base = sys.FileSystem.absolutePath("build/tmp/ingest-http-fixtures");
		if (!sys.FileSystem.exists(base)) sys.FileSystem.createDirectory(base);
		return StringTools.replace(base, "\\", "/");
		#else
		return "/tmp/ingest-http-fixtures";
		#end
	}

	static function clearDir(dir:String):Void {
		#if (sys || nodejs)
		if (!sys.FileSystem.exists(dir)) return;
		for (name in sys.FileSystem.readDirectory(dir)) {
			var p = dir + "/" + name;
			try {
				if (sys.FileSystem.isDirectory(p)) clearDir(p);
				else sys.FileSystem.deleteFile(p);
			} catch (_:Dynamic) {}
		}
		#end
	}

	static function ohlcvCsv():String {
		return "time,open,high,low,close,volume\n"
			+ "1,100,101,99,100.5,1000\n"
			+ "2,100.5,102,100,101.5,1100\n"
			+ "3,101.5,103,101,102,1200\n";
	}

	static function ingestGrants(mode:String):IoGrant {
		return {
			fs: {
				roots: [{ name: "workspace", abs: sandboxRoot(), read: true, write: true }],
				mode: "sync"
			},
			net: {
				allow_hosts: ["api.example.com"],
				allow_schemes: ["https", "http"],
				timeout_ms: 5000,
				max_bytes: 1024 * 1024,
				fixture_mode: mode,
				fixture_dir: fixtureRoot()
			}
		};
	}

	static inline var INGEST_SRC = '
{
  @strategy("ingest_http_csv")
  {
    var resp = muse.http.get("https://api.example.com/ohlcv.csv");
    muse.fs.mkdir("tapes", true);
    muse.fs.write_text("tapes/DEMO.csv", resp.body_text);
    var df = muse.pd.read_csv("tapes/DEMO.csv");
    log("rows");
  }
}
';

	public function testCliIoGrantsFromOpts() {
		var g = CliIoGrants.fromOpts({
			fsRoot: sandboxRoot(),
			fixtureDir: fixtureRoot(),
			allowHosts: "api.example.com,*.github.com",
			http: "replay"
		});
		Assert.notNull(g);
		Assert.notNull(g.fs);
		Assert.notNull(g.net);
		Assert.equals(NetGrants.MODE_REPLAY, g.net.fixture_mode);
		Assert.equals(2, g.net.allow_hosts.length);
	}

	public function testRunIngestRequiresGrants() {
		var out = MuseRuntime.runIngest("log(1)", {});
		Assert.isFalse(out.ok == true, Std.string(out));
		Assert.isTrue(Std.string(out.error).indexOf("grants") >= 0, Std.string(out.error));
	}

	public function testRunIngestRefusesFitnessFlag() {
		var out = MuseRuntime.runIngest("log(1)", {
			grants: ingestGrants(NetGrants.MODE_REPLAY),
			fitness: true
		});
		Assert.isFalse(out.ok == true, Std.string(out));
		Assert.isTrue(Std.string(out.error).indexOf("fitness") >= 0, Std.string(out.error));
	}

	public function testApplyIoGrantsFitnessStripsGrants() {
		var h = new HarnessContext();
		MuseRuntime.applyIoGrants(h, {
			grants: ingestGrants(NetGrants.MODE_RECORD),
			fitness: true
		});
		Assert.isTrue(h.isFitness);
		Assert.isNull(h.ioGrants);
		Assert.isTrue(h.isBacktest);
	}

	public function testApplyIoGrantsIngestKindNotBacktest() {
		var h = new HarnessContext();
		MuseRuntime.applyIoGrants(h, {
			grants: ingestGrants(NetGrants.MODE_REPLAY),
			kind: "ingest"
		});
		Assert.isFalse(h.isFitness);
		Assert.isFalse(h.isBacktest);
		Assert.notNull(h.ioGrants);
	}

	public function testIngestReplayWriteCsvThenOfflineRun() {
		#if (sys || nodejs)
		clearDir(sandboxRoot());
		clearDir(fixtureRoot());
		var csv = ohlcvCsv();
		HttpTransport.testLive = function(method, u, headers, body, timeoutMs, maxBytes, follow) {
			return {
				status: 200,
				headers: { "content-type": "text/csv" },
				body_text: csv,
				url_final: u
			};
		};
		var ok = false;
		try {
			// Record once into fixture store
			var rec = MuseRuntime.runIngest('
{
  @strategy("ingest_record")
  {
    var resp = muse.http.get("https://api.example.com/ohlcv.csv");
    log(resp.body_text);
  }
}
', {
				grants: ingestGrants(NetGrants.MODE_RECORD),
				http: "record",
				kind: "ingest"
			});
			Assert.isTrue(rec.ok == true, Std.string(rec));
			HttpTransport.testLive = function(method, u, headers, body, timeoutMs, maxBytes, follow) {
				return throw "live must not run in ingest replay";
			};

			var out = MuseRuntime.runIngest(INGEST_SRC, {
				grants: ingestGrants(NetGrants.MODE_REPLAY),
				http: "replay",
				kind: "ingest"
			});
			Assert.isTrue(out.ok == true, Std.string(out));
			Assert.equals("ingest", Std.string(out.kind));
			Assert.isTrue(Std.int(out.httpRequests) >= 1);

			var tapePath = sandboxRoot() + "/tapes/DEMO.csv";
			Assert.isTrue(sys.FileSystem.exists(tapePath), tapePath);
			var bars = OhlcvCsv.parse(sys.io.File.getContent(tapePath));
			Assert.equals(3, bars.length);

			// Offline fitness-style run: grants null / fitness true — no IO.
			var strat = '
			@strategy("post-ingest")
			@on(bar) {
				if (close > open) long();
			}
			';
			var runOut = MuseRuntime.run(strat, [for (b in bars) {
				open: b.open, high: b.high, low: b.low, close: b.close,
				volume: b.volume, time: b.time, index: b.index, data: null
			}], {
				tier: "interp",
				instrument: false,
				skipTruthReport: true,
				fitness: true
			});
			Assert.isTrue(runOut.ok == true, Std.string(runOut));
			Assert.isTrue(Std.int(runOut.bars) == 3);

			// Same IO surface under fitness cannot run (grants stripped)
			var probe = '
			@strategy("io-deny")
			@on(bar) {
				muse.http.get("https://api.example.com/ohlcv.csv");
			}
			';
			var denied2 = MuseRuntime.run(probe, [{
				open: 100.0, high: 101.0, low: 99.0, close: 100.0,
				volume: 1.0, time: 0.0, index: 0, data: null
			}], {
				tier: "interp",
				instrument: false,
				skipTruthReport: true,
				fitness: true,
				grants: ingestGrants(NetGrants.MODE_REPLAY)
			});
			Assert.isFalse(denied2.ok == true, Std.string(denied2));
			Assert.isTrue(Std.string(denied2.error).indexOf("IoDenied") >= 0, Std.string(denied2.error));
			ok = true;
		} catch (e:Dynamic) {
			HttpTransport.testLive = null;
			clearDir(sandboxRoot());
			clearDir(fixtureRoot());
			throw e;
		}
		HttpTransport.testLive = null;
		clearDir(sandboxRoot());
		clearDir(fixtureRoot());
		Assert.isTrue(ok);
		#else
		Assert.isTrue(true);
		#end
	}

	public function testIngestRefusesOnBarStrategy() {
		#if (sys || nodejs)
		var out = MuseRuntime.runIngest('
			@strategy("bad-ingest")
			@on(bar) {
				muse.fs.write_text("x.csv", "a");
			}
		', { grants: ingestGrants(NetGrants.MODE_REPLAY), kind: "ingest" });
		Assert.isFalse(out.ok == true, Std.string(out));
		Assert.isTrue(Std.string(out.error).indexOf("on(bar)") >= 0, Std.string(out.error));
		#else
		Assert.isTrue(true);
		#end
	}

	public function testPluginsStillDenyIo() {
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Panel, "http_get"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Compute, "fs_write_text"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Panel, "pd_read_csv"));
	}
}

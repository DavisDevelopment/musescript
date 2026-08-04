package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;
import musescript.runtime.MuseRuntime;
import musescript.types.PluginCapabilities;
import musescript.types.PluginKind;

/**
 * Engine plugin-kind capability table — replaces host-side order-verb regex gates.
 */
class TestPluginKinds extends Test {
	static function auditSrc(src:String, kind:PluginKind):Dynamic {
		var prog = MuseRuntimeParse.parse(src);
		return PluginCapabilities.audit(prog, kind);
	}

	public function testKindParseDefaultsAndAliases() {
		Assert.equals(PluginKind.Compute, PluginKind.parse(null));
		Assert.equals(PluginKind.Compute, PluginKind.parse(""));
		Assert.equals(PluginKind.Chart, PluginKind.parse("overlay"));
		Assert.equals(PluginKind.Panel, PluginKind.parse("flex"));
		Assert.equals(PluginKind.Scanner, PluginKind.parse("scan"));
		var threw = false;
		try PluginKind.parse("nope") catch (e:Dynamic) threw = true;
		Assert.isTrue(threw);
	}

	public function testOrderVerbsDeniedForEveryKind() {
		for (k in PluginKind.all()) {
			Assert.isFalse(PluginCapabilities.allows(k, "long"));
			Assert.isFalse(PluginCapabilities.allows(k, "short"));
			Assert.isFalse(PluginCapabilities.allows(k, "flat"));
			Assert.isFalse(PluginCapabilities.allows(k, "buy"));
			Assert.isFalse(PluginCapabilities.allows(k, "sell_all"));
			Assert.isFalse(PluginCapabilities.allows(k, "portfolio_apply"));
			Assert.isFalse(PluginCapabilities.allows(k, "portfolio_equity"));
			Assert.isFalse(PluginCapabilities.allows(k, "Reflect"));
		}
	}

	public function testChartAndPanelOptIn() {
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Compute, "plot"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Compute, "log"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Chart, "plot"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Chart, "log"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Panel, "plot"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Panel, "log"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Compute, "sma"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Panel, "rsi"));
	}

	public function testScannerCapReserved() {
		Assert.equals(PluginCapabilities.CAP_SCANNER, PluginCapabilities.capabilityOf("scan_top"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Scanner, "scan_top"),
			"scanner kind reserved — builtins still denied until a consumer ships");
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Panel, "scan_top"));
	}

	public function testAuditRejectsLongUnderPanel() {
		var src = '{
			@strategy("w")
			@on(bar) { long(); }
		}';
		var a = auditSrc(src, PluginKind.Panel);
		Assert.isFalse(a.ok == true);
		Assert.isTrue(Std.string(a.error).indexOf("orders") >= 0);
	}

	public function testAuditRejectsMuseOrdersLong() {
		var src = '{
			@strategy("w")
			@on(bar) { muse.orders.long(); }
		}';
		var a = auditSrc(src, PluginKind.Chart);
		Assert.isFalse(a.ok == true);
	}

	public function testAuditRejectsPlotUnderCompute() {
		var src = '{
			@strategy("w")
			@on(bar) { plot(close, "c"); }
		}';
		var a = auditSrc(src, PluginKind.Compute);
		Assert.isFalse(a.ok == true);
		Assert.isTrue(Std.string(a.error).indexOf("chart") >= 0);
	}

	public function testAuditAllowsHelloPanelUnderPanelKind() {
		var src = '{
			@indicator("sma") function(len) {
				if (bar_index + 1 < len) return null;
				var s = 0.0; var i = 0;
				while (i < len) { s = s + close[i]; i = i + 1; }
				return s / len;
			}
			@strategy("hello_panel") @param("n", 20)
			@on(bar) {
				var m = sma(n);
				plot(close, "close");
				plot(m, "sma");
				log("close=" + close);
				if (m != null) { log("sma=" + m); }
			}
		}';
		var a = auditSrc(src, PluginKind.Panel);
		Assert.isTrue(a.ok == true, Std.string(a.error));
	}

	public function testAuditAllowsHelloChartUnderChartKind() {
		var src = '{
			@indicator("sma") function(len) {
				if (bar_index + 1 < len) return null;
				var s = 0.0; var i = 0;
				while (i < len) { s = s + close[i]; i = i + 1; }
				return s / len;
			}
			@strategy("hello_chart") @param("n", 20)
			@on(bar) { plot(sma(n), "sma"); }
		}';
		var a = auditSrc(src, PluginKind.Chart);
		Assert.isTrue(a.ok == true, Std.string(a.error));
	}

	public function testMuseRuntimeCheckWidgetAndRunWidget() {
		var okSrc = '{
			@strategy("w") @param("n", 5)
			@on(bar) {
				var m = sma(close, n);
				plot(m, "sma");
				log("ok");
			}
		}';
		var gate = MuseRuntime.checkWidget(okSrc, { kind: "panel" });
		Assert.isTrue(gate.ok == true, Std.string(gate.error));

		var bad = MuseRuntime.checkWidget('{
			@strategy("w")
			@on(bar) { buy("AAPL", 1); }
		}', { kind: "panel" });
		Assert.isFalse(bad.ok == true);

		var bars:Array<Dynamic> = [];
		var px = 100.0;
		for (i in 0...40) {
			bars.push({ open: px, high: px + 1, low: px - 1, close: px + 0.2, volume: 1000, time: i });
			px += 0.2;
		}
		var run = MuseRuntime.runWidget(okSrc, bars, { kind: "panel", tier: "interp" });
		Assert.isTrue(run.ok == true, Std.string(run.error));
		Assert.equals("panel", run.kind);
	}

	public function testExecutePluginThrowsOnOrders() {
		var harness = new HarnessContext();
		harness.feed = BarFeed.synthetic(30, 1);
		var prog = new MuseParser().parse('{
			@strategy("w")
			@on(bar) { short(); }
		}', "<t>");
		prog = musescript.compile.MuseHostLower.lower(prog);
		var threw = false;
		try {
			new MuseInterp(harness).executePlugin(prog, PluginKind.Panel);
		} catch (e:Dynamic) {
			threw = true;
			Assert.isTrue(Std.string(e).indexOf("orders") >= 0 || Std.string(e).indexOf("short") >= 0);
		}
		Assert.isTrue(threw);
	}

	public function testPluginKindsTableJson() {
		var t = MuseRuntime.pluginKinds();
		Assert.equals("musescript.plugin-kinds/2", t.schema);
		Assert.isTrue(Std.isOfType(t.kinds, Array));
		var kinds:Array<Dynamic> = cast t.kinds;
		Assert.isTrue(kinds.length >= 4);
		var denied:Array<Dynamic> = cast t.alwaysDenied;
		Assert.isTrue(denied.indexOf("io_fs") >= 0);
		Assert.isTrue(denied.indexOf("io_net") >= 0);
	}

	public function testIoFsDeniedEvenIfStubInstalled() {
		Assert.equals(PluginCapabilities.CAP_IO_FS, PluginCapabilities.capabilityOf("fs_read_text"));
		Assert.equals(PluginCapabilities.CAP_IO_FS, PluginCapabilities.capabilityOf("fs_made_up_stub"));
		Assert.equals(PluginCapabilities.CAP_IO_NET, PluginCapabilities.capabilityOf("http_request"));
		Assert.equals(PluginCapabilities.CAP_IO_FS, PluginCapabilities.capabilityOf("db_open"));
		for (k in PluginKind.all()) {
			Assert.isFalse(PluginCapabilities.allows(k, "fs_read_text"));
			Assert.isFalse(PluginCapabilities.allows(k, "fs_write_text"));
			Assert.isFalse(PluginCapabilities.allows(k, "http_get"));
			Assert.isFalse(PluginCapabilities.allows(k, "db_query"));
		}
		// Pure path / string stay compute.
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Compute, "str_lower"));
		Assert.isTrue(PluginCapabilities.allows(PluginKind.Panel, "path_join"));
	}

	public function testAuditRejectsFsReadTextUnderPanel() {
		var src = '{
			@strategy("w")
			@on(bar) { fs_read_text("secret.txt"); }
		}';
		var a = auditSrc(src, PluginKind.Panel);
		Assert.isFalse(a.ok == true);
		Assert.isTrue(Std.string(a.error).indexOf("io_fs") >= 0, Std.string(a.error));
	}

	public function testAuditRejectsMuseFsAfterLower() {
		var src = '{
			@strategy("w")
			@on(bar) { muse.fs.read_text("x"); }
		}';
		var a = auditSrc(src, PluginKind.Compute);
		Assert.isFalse(a.ok == true);
		Assert.isTrue(Std.string(a.error).indexOf("io_fs") >= 0
			|| Std.string(a.error).indexOf("fs_read_text") >= 0, Std.string(a.error));
	}

	public function testAuditRejectsMuseHttpAfterLower() {
		var src = '{
			@strategy("w")
			@on(bar) { muse.http.get("https://api.example.com/x"); }
		}';
		var a = auditSrc(src, PluginKind.Panel);
		Assert.isFalse(a.ok == true);
		Assert.isTrue(Std.string(a.error).indexOf("io_net") >= 0
			|| Std.string(a.error).indexOf("http_get") >= 0, Std.string(a.error));
	}

	public function testAuditAllowsMuseStrAndPath() {
		var src = '{
			@strategy("w")
			@on(bar) {
				var s = muse.str.lower("Ab");
				var p = muse.path.join("a", "b");
				var r = muse.re.compile("a+");
				log(s);
				log(p);
				log(muse.re.test(r, "aaa"));
			}
		}';
		var a = auditSrc(src, PluginKind.Panel);
		Assert.isTrue(a.ok == true, Std.string(a.error));
	}
}

/**
 * Tiny helper so tests share MuseRuntime's parse/lower path without making
 * `parse` public — duplicate the same ClassStrategyLower → MuseHostLower →
 * TemplateExpand → ModuleExpand order.
 */
private class MuseRuntimeParse {
	public static function parse(source:String):musescript.ast.MuseProgram {
		var prog = new MuseParser().parse(source, "<plugin-test>");
		prog = musescript.compile.ClassStrategyLower.expand(prog);
		prog = musescript.compile.MuseHostLower.lower(prog);
		prog = musescript.compile.TemplateExpand.expand(prog);
		prog = musescript.compile.ModuleExpand.expand(prog);
		return prog;
	}
}

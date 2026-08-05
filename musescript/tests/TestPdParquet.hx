package musescript.tests;

import sys.io.File;
import utest.Assert;
import utest.Test;
import musescript.builtins.MuseHost;
import musescript.dataframe.Pd;
import musescript.dataframe.PdParquet;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.types.PluginCapabilities;
import musescript.types.PluginKind;
import musescript.compile.WasmPdEligibility;
import musescript.vm.VmPdEligibility;

/**
 * Grant-gated muse.pd.read_parquet / pd_read_parquet (ingest tier).
 */
class TestPdParquet extends Test {
	public function testFromObjectsNumeric() {
		var df = PdParquet.fromObjects([
			{ time: 1, fact: 10 },
			{ time: 2, fact: 20 }
		]);
		Assert.same(["time", "fact"], df.columns());
		Assert.equals(2, df.nrows());
		Assert.equals(10.0, df.get("fact").getFlat(0));
		Assert.equals(20.0, df.get("fact").getFlat(1));
	}

	public function testFromColumnarNullsAndBool() {
		var df = PdParquet.fromColumnar({
			order: ["a", "b"],
			columns: {
				a: [1.0, null, 3.0],
				b: [true, false, null]
			}
		});
		Assert.equals(3, df.nrows());
		Assert.equals(1.0, df.get("b").getFlat(0));
		Assert.equals(0.0, df.get("b").getFlat(1));
		Assert.isTrue(Math.isNaN(df.get("a").getFlat(1)));
	}

	public function testGrantDeniedAndCaps() {
		var denied = false;
		try {
			Pd.readParquet(null, "nope.parquet");
		} catch (e:Dynamic) {
			denied = Std.isOfType(e, IoDenied) || Std.string(e).indexOf("IoDenied") >= 0;
		}
		Assert.isTrue(denied);
		Assert.equals("io_fs", PluginCapabilities.capabilityOf("pd_read_parquet"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Panel, "pd_read_parquet"));
		Assert.equals("pd_read_parquet", MuseHost.resolveFlat("pd", "read_parquet"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_read_parquet"));
		Assert.isTrue(VmPdEligibility.isDocumentedUnsupported("pd_read_parquet"));
	}

	public function testReadParquetWithGrant() {
		#if (js && nodejs)
		var fixture = sys.FileSystem.absolutePath("testdata/pd_sample.parquet");
		Assert.isTrue(sys.FileSystem.exists(fixture), "checked-in testdata/pd_sample.parquet");
		var root = sys.FileSystem.absolutePath("build/pd-parquet-sandbox");
		try sys.FileSystem.createDirectory("build") catch (_:Dynamic) {}
		try sys.FileSystem.createDirectory(root) catch (_:Dynamic) {}
		var bytes = File.getBytes(fixture);
		File.saveBytes(root + "/sample.parquet", bytes);
		var museRoot = StringTools.replace(root, "\\", "/");
		var g:IoGrant = {
			fs: {
				roots: [{name: "data", abs: museRoot, read: true, write: false}]
			}
		};
		var df = Pd.readParquet(g, "sample.parquet");
		Assert.equals(2, df.nrows());
		Assert.same(["time", "fact"], df.columns());
		Assert.equals(1.0, df.get("time").getFlat(0));
		Assert.equals(10.0, df.get("fact").getFlat(0));
		Assert.equals(20.0, df.get("fact").getFlat(1));
		try sys.FileSystem.deleteFile(root + "/sample.parquet") catch (_:Dynamic) {}
		#else
		// JVM / non-Node: grant path still resolves then fails with clear host message.
		var denied = false;
		try {
			Pd.readParquet({
				fs: { roots: [{name: "data", abs: ".", read: true, write: false}] }
			}, "testdata/pd_sample.parquet");
		} catch (e:Dynamic) {
			var msg = Std.string(e);
			denied = msg.indexOf("IoDenied") >= 0
				&& (msg.indexOf("hyparquet") >= 0 || msg.indexOf("unavailable") >= 0
					|| msg.indexOf("parquet") >= 0);
		}
		Assert.isTrue(denied);
		#end
	}

	public function testFitnessDeniesReadParquet() {
		var src = '
			@strategy("pd-parquet-deny")
			@on(bar) {
				muse.pd.read_parquet("x.parquet");
			}
		';
		var bars = [for (i in 0...2) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var threw = false;
		try {
			new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		} catch (e:Dynamic) {
			threw = Std.isOfType(e, IoDenied) || Std.string(e).indexOf("IoDenied") >= 0;
		}
		Assert.isTrue(threw);
	}
}

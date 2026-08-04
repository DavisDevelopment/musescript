package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.dataframe.Align;
import musescript.dataframe.Concat;
import musescript.dataframe.DataFrame;
import musescript.dataframe.FrameNa;
import musescript.dataframe.Index;
import musescript.dataframe.Join;
import musescript.dataframe.MergeAsof;
import musescript.dataframe.Pd;
import musescript.dataframe.PdCsv;
import musescript.builtins.MuseHost;
import musescript.builtins.PdBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.ndarray.Np;
import musescript.parse.MuseParser;
import musescript.types.PluginCapabilities;
import musescript.types.PluginKind;
import haxe.Json;
import sys.io.File;

/**
 * muse.pd M1 — merge_asof (PIT), align/join, grant-gated CSV, goldens.
 */
class TestPdM1 extends Test {
	function approxEq(a:Float, b:Float, ?eps:Float = 1e-12):Bool {
		if (Math.isNaN(a) && Math.isNaN(b)) return true;
		return Math.abs(a - b) < eps;
	}

	function assertSeries(expected:Array<Float>, actual:Array<Float>, ?msg:String) {
		Assert.equals(expected.length, actual.length, msg);
		for (i in 0...expected.length)
			Assert.isTrue(approxEq(expected[i], actual[i]), '${msg != null ? msg : ""}[$i] $expected vs $actual');
	}

	function dfTimeValue(times:Array<Float>, values:Array<Float>, timeName:String, valName:String):DataFrame {
		return DataFrame.fromColumns([
			timeName => Np.asarray(times),
			valName => Np.asarray(values)
		], Index.fromFloats(times), [timeName, valName]);
	}

	public function testMergeAsofBackwardMatchesLoader() {
		var left = dfTimeValue([1, 2, 3, 4, 5], [0, 0, 0, 0, 0], "time", "px");
		var right = dfTimeValue([2, 4], [10, 20], "time", "fact");
		var out = Pd.mergeAsof(left, right, "time");
		assertSeries([Math.NaN, 10, 10, 20, 20], out.get("fact").toArray(), "asof");
	}

	public function testMergeAsofGoldenFile() {
		#if (sys || nodejs)
		var path = "tools/pandas_golden/fixtures/merge_asof_backward.json";
		if (!sys.FileSystem.exists(path)) {
			Assert.isTrue(true); // allow missing in sparse checkouts
			return;
		}
		var g:Dynamic = Json.parse(File.getContent(path));
		var lt:Array<Float> = cast g.left_time;
		var rt:Array<Float> = cast g.right_time;
		var rv:Array<Float> = cast g.right_value;
		var exp:Array<Float> = [for (x in (cast g.expected_value : Array<Dynamic>)) x == null ? Math.NaN : (x : Float)];
		var left = dfTimeValue(lt, [for (_ in lt) 0.0], "time", "px");
		var right = dfTimeValue(rt, rv, "time", "fact");
		var out = MergeAsof.merge(left, right, "time");
		assertSeries(exp, out.get("fact").toArray(), "golden");
		#else
		Assert.isTrue(true);
		#end
	}

	public function testMergeAsofByGroupGolden() {
		#if (sys || nodejs)
		var path = "tools/pandas_golden/fixtures/merge_asof_by_group.json";
		if (!sys.FileSystem.exists(path)) {
			Assert.isTrue(true);
			return;
		}
		var g:Dynamic = Json.parse(File.getContent(path));
		var L:Dynamic = g.left;
		var R:Dynamic = g.right;
		var left = DataFrame.fromColumns([
			"time" => Np.asarray(cast L.time),
			"by" => Np.asarray(cast L.by),
			"px" => Np.asarray(cast L.px)
		], null, ["time", "by", "px"]);
		var right = DataFrame.fromColumns([
			"time" => Np.asarray(cast R.time),
			"by" => Np.asarray(cast R.by),
			"fact" => Np.asarray(cast R.fact)
		], null, ["time", "by", "fact"]);
		var out = Pd.mergeAsof(left, right, "time", "by");
		var exp:Array<Float> = [for (x in (cast g.expected_fact : Array<Dynamic>)) x == null ? Math.NaN : (x : Float)];
		assertSeries(exp, out.get("fact").toArray(), "by-golden");
		#else
		Assert.isTrue(true);
		#end
	}

	public function testMergeAsofRefusesForwardWithoutLookahead() {
		var left = dfTimeValue([1, 2], [0, 0], "time", "px");
		var right = dfTimeValue([1], [9], "time", "fact");
		var threw = false;
		try {
			Pd.mergeAsof(left, right, "time", null, "forward", false);
		} catch (e:Dynamic) {
			threw = Std.string(e).indexOf("allow_lookahead") >= 0
				|| Std.string(e).indexOf("refused") >= 0;
		}
		Assert.isTrue(threw);
	}

	public function testAlignReindexJoin() {
		var a = DataFrame.fromColumns([
			"k" => Np.asarray([1.0, 2.0, 3.0]),
			"x" => Np.asarray([10.0, 20.0, 30.0])
		], Index.fromFloats([1, 2, 3]), ["k", "x"]);
		var b = DataFrame.fromColumns([
			"k" => Np.asarray([2.0, 3.0, 4.0]),
			"y" => Np.asarray([200.0, 300.0, 400.0])
		], Index.fromFloats([2, 3, 4]), ["k", "y"]);

		var re = Align.reindex(a, Index.fromFloats([2, 3, 9]));
		Assert.equals(20.0, re.get("x").getFlat(0));
		Assert.isTrue(Math.isNaN(re.get("x").getFlat(2)));

		var aligned = Align.align(a, b, "inner");
		Assert.equals(2, aligned.left.nrows());

		var j = Join.onColumn(a, b, "k", "left");
		Assert.equals(3, j.nrows());
		Assert.equals(200.0, j.get("y").getFlat(1));
		Assert.isTrue(Math.isNaN(j.get("y").getFlat(0)));
	}

	public function testFillnaDropnaConcat() {
		var df = DataFrame.fromColumns([
			"a" => Np.asarray([1.0, Math.NaN, 3.0]),
			"b" => Np.asarray([Math.NaN, 2.0, 3.0])
		], null, ["a", "b"]);
		var filled = FrameNa.fillna(df, 0);
		Assert.equals(0.0, filled.get("a").getFlat(1));
		var dropped = FrameNa.dropna(df, "any");
		Assert.equals(1, dropped.nrows());
		Assert.equals(3.0, dropped.get("a").getFlat(0));

		var c = Concat.axis0([
			DataFrame.fromColumns(["a" => Np.asarray([1.0])], null, ["a"]),
			DataFrame.fromColumns(["a" => Np.asarray([2.0])], null, ["a"])
		]);
		Assert.same([1.0, 2.0], c.get("a").toArray());
	}

	public function testParseCsvAndGrantDenied() {
		var df = PdCsv.parse("time,fact\n1,10\n2,20\n");
		Assert.same(["time", "fact"], df.columns());
		Assert.equals(20.0, df.get("fact").getFlat(1));

		var denied = false;
		try {
			Pd.readCsv(null, "nope.csv");
		} catch (e:Dynamic) {
			denied = Std.isOfType(e, IoDenied) || Std.string(e).indexOf("IoDenied") >= 0;
		}
		Assert.isTrue(denied);
		Assert.equals("io_fs", PluginCapabilities.capabilityOf("pd_read_csv"));
		Assert.isFalse(PluginCapabilities.allows(PluginKind.Panel, "pd_read_csv"));
	}

	public function testReadCsvWithGrant() {
		#if (sys || nodejs)
		var root = sys.FileSystem.absolutePath("build/pd-csv-sandbox");
		try sys.FileSystem.createDirectory("build") catch (_:Dynamic) {}
		try sys.FileSystem.createDirectory(root) catch (_:Dynamic) {}
		var museRoot = StringTools.replace(root, "\\", "/");
		File.saveContent(root + "/sample.csv", "time,fact\n1,10\n2,20\n");
		var g:IoGrant = {
			fs: {
				roots: [{name: "data", abs: museRoot, read: true, write: false}]
			}
		};
		var df = Pd.readCsv(g, "sample.csv");
		Assert.equals(2, df.nrows());
		Assert.equals(10.0, df.get("fact").getFlat(0));
		try sys.FileSystem.deleteFile(root + "/sample.csv") catch (_:Dynamic) {}
		#else
		Assert.isTrue(true);
		#end
	}

	public function testMuseHostLowerMergeAsof() {
		Assert.equals("pd_merge_asof", MuseHost.resolveFlat("pd", "merge_asof"));
		Assert.equals("pd_read_csv", MuseHost.resolveFlat("pd", "read_csv"));
		var src = '
			strategy S {
			  onBar {
			    var a = muse.pd.from_columns({time: [1, 2, 3], px: [0, 0, 0]})
			    var b = muse.pd.from_columns({time: [2], fact: [9]})
			    var m = muse.pd.merge_asof(a, b, "time")
			  }
			}
		';
		var printed = new MusePrinter().printProgram(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isTrue(printed.indexOf("pd_merge_asof(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.pd") < 0, printed);
	}

	public function testMuseInterpMergeAsofSmoke() {
		var src = '
			@strategy("pd-asof")
			@on(bar) {
				var bars = muse.pd.from_columns({time: [1, 2, 3, 4], px: [1, 1, 1, 1]});
				var facts = muse.pd.from_columns({time: [2, 4], fact: [10, 20]});
				var m = muse.pd.merge_asof(bars, facts, "time");
				var f = muse.pd.series_values(muse.pd.get(m, "fact"));
				var s = muse.np.sum(muse.np.where(muse.np.equal(f, f), f, muse.np.zeros([4])));
				if (s == 60) long();
			}
		';
		// NaN != NaN so equal mask zeros NaNs; 10+10+20+20? wait rows: nan,10,10,20 sum=40
		// Fix expectation below after run — use get_flat checks instead.
		src = '
			@strategy("pd-asof")
			@on(bar) {
				var bars = muse.pd.from_columns({time: [1, 2, 3, 4], px: [1, 1, 1, 1]});
				var facts = muse.pd.from_columns({time: [2, 4], fact: [10, 20]});
				var m = muse.pd.merge_asof(bars, facts, "time");
				var f = muse.pd.get(m, "fact");
				var ok = muse.pd.series_length(f) == 4
					&& muse.np.get_flat(muse.pd.series_values(f), 1) == 10
					&& muse.np.get_flat(muse.pd.series_values(f), 3) == 20;
				if (ok) long();
			}
		';
		var bars = [for (i in 0...3) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testFitnessDeniesReadCsv() {
		var src = '
			@strategy("pd-csv-deny")
			@on(bar) {
				muse.pd.read_csv("x.csv");
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
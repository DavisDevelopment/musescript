package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.dataframe.DataFrame;
import musescript.dataframe.GroupBy;
import musescript.dataframe.Index;
import musescript.dataframe.Pd;
import musescript.dataframe.Resample;
import musescript.builtins.MuseHost;
import musescript.builtins.PdBuiltins;
import musescript.compile.MuseCompiler;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.WasmPdEligibility;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.interp.MuseInterp;
import musescript.ndarray.Np;
import musescript.parse.MuseParser;
import musescript.builtins.TradeBuiltins;

/**
 * muse.pd M4 — resample OHLCV + tiny WASM N `pd_rank1d`.
 */
class TestPdM4 extends Test {
	function approxEq(a:Float, b:Float, ?eps:Float = 1e-12):Bool {
		if (Math.isNaN(a) && Math.isNaN(b)) return true;
		return Math.abs(a - b) < eps;
	}

	function assertSeries(expected:Array<Float>, actual:Array<Float>, ?msg:String) {
		Assert.equals(expected.length, actual.length, msg);
		for (i in 0...expected.length)
			Assert.isTrue(approxEq(expected[i], actual[i]), '${msg != null ? msg : ""}[$i] got ${actual[i]} want ${expected[i]}');
	}

	function ohlcvFrame():DataFrame {
		// 6 bars @ 1-minute steps (ms)
		var times = [0., 60000., 120000., 180000., 240000., 300000.];
		return DataFrame.fromColumns([
			"open" => Np.asarray([1., 2., 3., 4., 5., 6.]),
			"high" => Np.asarray([1.5, 2.5, 3.5, 4.5, 5.5, 6.5]),
			"low" => Np.asarray([0.5, 1.5, 2.5, 3.5, 4.5, 5.5]),
			"close" => Np.asarray([1.2, 2.2, 3.2, 4.2, 5.2, 6.2]),
			"volume" => Np.asarray([10., 20., 30., 40., 50., 60.]),
			"score" => Np.asarray([100., 200., 300., 400., 500., 600.])
		], Index.fromFloats(times), ["open", "high", "low", "close", "volume", "score"]);
	}

	public function testParseRules() {
		var b = Resample.parseRule("5");
		Assert.notNull(b);
		Assert.equals("Bars", Std.string(b.kind));
		Assert.equals(5., b.n);
		var bb = Resample.parseRule("3B");
		Assert.notNull(bb);
		Assert.equals(3., bb.n);
		var h = Resample.parseRule("1h");
		Assert.notNull(h);
		Assert.equals(3600000., h.n);
		var m = Resample.parseRule("2m");
		Assert.notNull(m);
		Assert.equals(120000., m.n);
		Assert.isNull(Resample.parseRule("weekly"));
	}

	public function testResampleBarCountOhlcv() {
		var df = ohlcvFrame();
		var out = Pd.resample(df, "2");
		Assert.equals(3, out.nrows());
		assertSeries([1., 3., 5.], out.get("open").toArray(), "open first");
		assertSeries([2.5, 4.5, 6.5], out.get("high").toArray(), "high max");
		assertSeries([0.5, 2.5, 4.5], out.get("low").toArray(), "low min");
		assertSeries([2.2, 4.2, 6.2], out.get("close").toArray(), "close last");
		assertSeries([30., 70., 110.], out.get("volume").toArray(), "vol sum");
		assertSeries([200., 400., 600.], out.get("score").toArray(), "score last");
		var idx = Index.asF64(out.index);
		Assert.notNull(idx);
		assertSeries([60000., 180000., 300000.], idx.toArray(), "last labels");
	}

	public function testResampleDuration() {
		var df = ohlcvFrame();
		// 2-minute bins from t0: [0,120), [120,240), [240,360)
		var out = Pd.resample(df, "2m");
		Assert.equals(3, out.nrows());
		assertSeries([1., 3., 5.], out.get("open").toArray(), "dur open");
		assertSeries([2.2, 4.2, 6.2], out.get("close").toArray(), "dur close");
		assertSeries([30., 70., 110.], out.get("volume").toArray(), "dur vol");
	}

	public function testResampleUniformMean() {
		var df = DataFrame.fromColumns([
			"x" => Np.asarray([1., 3., 5., 7.])
		], Index.fromFloats([0., 1., 2., 3.]), ["x"]);
		var out = Resample.agg(df, "2", "mean");
		Assert.equals(2, out.nrows());
		assertSeries([2., 6.], out.get("x").toArray(), "mean");
	}

	public function testRank1dParity() {
		var xs = Np.asarray([30., 10., 20., 10.]);
		var r = Pd.rank1d(xs);
		// values 10,10,20,30 → ranks 1.5, 1.5, 3, 4 at positions
		assertSeries([4., 1.5, 3., 1.5], r.toArray(), "abs");
		var p = Pd.rank1d(xs, true);
		assertSeries([1., 1.5 / 4., 3. / 4., 1.5 / 4.], p.toArray(), "pct");
		var viaGb = GroupBy.rank1d(xs, false, true);
		assertSeries(r.toArray(), viaGb.toArray(), "groupby same");
	}

	public function testWasmPdRank1dNative() {
		Assert.equals(4, WasmPdEligibility.NATIVE_VEC.length);
		Assert.isTrue(WasmPdEligibility.isClaimedNative("pd_rank1d"));
		Assert.isTrue(WasmPdEligibility.isClaimedNative("pd_series"));
		Assert.isTrue(WasmPdEligibility.isClaimedNative("pd_shift"));
		Assert.isTrue(WasmPdEligibility.isClaimedNative("pd_series_values"));
		Assert.isTrue(WasmPdEligibility.isClaimedNative("pd_series_length"));
		Assert.isFalse(WasmPdEligibility.isDocumentedEscape("pd_series_length"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_series_name"));
		Assert.isFalse(WasmPdEligibility.isClaimedNative("pd_xs_rank"));
		Assert.isTrue(WasmPdEligibility.isDocumentedEscape("pd_resample"));
		Assert.isFalse(WasmPdEligibility.isDocumentedEscape("pd_series"));
		Assert.isFalse(WasmPdEligibility.isDocumentedEscape("pd_shift"));
		Assert.equals(64, WasmPdEligibility.MAX_VEC_LEN);
		Assert.isTrue(WasmPdEligibility.arityOk("pd_series", 1));
		Assert.isFalse(WasmPdEligibility.arityOk("pd_series", 2));
		Assert.isTrue(WasmPdEligibility.fitsShiftPeriods(1));
		Assert.isFalse(WasmPdEligibility.fitsShiftPeriods(65));

		var src = '
			strategy PdRank1dNative {
				onBar {
					r = muse.pd.rank1d([30, 10, 20, 10])
					s = muse.np.sum(r)
					when s == 10: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(wat, "pd_rank1d must not force opaque fallback");
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		// const-fold preferred: sum of ranks = 4+1.5+3+1.5 = 10
		Assert.isTrue(wat.indexOf("f64.const 10") >= 0 || wat.indexOf("call $vec_rank") >= 0, wat);
	}

	public function testWasmPdSeriesLaneNative() {
		var src = '
			strategy PdSeriesNative {
				onBar {
					s = muse.pd.series([1.0, 2.0, 3.0])
					when muse.np.get_flat(muse.pd.series_values(s), 1) == 2.0: long()
					when muse.np.sum(muse.pd.series_values(s)) != 6.0: flat()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(wat, "Series lane must not force opaque fallback");
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
	}

	public function testWasmPdSeriesShiftNative() {
		var src = '
			strategy PdSeriesShift {
				onBar {
					when muse.np.get_flat(muse.pd.series_values(muse.pd.shift(muse.pd.series(window(close, 4)), 1)), 3) > 0.0: long()
					when muse.np.get_flat(muse.pd.series_values(muse.pd.shift(muse.pd.series([5.0, 6.0, 7.0]), 1)), 1) != 5.0: flat()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(wat, "pd_shift Series chain must emit");
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		// window path needs runtime shift; const nest may fold
		Assert.isTrue(
			wat.indexOf("call $vec_shift") >= 0
			|| wat.indexOf("call $window_to_scratch") >= 0
			|| wat.indexOf("f64.const") >= 0,
			wat
		);
	}

	public function testWasmPdSeriesLengthNative() {
		var src = '
			strategy PdSeriesLen {
				onBar {
					when muse.pd.series_length(muse.pd.series([1.0, 2.0, 3.0])) == 3.0: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(wat, "pd_series_length must emit");
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		Assert.isTrue(wat.indexOf("f64.const 3") >= 0 || wat.indexOf("f64.convert_i32") >= 0, wat);
	}

	public function testWasmPdSeriesIndexCtorStillOpaque() {
		var src = '
			strategy PdSeriesIndexOpaque {
				onBar {
					when muse.pd.series([1.0], muse.pd.index_range(1)) != null: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isNull(wat, "pd_series index/name arity stays opaque U");
	}

	public function testWasmPdFrameShiftStillOpaque() {
		var src = '
			strategy PdFrameShiftOpaque {
				onBar {
					when muse.pd.shift(muse.pd.from_columns({a: [1.0, 2.0]}), 1) != null: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isNull(wat, "frame pd_shift stays opaque U");
	}

	#if (js || python)
	public function testInterpWasmParitySeriesShift() {
		if (!StrategyWasmBackend.hostReady()) {
			Assert.isTrue(true);
			return;
		}
		var source = '
			strategy PdSeriesParity {
				onBar {
					when muse.np.get_flat(muse.pd.series_values(muse.pd.shift(muse.pd.series(window(close, 4)), 1)), 3) > 0.0: long()
					when muse.np.get_flat(muse.pd.series_values(muse.pd.shift(muse.pd.series([5.0, 6.0, 7.0]), 1)), 1) != 5.0: flat()
				}
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(source));
		var wat = StrategyWasmBackend.emitWat(prog);
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);

		var feed = BarFeed.synthetic(40, 11);
		var wasmFn = MuseCompiler.compile(prog, { target: "wasm" });
		var wasmResult = wasmFn({ feed: feed });
		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext()).runBacktest(
			MuseHostLower.lower(new MuseParser().parse(source)),
			BarFeed.synthetic(40, 11)
		);
		Assert.equals(interpResult.trades, wasmResult.trades);
		Assert.isTrue(Math.abs(interpResult.finalEquity - wasmResult.finalEquity) < 1e-6);
	}
	#end

	public function testWasmPdRank1dRuntimeKernel() {
		var src = '
			strategy PdRank1dRt {
				onBar {
					xs = muse.np.asarray([close, 2, 3])
					r = muse.pd.rank1d(xs)
					s = muse.np.sum(r)
					when s == s: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_rank") >= 0, wat);
	}

	public function testWasmPdRank1dPct() {
		var src = '
			strategy PdRank1dPct {
				onBar {
					r = muse.pd.rank1d([1, 2, 3], true)
					s = muse.np.sum(r)
					when s == s: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.notNull(wat);
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		// const fold of pct ranks 1/3+2/3+1 = 2, or runtime pct kernel
		Assert.isTrue(
			wat.indexOf("call $vec_rank_pct") >= 0 || wat.indexOf("f64.const") >= 0,
			wat
		);
	}

	public function testResampleStillOpaqueFallback() {
		var src = '
			strategy PdResampleOpaque {
				onBar {
					var df = muse.pd.from_columns({open: [1, 2], close: [3, 4]})
					var r = muse.pd.resample(df, "2")
					when muse.pd.nrows(r) == 1: long()
				}
			}
		';
		var wat = StrategyWasmBackend.emitWat(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isNull(wat, "pd_resample returns TDataFrame → whole-module fallback");
	}

	public function testHostLowerResampleRank1d() {
		Assert.equals("pd_resample", MuseHost.resolveFlat("pd", "resample"));
		Assert.equals("pd_rank1d", MuseHost.resolveFlat("pd", "rank1d"));
		var src = '
			strategy S {
			  onBar {
			    var df = muse.pd.from_columns({open: [1, 2], close: [3, 4]})
			    var r = muse.pd.resample(df, "2")
			    var x = muse.pd.rank1d([1, 2, 3])
			  }
			}
		';
		var printed = new MusePrinter().printProgram(MuseHostLower.lower(new MuseParser().parse(src)));
		Assert.isTrue(printed.indexOf("pd_resample(") >= 0, printed);
		Assert.isTrue(printed.indexOf("pd_rank1d(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.pd") < 0, printed);
	}

	public function testInterpResampleSmoke() {
		var src = '
			@strategy("pd-m4")
			@on(bar) {
				var df = muse.pd.from_columns({
					open: [1, 2, 3, 4],
					high: [1.5, 2.5, 3.5, 4.5],
					low: [0.5, 1.5, 2.5, 3.5],
					close: [1.2, 2.2, 3.2, 4.2],
					volume: [10, 20, 30, 40]
				});
				var r = muse.pd.resample(df, "2");
				if (muse.pd.nrows(r) == 2) long();
			}
		';
		var bars = [for (i in 0...2) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testPdBuiltinsResample() {
		var out = PdBuiltins.resampleOf(ohlcvFrame(), "3");
		Assert.equals(2, out.nrows());
		assertSeries([60., 150.], out.get("volume").toArray(), "builtins");
	}
}

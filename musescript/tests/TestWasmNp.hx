package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.ast.MuseProgram;
import musescript.compile.MuseHostLower;
import musescript.compile.StrategyWasmBackend;
import musescript.compile.StrategyWasmEmitter;
import musescript.compile.WasmNpEligibility;
import musescript.interp.MuseInterp;
import musescript.harness.BarFeed;
import musescript.harness.HarnessContext;
import musescript.parse.MuseParser;
import musescript.builtins.TradeBuiltins;
import musescript.compile.MuseCompiler;

/**
 * WASM muse.np honesty: claimed-native ops emit vec_* / nd_matmul (no surprise
 * host_eval); documented escapes / over-cap fail closed to host_eval; parity
 * interp↔WASM on synthetic feed. Panel escape list unchanged.
 */
class TestWasmNp extends Test {
	function parse(src:String):MuseProgram {
		return MuseHostLower.lower(new MuseParser().parse(src));
	}

	function emitWat(src:String):String {
		var wat = StrategyWasmBackend.emitWat(parse(src));
		Assert.notNull(wat, src);
		return wat;
	}

	public function testEligibilityTablesCoverNativeAndEscape() {
		Assert.isTrue(WasmNpEligibility.isNativeScalar("np_dot"));
		Assert.isTrue(WasmNpEligibility.isNativeScalar("np_get_flat"));
		Assert.isTrue(WasmNpEligibility.isNativeVec("np_matmul"));
		Assert.isTrue(WasmNpEligibility.isNativeVec("np_exp"));
		Assert.isTrue(WasmNpEligibility.isNativeVec("np_log"));
		Assert.isTrue(WasmNpEligibility.isDocumentedEscape("np_reshape"));
		Assert.isFalse(WasmNpEligibility.isDocumentedEscape("np_get_flat"));
		Assert.isTrue(StrategyWasmEmitter.NP_HOST_ESCAPE.indexOf("np_reshape") >= 0);
		Assert.isTrue(StrategyWasmEmitter.NP_HOST_ESCAPE.indexOf("np_exp") < 0);
		Assert.isTrue(StrategyWasmEmitter.PANEL_HOST_ESCAPE.indexOf("bag_equal") >= 0);
	}

	public function testNativeGetFlatNoHostEval() {
		var wat = emitWat('strategy NpGetFlat {
			onBar {
				r = muse.pd.rank1d([1, 3, 2], true)
				x = muse.np.get_flat(r, 1)
				when x == x: long()
			}
		}');
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_rank_pct") >= 0 || wat.indexOf("f64.const") >= 0, wat);
		Assert.isTrue(wat.indexOf("f64.load") >= 0 || wat.indexOf("f64.const") >= 0, wat);
	}

	public function testNativeDotMeanSumNoHostEval() {
		var wat = emitWat('strategy NpNativeScalars {
			onBar {
				score = muse.np.dot([1, 2], [3, 4])
				avg = muse.np.mean([2, 4, 6])
				total = muse.np.sum(window(close, 3))
				when score == 11 && avg == 4 && total == total: long()
			}
		}');
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		Assert.isTrue(wat.indexOf("f64.const 11") >= 0 || wat.indexOf("call $vec_dot") >= 0, wat);
		Assert.isTrue(wat.indexOf("f64.const 4") >= 0 || wat.indexOf("call $vec_mean") >= 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_sum") >= 0, wat);
	}

	public function testNativeAxis0SumMeanNoHostEval() {
		var wat = emitWat('strategy NpAxis0 {
			onBar {
				s = muse.np.sum(muse.np.asarray([1, 2, 3]), 0)
				m = muse.np.mean([2, 4, 6], -1)
				when s == 6 && m == 4: long()
			}
		}');
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_sum") >= 0 || wat.indexOf("f64.const 6") >= 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_mean") >= 0 || wat.indexOf("f64.const 4") >= 0, wat);
	}

	public function testNativeExpLogDetMath() {
		var folded = emitWat('strategy NpExpFold {
			onBar {
				e = muse.np.exp([0, 1])
				s = muse.np.sum(e)
				when s == s: long()
			}
		}');
		Assert.isTrue(folded.indexOf("call $host_eval") < 0, folded);
		Assert.isTrue(folded.indexOf("call $vec_exp") < 0, folded);
		Assert.isTrue(folded.indexOf("f64.const") >= 0, folded);

		var runtime = emitWat('strategy NpExpRuntime {
			onBar {
				xs = muse.np.asarray([close, 1])
				ys = muse.np.exp(xs)
				zs = muse.np.log(muse.np.add(ys, muse.np.full([2], 1)))
				s = muse.np.sum(zs)
				when s == s: long()
			}
		}');
		Assert.isTrue(runtime.indexOf("call $host_eval") < 0, runtime);
		Assert.isTrue(runtime.indexOf("call $vec_exp") >= 0, runtime);
		Assert.isTrue(runtime.indexOf("call $vec_log") >= 0, runtime);
		Assert.isTrue(runtime.indexOf("func $det_exp") >= 0, runtime);
		Assert.isTrue(runtime.indexOf("func $det_log") >= 0, runtime);
	}

	#if (js || python)
	public function testInterpWasmParityExpLogDetMath() {
		if (!StrategyWasmBackend.hostReady()) {
			Assert.isTrue(true);
			return;
		}
		// Const-folded exp + runtime log of a close-dependent vector — both use DetMath.
		var source = 'strategy NpExpParity {
			onBar {
				e = muse.np.exp([0, 1])
				xs = muse.np.asarray([1, close])
				lx = muse.np.log(muse.np.add(xs, muse.np.ones([2])))
				s = muse.np.sum(e) + muse.np.sum(lx)
				when s == s && s > 0: long()
			}
		}';
		var prog = parse(source);
		var wat = StrategyWasmBackend.emitWat(prog);
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);

		var feed = BarFeed.synthetic(40, 11);
		var wasmFn = MuseCompiler.compile(prog, { target: "wasm" });
		var wasmResult = wasmFn({ feed: feed });
		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext()).runBacktest(parse(source), BarFeed.synthetic(40, 11));
		Assert.equals(interpResult.trades, wasmResult.trades);
		Assert.isTrue(Math.abs(interpResult.finalEquity - wasmResult.finalEquity) < 1e-6);
	}
	#end


	public function testNativeAddAndCumsumAssign() {
		var wat = emitWat('strategy NpNativeVec {
			onBar {
				xs = muse.np.asarray([1, close, 3])
				ys = muse.np.add(xs, muse.np.full([3], 1))
				cs = muse.np.cumsum(ys)
				s = muse.np.sum(cs)
				when s == s: long()
			}
		}');
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_add") >= 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_cumsum") >= 0, wat);
		Assert.isTrue(wat.indexOf("call $vec_sum") >= 0, wat);
	}

	public function testNativeMatmulConstFoldOrKernel() {
		var folded = emitWat('strategy NpMatmulFold {
			onBar {
				p = muse.np.matmul([[1, 2], [3, 4]], [[5, 6], [7, 8]])
				s = muse.np.sum(p)
				when s == 70: long()
			}
		}');
		Assert.isTrue(folded.indexOf("call $host_eval") < 0, folded);
		Assert.isTrue(folded.indexOf("f64.const 70") >= 0, folded);

		var runtime = emitWat('strategy NpMatmulRuntime {
			onBar {
				p = muse.np.matmul([[1, close], [0, 1]], [[1, 0], [0, 1]])
				s = muse.np.sum(p)
				when s == s: long()
			}
		}');
		Assert.isTrue(runtime.indexOf("call $host_eval") < 0, runtime);
		Assert.isTrue(runtime.indexOf("call $nd_matmul") >= 0, runtime);
	}

	public function testEscapeReshapeAndNontrivialAxis() {
		var reshape = emitWat('strategy NpEscapeReshape {
			onBar {
				a = muse.np.asarray([1, 2, 3, 4])
				b = muse.np.reshape(a, [2, 2])
				when muse.np.sum(b) > 0: long()
			}
		}');
		Assert.isTrue(reshape.indexOf("call $host_eval") >= 0, reshape);

		// keepdims=true forces H even for axis 0 on 1-D.
		var keep = emitWat('strategy NpEscapeKeepdims {
			onBar {
				s = muse.np.mean(muse.np.asarray([1, 2, 3]), 0, true)
				when muse.np.size(s) == 1: long()
			}
		}');
		Assert.isTrue(keep.indexOf("call $host_eval") >= 0, keep);
	}

	public function testEscapeVolTargetAndMaskQty() {
		Assert.isTrue(WasmNpEligibility.isDocumentedEscape("np_vol_target_qty"));
		Assert.isTrue(WasmNpEligibility.isDocumentedEscape("np_mask_qty"));
		Assert.isTrue(StrategyWasmEmitter.NP_HOST_ESCAPE.indexOf("np_vol_target_qty") >= 0);
		var wat = emitWat('strategy NpRiskEscape {
			onBar {
				q = muse.np.vol_target_qty(0.02, 0.04, 5)
				m = muse.np.mask_qty(muse.np.asarray([1, 0]), 2)
				when q > 0 && muse.np.sum(m) > 0: long()
			}
		}');
		Assert.isTrue(wat.indexOf("call $host_eval") >= 0, wat);
	}

	public function testEscapeOverCapVecLen() {
		var elems = [for (i in 0...65) Std.string(i)].join(", ");
		var wat = emitWat('strategy NpOverCap {
			onBar {
				s = muse.np.sum([${elems}])
				when s == s: long()
			}
		}');
		Assert.isTrue(wat.indexOf("call $host_eval") >= 0, wat);
	}

	public function testEscapeZeros2d() {
		var wat = emitWat('strategy NpZeros2d {
			onBar {
				z = muse.np.zeros([2, 3])
				when muse.np.size(z) == 6: long()
			}
		}');
		Assert.isTrue(wat.indexOf("call $host_eval") >= 0, wat);
	}

	#if (js || python)
	public function testInterpWasmParityNativeSubset() {
		if (!StrategyWasmBackend.hostReady()) {
			Assert.isTrue(true);
			return;
		}
		var source = 'strategy NpParity {
			onBar {
				score = muse.np.dot([1, 2], [close, 1])
				avg = muse.np.mean(window(close, 3))
				xs = muse.np.add([1, 2, 3], [1, 1, 1])
				total = muse.np.sum(xs, 0)
				when score > 0 && avg == avg && total == 9: long()
			}
		}';
		var prog = parse(source);
		var wat = StrategyWasmBackend.emitWat(prog);
		Assert.isTrue(wat.indexOf("call $host_eval") < 0, wat);

		var feed = BarFeed.synthetic(40, 11);
		var wasmFn = MuseCompiler.compile(prog, { target: "wasm" });
		var wasmResult = wasmFn({ feed: feed });
		TradeBuiltins.resetCrossState();
		var interpResult = new MuseInterp(new HarnessContext()).runBacktest(parse(source), BarFeed.synthetic(40, 11));
		Assert.equals(interpResult.trades, wasmResult.trades);
		Assert.isTrue(Math.abs(interpResult.finalEquity - wasmResult.finalEquity) < 1e-6);
	}

	public function testHybridEscapeStillRuns() {
		if (!StrategyWasmBackend.hostReady()) {
			Assert.isTrue(true);
			return;
		}
		var source = 'strategy NpHybrid {
			onBar {
				score = muse.np.dot([1, 2], [3, 4])
				z = muse.np.reshape(muse.np.asarray([1, 2, 3, 4]), [2, 2])
				when score == 11 && muse.np.sum(z) == 10: long()
			}
		}';
		var prog = parse(source);
		var wat = StrategyWasmBackend.emitWat(prog);
		Assert.isTrue(wat.indexOf("call $host_eval") >= 0, wat);
		Assert.isTrue(wat.indexOf("f64.const 11") >= 0 || wat.indexOf("call $vec_dot") >= 0, wat);

		var feed = BarFeed.synthetic(60, 4);
		var interpResult = new MuseInterp(new HarnessContext()).runBacktest(parse(source), feed);
		var hybridHarness = new HarnessContext();
		Reflect.setField(hybridHarness, "feed", feed);
		var hybridResult = StrategyWasmBackend.compile(parse(source))(hybridHarness);
		Assert.equals(interpResult.trades, hybridResult.trades);
		Assert.floatEquals(interpResult.finalEquity, hybridResult.finalEquity);
	}
	#end
}

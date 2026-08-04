package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.ndarray.NdArrayF64;
import musescript.ndarray.NdArrayF32;
import musescript.ndarray.NdArrayI32;
import musescript.ndarray.NdArrayBool;
import musescript.ndarray.AnyNdArray;
import musescript.ndarray.NdCast;
import musescript.ndarray.NdTypedOps;
import musescript.ndarray.Np;
import musescript.ndarray.NdBridge;
import musescript.ndarray.Broadcast;
import musescript.ndarray.Shape;
import musescript.builtins.NpBuiltins;
import musescript.builtins.MuseHost;
import musescript.builtins.MlBuiltins;
import musescript.compile.MuseHostLower;
import musescript.compile.MusePrinter;
import musescript.compile.JsBackend;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;
import musescript.indicators.GrowableVec;
import musescript.indicators.FloatSeries;
import musescript.interp.MuseInterp;
import musescript.parse.MuseParser;

/**
 * Excessive NdArray / muse.np coverage — creation, broadcast, ufuncs, reductions,
 * matmul, MuseHostLower, interp smoke, JsBackend dispatch.
 */
class TestNdArray extends Test {
	function approx(a:Float, b:Float, ?eps:Float = 1e-12):Bool
		return Math.abs(a - b) < eps;

	public function testZerosOnesFullArange() {
		var z = Np.zeros([2, 3]);
		Assert.equals(2, z.ndim);
		Assert.equals(6, z.size);
		Assert.equals(0.0, z.getFlat(0));
		Assert.equals(0.0, z.get2(1, 2));

		var o = Np.ones([4]);
		Assert.equals(4, o.size);
		Assert.equals(1.0, o.getFlat(3));

		var f = Np.full([2, 2], 7.5);
		Assert.equals(7.5, f.get2(0, 1));

		var a = Np.arange(5);
		Assert.same([0.0, 1.0, 2.0, 3.0, 4.0], a.toArray());
		Assert.same([2.0, 3.0, 4.0], Np.arange(2, 5).toArray());
		Assert.same([0.0, 2.0, 4.0], Np.arange(0, 5, 2).toArray());
	}

	public function testLinspaceEyeAsarrayReshapeSlice() {
		var ls = Np.linspace(0, 1, 5);
		Assert.equals(5, ls.size);
		Assert.isTrue(approx(ls.getFlat(0), 0));
		Assert.isTrue(approx(ls.getFlat(4), 1));
		Assert.isTrue(approx(ls.getFlat(2), 0.5));

		var eye = Np.eye(3);
		Assert.equals(1.0, eye.get2(0, 0));
		Assert.equals(0.0, eye.get2(0, 1));
		Assert.equals(1.0, eye.get2(2, 2));

		var a = Np.asarray([1, 2, 3, 4, 5, 6], [2, 3]);
		Assert.equals(2, a.shape[0]);
		Assert.equals(3, a.shape[1]);
		Assert.equals(6.0, a.get2(1, 2));

		var r = Np.reshape(a, [3, 2]);
		Assert.equals(3, r.shape[0]);
		Assert.equals(2.0, r.get2(0, 1));

		var s = Np.slice(Np.arange(10), 2, 7);
		Assert.same([2.0, 3.0, 4.0, 5.0, 6.0], s.toArray());
	}

	public function testTransposeCopyBroadcastPlan() {
		var a = Np.asarray2d([[1, 2, 3], [4, 5, 6]]);
		var t = Np.transpose(a);
		Assert.same([3, 2], Np.shapeOf(t));
		Assert.equals(4.0, t.get2(0, 1));
		Assert.equals(1.0, a.get2(0, 0)); // original unchanged

		var p = Broadcast.plan([1, 3], [2, 1]);
		Assert.isTrue(p.ok);
		Assert.same([2, 3], (p.outShape : Array<Int>));
		Assert.isFalse(Broadcast.plan([2, 3], [2, 4]).ok);
	}

	public function testUfuncsBroadcastAndWhere() {
		var a = Np.asarray([1, 2, 3]);
		var b = Np.asarray([10, 20, 30]);
		Assert.same([11.0, 22.0, 33.0], Np.add(a, b).toArray());
		Assert.same([10.0, 40.0, 90.0], Np.multiply(a, b).toArray());

		var row = Np.asarray([1, 2, 3]);
		var col = Np.asarray([10, 20], [2, 1]);
		var sum = Np.add(col, row);
		Assert.same([2, 3], Np.shapeOf(sum));
		Assert.equals(11.0, sum.get2(0, 0));
		Assert.equals(23.0, sum.get2(1, 2));

		Assert.same([1.0, 2.0, 3.0], Np.abs(Np.asarray([-1, 2, -3])).toArray());
		Assert.same([0.0, 1.0, 2.0], Np.clip(Np.asarray([-1, 1, 5]), 0, 2).toArray());

		var cond = Np.greater(a, Np.asarray([2, 2, 2]));
		Assert.same([false, false, true], cond.toArray());
		var w = Np.whereBool(cond, Np.full([3], 9), Np.full([3], -1));
		Assert.same([-1.0, -1.0, 9.0], w.toArray());
		// F64 0/1 cond still accepted
		Assert.same([-1.0, -1.0, 9.0], Np.where(cond.toF64(), Np.full([3], 9), Np.full([3], -1)).toArray());
	}

	public function testDetMathExpLog() {
		var x = Np.asarray([1.0]);
		var e = Np.exp(x);
		var back = Np.log(e);
		Assert.isTrue(approx(back.getFlat(0), 1.0, 1e-10));
	}

	public function testReductionsAxisKeepdims() {
		var a = Np.asarray([1, 2, 3, 4, 5, 6], [2, 3]);
		Assert.equals(21.0, Np.sum(a));
		Assert.isTrue(approx(Np.mean(a), 3.5));
		Assert.equals(1.0, Np.min(a));
		Assert.equals(6.0, Np.max(a));

		var s0 = Np.sumAxis(a, 0);
		Assert.same([3], Np.shapeOf(s0));
		Assert.same([5.0, 7.0, 9.0], s0.toArray());

		var s1 = Np.sumAxis(a, 1, true);
		Assert.same([2, 1], Np.shapeOf(s1));
		Assert.equals(6.0, s1.get2(0, 0));
		Assert.equals(15.0, s1.get2(1, 0));

		Assert.same([1.0, 3.0, 6.0], Np.cumsum(Np.asarray([1, 2, 3])).toArray());
		Assert.same([1.0, 1.0], Np.diff(Np.asarray([1, 2, 3])).toArray());
	}

	public function testMatmulDotOuter() {
		Assert.equals(32.0, Np.dot(Np.asarray([1, 2, 3]), Np.asarray([4, 5, 6])));
		var a = Np.asarray2d([[1, 2], [3, 4]]);
		var b = Np.asarray2d([[5, 6], [7, 8]]);
		var m = Np.matmul(a, b);
		Assert.same([2, 2], Np.shapeOf(m));
		Assert.equals(19.0, m.get2(0, 0));
		Assert.equals(22.0, m.get2(0, 1));
		Assert.equals(43.0, m.get2(1, 0));
		Assert.equals(50.0, m.get2(1, 1));

		var o = Np.outer(Np.asarray([1, 2]), Np.asarray([3, 4, 5]));
		Assert.same([2, 3], Np.shapeOf(o));
		Assert.equals(10.0, o.get2(1, 2));
	}

	public function testStackExpandSqueezeAstype() {
		var a = Np.asarray([1, 2]);
		var b = Np.asarray([3, 4]);
		var st = Np.stack([a, b], 0);
		Assert.same([2, 2], Np.shapeOf(st));
		Assert.equals(4.0, st.get2(1, 1));

		var e = Np.expandDims(a, 0);
		Assert.same([1, 2], Np.shapeOf(e));
		Assert.same([2], Np.shapeOf(Np.squeeze(e)));

		var i = Np.astype(Np.asarray([1.7, -2.2]), "i32");
		switch (i) {
			case I32(arr):
				Assert.same([1, -2], arr.toArray());
			default:
				Assert.fail("expected I32");
		}

		var f = Np.astype(Np.asarray([1.7, -2.2]), "float32");
		switch (f) {
			case F32(arr):
				Assert.equals(2, arr.size);
				Assert.isTrue(approx(arr.getFlat(0), 1.7, 1e-6));
			default:
				Assert.fail("expected F32");
		}
	}

	public function testMlMatrixShimUsesNdArray() {
		var m = MlBuiltins.matrix(2, 3, [1, 2, 3, 4, 5, 6]);
		Assert.equals(2, MlBuiltins.matrixRows(m));
		Assert.equals(6.0, MlBuiltins.matrixGet(m, 1, 2));
		var t = MlBuiltins.matrixTranspose(m);
		Assert.equals(3, MlBuiltins.matrixRows(t));
		Assert.same([1.0, 4.0, 2.0, 5.0, 3.0, 6.0], MlBuiltins.matrixData(t));
	}

	public function testMuseHostFlatResolveAndLower() {
		Assert.equals("np_zeros", MuseHost.resolveFlat("np", "zeros"));
		Assert.equals("np_matmul", MuseHost.resolveFlat("np", "matmul"));
		Assert.equals("np_asarray", MuseHost.resolveFlat("np", "array"));

		var src = '
			strategy S {
			  onBar {
			    var z = muse.np.zeros([2, 3])
			    var a = muse.np.asarray([1, 2, 3])
			    var s = muse.np.sum(a)
			  }
			}
		';
		var prog = MuseHostLower.lower(new MuseParser().parse(src));
		var printed = new MusePrinter().printProgram(prog);
		Assert.isTrue(printed.indexOf("np_zeros(") >= 0, printed);
		Assert.isTrue(printed.indexOf("np_asarray(") >= 0, printed);
		Assert.isTrue(printed.indexOf("np_sum(") >= 0, printed);
		Assert.isTrue(printed.indexOf("muse.np") < 0, printed);
	}

	public function testMuseInterpNpSmoke() {
		var src = '
			@strategy("np-smoke")
			@on(bar) {
				var z = muse.np.zeros([2, 3]);
				var a = muse.np.asarray([1, 2, 3, 4]);
				var b = muse.np.reshape(a, [2, 2]);
				var s = muse.np.sum(a);
				var p = muse.np.matmul(b, muse.np.eye(2));
				if (s == 10 && muse.np.ndim(z) == 2 && muse.np.get(p, [0, 0]) == 1) long();
			}
		';
		var bars = [for (i in 0...5) {
			open: 100. + i, high: 101. + i, low: 99. + i, close: 100.5 + i,
			volume: 1000., time: (i : Float), index: i, data: null
		}];
		var h = new HarnessContext();
		var r = new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testMuseInterpManyOps() {
		var src = '
			@strategy("np-many")
			@on(bar) {
				var a = muse.np.arange(1, 6);
				var b = muse.np.add(a, muse.np.ones([5]));
				var c = muse.np.multiply(b, muse.np.full([5], 2));
				var d = muse.np.cumsum(a);
				var g = muse.np.greater(a, muse.np.full([5], 3));
				var w = muse.np.where(g, a, muse.np.zeros([5]));
				var ok = muse.np.sum(c) == 40 && muse.np.get_flat(d, 4) == 15 && muse.np.sum(w) == 9;
				if (ok) long();
			}
		';
		var bars:Array<Bar> = [for (i in 0...3) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testJsBackendNpDispatch() {
		#if js
		var api:Dynamic = JsBackend.createApi(new HarnessContext());
		var invoke:Dynamic = Reflect.field(api, "invoke");
		var z:NdArrayF64 = cast Reflect.callMethod(null, invoke, ["np_zeros", [[2, 2]]]);
		Assert.equals(4, z.size);
		var data:Array<Float> = [1, 2, 3];
		var a:NdArrayF64 = cast Reflect.callMethod(null, invoke, ["np_asarray", [data]]);
		Assert.equals(6.0, Reflect.callMethod(null, invoke, ["np_sum", [a]]));
		var b:NdArrayF64 = cast Reflect.callMethod(null, invoke, ["np_add", [a, a]]);
		Assert.same([2.0, 4.0, 6.0], b.toArray());
		var x:Array<Float> = [1, 2, 3];
		var y:Array<Float> = [4, 5, 6];
		Assert.equals(32.0, Reflect.callMethod(null, invoke, ["np_dot", [
			Reflect.callMethod(null, invoke, ["np_asarray", [x]]),
			Reflect.callMethod(null, invoke, ["np_asarray", [y]])
		]]));
		#end
		Assert.isTrue(true);
	}

	public function testNpBuiltinsCoerceNestedAndLegacy() {
		var nested = NpBuiltins.asarray([[1, 2], [3, 4]]);
		Assert.same([2, 2], Np.shapeOf(nested));
		Assert.equals(4.0, nested.get2(1, 1));
		var legacy = {rows: 2, cols: 2, data: [1.0, 0.0, 0.0, 1.0]};
		var fromLegacy = NpBuiltins.asarray(legacy);
		Assert.equals(1.0, fromLegacy.get2(0, 0));
	}

	public function testBroadcastToConcatenate() {
		var a = Np.asarray([1, 2, 3]);
		var broad = Np.broadcastTo(Np.expandDims(a, 0), [2, 3]);
		Assert.same([2, 3], Np.shapeOf(broad));
		Assert.equals(2.0, broad.get2(1, 1));

		var c = Np.concatenate([Np.asarray([1, 2]), Np.asarray([3, 4])], 0);
		Assert.same([1.0, 2.0, 3.0, 4.0], c.toArray());
	}

	public function testHandGoldensVsNumpyNotes() {
		// Hand goldens (numpy-checked offline): (arange(6).reshape(2,3) * [[10],[20]]).sum(axis=1)
		var a = Np.reshape(Np.arange(6), [2, 3]);
		var col = Np.asarray([10, 20], [2, 1]);
		var prod = Np.multiply(a, col);
		Assert.same([0.0, 10.0, 20.0, 60.0, 80.0, 100.0], prod.toArray());
		var rowSums = Np.sumAxis(prod, 1);
		Assert.same([30.0, 240.0], rowSums.toArray());
	}

	public function testTransposeViewMutationAndCopy() {
		var a = Np.asarray([1, 2, 3, 4, 5, 6], [2, 3]);
		var t = a.transpose();
		Assert.isFalse(t.isCContiguous());
		Assert.isTrue(a.isCContiguous());
		Assert.equals(4.0, t.get2(0, 1));
		// mutate through view
		t.setAt([0, 1], 99);
		Assert.equals(99.0, a.get2(1, 0));
		var c = t.copy();
		Assert.isTrue(c.isCContiguous());
		c.setFlat(0, -1);
		Assert.equals(1.0, t.get2(0, 0)); // original view unchanged
	}

	public function testSliceViewAndUfuncOnStrides() {
		var a = Np.arange(12).reshape([3, 4]);
		var row = a.sliceAxis(0, 1, 2); // shape (1,4) view
		Assert.same([1, 4], Np.shapeOf(row));
		Assert.equals(5.0, row.get2(0, 1));
		row.setAt([0, 1], 50);
		Assert.equals(50.0, a.get2(1, 1));

		var t = a.transpose(); // non-contig
		var doubled = Np.add(t, t);
		Assert.equals(0.0, doubled.get2(0, 0));
		Assert.equals(100.0, doubled.get2(1, 1)); // 50+50 through strides
		Assert.equals(8.0, doubled.get2(0, 1)); // 4+4
	}

	public function testMultiAxisReduceKeepdims() {
		var a = Np.asarray([1, 2, 3, 4, 5, 6, 7, 8], [2, 2, 2]);
		var s = Np.sumAxes(a, [0, 2]);
		Assert.same([2], Np.shapeOf(s));
		Assert.same([14.0, 22.0], s.toArray()); // numpy multi_axis_cube golden

		var sk = Np.sumAxes(a, [1], true);
		Assert.same([2, 1, 2], Np.shapeOf(sk));
		Assert.equals(1.0 + 3.0, sk.getAt([0, 0, 0]));

		var m = Np.meanAxes(a, [0, 1, 2]);
		Assert.equals(0, m.ndim);
		Assert.isTrue(approx(m.getFlat(0), 4.5));

		var anyA = Np.anyAxes(a, [2]);
		Assert.same([2, 2], (anyA.shape : Array<Int>));
		Assert.isTrue(anyA.getAt([0, 0]));

		var std0 = Np.stdAxis(Np.asarray([1, 2, 3, 4], [2, 2]), 1, false, 0);
		Assert.isTrue(approx(std0.getFlat(0), 0.5));
	}

	public function testBoolCompressAssign() {
		var a = Np.asarray([10, 20, 30, 40]);
		var mask = Np.greater(a, Np.full([4], 25));
		var sel = Np.compress(a, mask);
		Assert.same([30.0, 40.0], sel.toArray());
		Assert.isTrue(Np.assignWhere(a, mask, Np.asarray([1, 2])));
		Assert.same([10.0, 20.0, 1.0, 2.0], a.toArray());
	}

	public function testSteppedSliceViewsAndNegatives() {
		var a = Np.arange(10);
		var even = Np.slice(a, 0, 10, 2);
		Assert.same([0.0, 2.0, 4.0, 6.0, 8.0], even.toArray());
		Assert.isFalse(even.isCContiguous()); // stride 2
		even.setFlat(1, 99); // physical a[2]
		Assert.equals(99.0, a.getFlat(2));

		var rev = Np.slice(a, -1, -11, -1); // numpy a[::-1] / a[-1:-11:-1]
		Assert.same([9.0, 8.0, 7.0, 6.0, 5.0, 4.0, 3.0, 99.0, 1.0, 0.0], rev.toArray());
		Assert.same([], Np.slice(a, 9, -1, -1).toArray()); // numpy a[9:-1:-1] empty

		Assert.same([7.0, 8.0, 9.0], Np.slice(Np.arange(10), -3, 10).toArray());
		Assert.same([], Np.slice(Np.arange(5), 3, 3).toArray());
		Assert.equals(0, Np.slice(Np.arange(5), 0, 5, 0).size); // step 0 → empty

		var m = Np.reshape(Np.arange(12), [3, 4]);
		var cols = Np.sliceAxis(m, 1, 0, 4, 2); // every other column — view
		Assert.same([3, 2], Np.shapeOf(cols));
		Assert.equals(0.0, cols.get2(0, 0));
		Assert.equals(2.0, cols.get2(0, 1));
		Assert.equals(4.0, cols.get2(1, 0)); // m[1,0]
		Assert.equals(6.0, cols.get2(1, 1)); // m[1,2]
		cols.setAt([1, 1], 50); // was m[1,2]=6
		Assert.equals(50.0, m.get2(1, 2));

		var lastTwoRows = Np.sliceAxis(m, 0, -2, 3);
		Assert.same([2, 4], Np.shapeOf(lastTwoRows));
		Assert.equals(4.0, lastTwoRows.get2(0, 0));
	}

	public function testTakeGatherTakeAlongBounds() {
		var a = Np.asarray([10, 20, 30, 40, 50]);
		Assert.same([40.0, 20.0, 50.0], Np.take(a, [3, 1, -1]).toArray());
		Assert.same([50.0, 10.0], Np.gather(a, [-1, 0]).toArray());
		Assert.equals(0, Np.take(a, [5]).size); // OOB → empty
		Assert.equals(0, Np.take(a, [-6]).size);

		var m = Np.reshape(Np.arange(12), [3, 4]);
		// take rows [2, 0]
		var rows = Np.take(m, [2, 0], 0);
		Assert.same([2, 4], Np.shapeOf(rows));
		Assert.same([8.0, 9.0, 10.0, 11.0, 0.0, 1.0, 2.0, 3.0], rows.toArray());
		// take columns [1, -1, 0]
		var cols = Np.take(m, [1, -1, 0], 1);
		Assert.same([3, 3], Np.shapeOf(cols));
		Assert.equals(1.0, cols.get2(0, 0));
		Assert.equals(3.0, cols.get2(0, 1));
		Assert.equals(0.0, cols.get2(0, 2));
		Assert.equals(5.0, cols.get2(1, 0));

		// flatten take
		Assert.same([11.0, 0.0, 5.0], Np.take(m, [11, 0, 5]).toArray());

		// ND indices along axis 0: shape (2,2) → out (2,2,4)
		var idx = Np.asarray([0, 2, 1, 1], [2, 2]);
		var g = Np.takeNd(m, idx, 0);
		Assert.same([2, 2, 4], Np.shapeOf(g));
		Assert.equals(0.0, g.getAt([0, 0, 0]));
		Assert.equals(8.0, g.getAt([0, 1, 0]));
		Assert.equals(4.0, g.getAt([1, 0, 0]));

		// take_along_axis: pick col argmax-style
		var vals = Np.asarray([1, 9, 3, 4, 0, 6], [2, 3]);
		var ai = Np.asarray([1, 2], [2, 1]); // best col per row
		var along = Np.takeAlong(vals, ai, 1);
		Assert.same([2, 1], Np.shapeOf(along));
		Assert.same([9.0, 6.0], along.toArray());

		// compress vs take: mask → compress; ints → take
		var mask = Np.asarrayBool([true, false, true, false, true]);
		Assert.same([10.0, 30.0, 50.0], Np.compress(a, mask).toArray());
		Assert.same([10.0, 30.0, 50.0], Np.take(a, [0, 2, 4]).toArray());

		// Muse builtins
		Assert.same([30.0, 10.0], NpBuiltins.take(a, [2, 0]).toArray());
		Assert.same([40.0, 20.0], NpBuiltins.gather(a, [-2, 1]).toArray());
		Assert.same([0.0, 2.0, 4.0], NpBuiltins.slice(Np.arange(6), 0, 6, 2).toArray());
	}

	public function testTakeDoesNotAliasSource() {
		var a = Np.arange(5);
		var t = Np.take(a, [1, 3]);
		t.setFlat(0, 100);
		Assert.equals(1.0, a.getFlat(1)); // copy, not view
	}

	public function testBridgesGrowableFloatSeriesBarData() {
		var g:GrowableVec<Float> = new GrowableVec<Float>(4);
		g.push(1); g.push(2); g.push(3);
		var view = NdBridge.fromGrowable(g);
		Assert.same([1.0, 2.0, 3.0], view.toArray());
		view.setFlat(1, 20);
		Assert.equals(20.0, g.at(1)); // mutation aliases

		var fs = FloatSeries.fromArray([4, 5, 6, 7]);
		var fv = NdBridge.fromFloatSeries(fs);
		Assert.same([4.0, 5.0, 6.0, 7.0], fv.toArray());
		fv.setFlat(0, 40);
		Assert.equals(40.0, fs.at(0));

		var bars:Array<Bar> = [
			{open: 1., high: 1., low: 1., close: 1., volume: 1., time: 0., index: 0, data: ["feat" => 1.5]},
			{open: 1., high: 1., low: 1., close: 1., volume: 1., time: 1., index: 1, data: ["feat" => 2.5]},
			{open: 1., high: 1., low: 1., close: 1., volume: 1., time: 2., index: 2, data: null}
		];
		var col = NdBridge.fromBarDataColumn(bars, "feat");
		Assert.same([1.5, 2.5], [col.getFlat(0), col.getFlat(1)]);
		Assert.isTrue(Math.isNaN(col.getFlat(2)));
	}

	public function testGoldenMultiAxisTranspose() {
		// numpy: arange(24).reshape(2,3,4).transpose(1,2,0).sum(axis=(0,2))
		var a = Np.reshape(Np.arange(24), [2, 3, 4]);
		var t = a.transpose([1, 2, 0]);
		Assert.same([3, 4, 2], Np.shapeOf(t));
		Assert.isFalse(t.isCContiguous());
		var s = Np.sumAxes(t, [0, 2]);
		Assert.same([4], Np.shapeOf(s));
		// values checked vs numpy offline / gen_fixtures
		Assert.same([60.0, 66.0, 72.0, 78.0], s.toArray());
	}

	public function testF32I32StorageAndFactories() {
		var zf = Np.zerosF32([2, 3]);
		Assert.equals("f32", zf.dtype());
		Assert.equals(6, zf.size);
		Assert.equals(0.0, zf.getFlat(0));

		var oi = Np.onesI32([4]);
		Assert.equals("i32", oi.dtype());
		Assert.same([1, 1, 1, 1], oi.toArray());

		var ai = Np.arangeI32(2, 8, 2);
		Assert.same([2, 4, 6], ai.toArray());

		var af = Np.asarrayF32([1.5, 2.5, 3.5], [3]);
		Assert.equals(3, af.size);
		Assert.isTrue(approx(af.getFlat(1), 2.5, 1e-6));

		// default Muse factories remain F64
		Assert.isTrue(Std.isOfType(Np.zeros([2]), NdArrayF64));
		Assert.isFalse(Std.isOfType(Np.zeros([2]), NdArrayF32));
	}

	public function testAstypeRoundTripsAllDtypes() {
		var src = Np.asarray([0, 1.7, -2.2, Math.NaN, 1e20]);

		var f32 = NdCast.toF32(AnyNdArray.F64(src));
		Assert.equals("f32", f32.dtype());
		Assert.isTrue(approx(f32.getFlat(1), 1.7, 1e-6));
		Assert.isTrue(f32.getFlat(3) != f32.getFlat(3)); // NaN

		var i32 = NdCast.toI32Arr(AnyNdArray.F64(src));
		Assert.same([0, 1, -2, 0, 2147483647], i32.toArray()); // NaN→0, huge→clamp

		var b = NdCast.toBool(AnyNdArray.F64(src));
		Assert.same([false, true, true, false, true], b.toArray());

		// F32 → F64 → I32 → Bool → F32
		var backF64 = f32.toF64();
		var roundI = NdArrayI32.fromF64(backF64);
		var roundB = roundI.toBool();
		var roundF = NdArrayF32.fromBool(roundB);
		Assert.same([0.0, 1.0, 1.0, 0.0, 1.0], roundF.toArray());

		// I32 → F32 → F64
		var fromI = Np.asarrayI32([3, -4, 5]);
		var asF = fromI.toF32();
		Assert.same([3.0, -4.0, 5.0], asF.toF64().toArray());

		// Bool → I32 / F64
		var mask = Np.asarrayBool([true, false, true]);
		Assert.same([1, 0, 1], mask.toI32().toArray());
		Assert.same([1.0, 0.0, 1.0], mask.toF64().toArray());

		// aliases + unknown
		switch (Np.astype(src, "int")) {
			case I32(_): Assert.isTrue(true);
			default: Assert.fail("int alias");
		}
		switch (Np.astype(src, "nope")) {
			case F64(_): Assert.isTrue(true);
			default: Assert.fail("unknown → f64");
		}
	}

	public function testF32I32UfuncsReductionsMatmul() {
		var a = Np.asarrayF32([1, 2, 3]);
		var b = Np.asarrayF32([10, 20, 30]);
		Assert.same([11.0, 22.0, 33.0], Np.addF32(a, b).toArray());
		Assert.same([10.0, 40.0, 90.0], Np.mulF32(a, b).toArray());
		Assert.equals(6.0, Np.sumF32(a));

		var ia = Np.asarrayI32([1, 2, 3]);
		var ib = Np.asarrayI32([4, 5, 6]);
		Assert.same([5, 7, 9], Np.addI32(ia, ib).toArray());
		Assert.same([4, 10, 18], Np.mulI32(ia, ib).toArray());
		Assert.equals(6.0, Np.sumI32(ia));
		Assert.equals(32, NdTypedOps.dotI32(ia, ib));

		// I32 true divide → F64
		var q = NdTypedOps.divI32(ia, ib);
		Assert.isTrue(q != null);
		Assert.isTrue(approx(q.getFlat(0), 0.25));

		// F32 transcendantals → F64 DetMath
		var e = NdTypedOps.expF32(Np.asarrayF32([1.0]));
		Assert.isTrue(Std.isOfType(e, NdArrayF64));
		Assert.isTrue(approx(Np.log(e).getFlat(0), 1.0, 1e-10));

		var am = Np.asarrayF32([1, 2, 3, 4], [2, 2]);
		var bm = Np.asarrayF32([5, 6, 7, 8], [2, 2]);
		var mm = Np.matmulF32(am, bm);
		Assert.equals(19.0, mm.get2(0, 0));
		Assert.equals(50.0, mm.get2(1, 1));

		var im = Np.asarrayI32([1, 2, 3, 4], [2, 2]);
		var jm = Np.asarrayI32([5, 6, 7, 8], [2, 2]);
		var imul = Np.matmulI32(im, jm);
		Assert.equals(19, imul.get2(0, 0));
		Assert.equals(50, imul.get2(1, 1));

		// Mixed promote → F64
		var mixed = Np.addAny(AnyNdArray.F32(a), AnyNdArray.I32(ia));
		switch (mixed) {
			case F64(x): Assert.same([2.0, 4.0, 6.0], x.toArray());
			default: Assert.fail("mixed → f64");
		}
	}

	public function testF32ViewsAndBroadcast() {
		var a = Np.asarrayF32([1, 2, 3, 4, 5, 6], [2, 3]);
		var t = a.transpose();
		Assert.same([3, 2], (t.shape : Array<Int>));
		Assert.isFalse(t.isCContiguous());
		Assert.equals(4.0, t.get2(0, 1));
		t.setAt([0, 1], 40);
		Assert.equals(40.0, a.get2(1, 0));

		var row = Np.asarrayF32([1, 2, 3]);
		var col = Np.asarrayF32([10, 20], [2, 1]);
		var sum = NdTypedOps.addF32(col, row);
		Assert.isTrue(sum != null);
		Assert.same([2, 3], (sum.shape : Array<Int>));
		Assert.equals(11.0, sum.get2(0, 0));
		Assert.equals(23.0, sum.get2(1, 2));
	}

	public function testMuseAstypeDtypeAndHost() {
		Assert.equals("np_dtype", MuseHost.resolveFlat("np", "dtype"));
		Assert.equals("f64", NpBuiltins.dtypeOf(Np.zeros([2])));
		var i32:Dynamic = NpBuiltins.astype(Np.asarray([1.9, -3.1]), "int32");
		Assert.isTrue(Std.isOfType(i32, NdArrayI32));
		Assert.equals("i32", NpBuiltins.dtypeOf(i32));
		Assert.equals(-2.0, NpBuiltins.sum(i32)); // trunc 1.9→1, -3.1→-3
		var addBack:Dynamic = NpBuiltins.add(i32, i32);
		Assert.isTrue(Std.isOfType(addBack, NdArrayI32));
		Assert.same([2, -6], (cast addBack : NdArrayI32).toArray());

		var f32:Dynamic = NpBuiltins.astype(Np.asarray([1, 2, 3]), "float32");
		Assert.isTrue(Std.isOfType(f32, NdArrayF32));
		Assert.equals(6.0, NpBuiltins.sum(f32));

		#if js
		var api:Dynamic = JsBackend.createApi(new HarnessContext());
		var invoke:Dynamic = Reflect.field(api, "invoke");
		var z:NdArrayF64 = cast Reflect.callMethod(null, invoke, ["np_zeros", [[2]]]);
		var casted:Dynamic = Reflect.callMethod(null, invoke, ["np_astype", [z, "float32"]]);
		Assert.isTrue(Std.isOfType(casted, NdArrayF32));
		Assert.equals("f32", Reflect.callMethod(null, invoke, ["np_dtype", [casted]]));
		#end
	}

	public function testMuseInterpAstypeExplicit() {
		var src = '
			@strategy("np-astype")
			@on(bar) {
				var a = muse.np.asarray([1.7, 2.8, 3.2]);
				var i = muse.np.astype(a, "int32");
				var s = muse.np.sum(i);
				var d = muse.np.dtype(i);
				if (s == 6 && d == "i32") long();
			}
		';
		var bars:Array<Bar> = [for (i in 0...2) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}

	public function testTakeI32IndicesNoWiden() {
		var a = Np.asarray([10.0, 20.0, 30.0, 40.0]);
		var idx = Np.asarrayI32([3, 1, 0]);
		Assert.same([40.0, 20.0, 10.0], Np.takeI32(a, idx).toArray());
		var m = Np.asarray([1.0, 2.0, 3.0, 4.0, 5.0, 6.0], [2, 3]);
		var rows = Np.asarrayI32([1, 0]);
		Assert.same([4.0, 5.0, 6.0, 1.0, 2.0, 3.0], Np.takeI32(m, rows, 0).toArray());
		// Muse builtins accept I32 indices without promoting them to F64 first.
		var viaHost:NdArrayF64 = NpBuiltins.take(a, idx);
		Assert.same([40.0, 20.0, 10.0], viaHost.toArray());
		var along = Np.takeAlongI32(
			Np.asarray([1.0, 2.0, 3.0, 4.0], [2, 2]),
			Np.asarrayI32([1, 0, 0, 1], [2, 2]),
			1
		);
		Assert.same([2.0, 1.0, 3.0, 4.0], along.toArray());
	}

	public function testF32I32PromoteAtRequireNdBoundary() {
		// Axis / where / compress stay F64 kernels; requireNd is the promote wall.
		var f32 = Np.asarrayF32([1, 2, 3, 4], [2, 2]);
		var axisSum:NdArrayF64 = cast NpBuiltins.sum(f32, 0);
		Assert.same([2], (axisSum.shape : Array<Int>));
		Assert.same([4.0, 6.0], axisSum.toArray());

		var i32 = Np.asarrayI32([1, 0, 3, 0], [2, 2]);
		var mask = Np.greater(Np.asarray([1.0, 0.0, 1.0, 0.0], [2, 2]), Np.zeros([2, 2]));
		var w:NdArrayF64 = cast NpBuiltins.where(mask, f32, i32);
		Assert.isTrue(Std.isOfType(w, NdArrayF64));
		Assert.same([1.0, 0.0, 3.0, 0.0], w.toArray());

		var comp:NdArrayF64 = cast NpBuiltins.compress(f32, mask);
		Assert.same([1.0, 3.0], comp.toArray());
	}

	public function testVolTargetQtyScalarAndClamp() {
		// qty = base * target / vol = 10 * 0.02 / 0.01 = 20
		var q:Dynamic = NpBuiltins.volTargetQty(0.01, 0.02, 10);
		Assert.equals(20.0, q);
		// upper clamp
		Assert.equals(5.0, NpBuiltins.volTargetQty(0.01, 0.02, 10, 5));
		// lower clamp when vol huge
		Assert.equals(1.0, NpBuiltins.volTargetQty(1.0, 0.01, 10, null, 1.0));
		// vector vol × scalar base
		var vols = Np.asarray([0.01, 0.02, 0.04]);
		var qs:NdArrayF64 = cast NpBuiltins.volTargetQty(vols, 0.02, 100);
		Assert.same([200.0, 100.0, 50.0], qs.toArray());
		Assert.equals("np_vol_target_qty", MuseHost.resolveFlat("np", "vol_target_qty"));
	}

	public function testVolTargetFromPricesDetMathLog() {
		// Constant geometric growth → constant log-return → zero rolling vol →
		// eps floor → large scale, then max clamp.
		var prices = Np.asarray([100.0, 101.0, 102.01, 103.0301, 104.060401]);
		var q:NdArrayF64 = cast NpBuiltins.volTargetQty(prices, 0.02, 10, 3.0, 0.0, 3);
		Assert.equals(5, q.size);
		// warmup → min (0); later bars clamped to max 3
		Assert.equals(0.0, q.getFlat(0));
		Assert.equals(0.0, q.getFlat(1));
		Assert.equals(0.0, q.getFlat(2));
		Assert.isTrue(q.getFlat(3) <= 3.0 + 1e-12);
		Assert.isTrue(q.getFlat(4) <= 3.0 + 1e-12);
		var roll = NpBuiltins.rollingLogVol(prices, 3);
		Assert.isTrue(Math.isNaN(roll.getFlat(0)));
		Assert.isTrue(Math.isNaN(roll.getFlat(2)));
		Assert.isTrue(roll.getFlat(3) == roll.getFlat(3)); // finite
	}

	public function testMaskQtyClamps() {
		var mask = Np.asarrayBool([true, false, true, false]);
		var out:NdArrayF64 = cast NpBuiltins.maskQty(mask, 7.5, 5.0, 1.0);
		Assert.same([5.0, 0.0, 5.0, 0.0], out.toArray());
		var bases = Np.asarray([2.0, 9.0, 0.5, 100.0]);
		var m2 = Np.asarrayBool([true, true, true, false]);
		var o2:NdArrayF64 = cast NpBuiltins.maskQty(m2, bases, 8.0, 1.0);
		Assert.same([2.0, 8.0, 1.0, 0.0], o2.toArray());
		Assert.equals("np_mask_qty", MuseHost.resolveFlat("np", "mask_qty"));
	}

	public function testRiskHelpersJsDispatch() {
		#if js
		var api:Dynamic = JsBackend.createApi(new HarnessContext());
		var invoke:Dynamic = Reflect.field(api, "invoke");
		var q:Dynamic = Reflect.callMethod(null, invoke, ["np_vol_target_qty", [0.05, 0.10, 4]]);
		Assert.equals(8.0, q);
		var mask = Np.asarrayBool([false, true]);
		var m:NdArrayF64 = cast Reflect.callMethod(null, invoke, ["np_mask_qty", [mask, 3]]);
		Assert.same([0.0, 3.0], m.toArray());
		#end
		Assert.isTrue(true);
	}

	public function testMuseInterpVolTargetMaskQty() {
		var src = '
			@strategy("np-risk")
			@on(bar) {
				var q = muse.np.vol_target_qty(0.02, 0.04, 5);
				var m = muse.np.mask_qty(muse.np.asarray([1, 0, 1]), 2, 10, 0);
				var s = muse.np.sum(m);
				if (q == 10 && s == 4) long(q);
			}
		';
		var bars:Array<Bar> = [for (i in 0...2) {
			open: 1., high: 1., low: 1., close: 1., volume: 1., time: (i : Float), index: i, data: null
		}];
		var r = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(bars));
		Assert.isTrue(r.trades > 0);
	}
}

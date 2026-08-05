package musescript.builtins;

import musescript.ndarray.NdArrayF64;
import musescript.ndarray.NdArrayF32;
import musescript.ndarray.NdArrayI32;
import musescript.ndarray.NdArrayBool;
import musescript.ndarray.Np;
import musescript.ndarray.AnyNdArray;
import musescript.ndarray.AnyNdArrays;
import musescript.ndarray.NdCast;
import musescript.ndarray.NdTypedOps;

/**
 * Muse install surface for `muse.np` / flat `np_*`.
 *
 * Engine eligibility: Interp N | JS B | WASM N subset + H (`WasmNpEligibility`) |
 * VM B/H (`VmNpEligibility`: scalar reduce + OBJ-lane ufuncs, len ≤ 64) else U
 * Dynamic only at this coercion boundary — typed callers use `Np` / `NdArrayF64`.
 *
 * M2: comparisons return `NdArrayBool`; `where` accepts Bool or F64 cond;
 * reductions accept scalar or list `axis` + keepdims.
 */
class NpBuiltins {
	public static function install(vars:Map<String, Dynamic>):Void {
		for (k in FLAT_NAMES.keys()) vars.set(k, FLAT_NAMES.get(k));
	}

	public static function build():Dynamic {
		var np:Dynamic = {};
		for (k in METHOD_NAMES.keys())
			Reflect.setField(np, k, METHOD_NAMES.get(k));
		return np;
	}

	/** Flat builtin name → callable (also drives MuseHost FLAT `np` map). */
	public static final FLAT_NAMES:Map<String, Dynamic> = [
		"np_zeros" => zeros, "np_ones" => ones, "np_full" => full, "np_empty" => empty,
		"np_arange" => arange, "np_linspace" => linspace, "np_eye" => eye, "np_identity" => identity,
		"np_asarray" => asarray, "np_array" => asarray,
		"np_reshape" => reshape, "np_transpose" => transpose, "np_swapaxes" => swapaxes, "np_copy" => copy,
		"np_ravel" => ravel, "np_flatten" => flatten, "np_expand_dims" => expandDims,
		"np_squeeze" => squeeze, "np_broadcast_to" => broadcastTo,
		"np_concatenate" => concatenate, "np_stack" => stack,
		"np_shape" => shapeOf, "np_ndim" => ndimOf, "np_size" => sizeOf,
		"np_is_c_contiguous" => isCContiguous,
		"np_get" => get, "np_get_flat" => getFlat, "np_slice" => slice, "np_slice_axis" => sliceAxis,
		"np_take" => take, "np_gather" => gather, "np_take_along" => takeAlong,
		"np_astype" => astype, "np_dtype" => dtypeOf, "np_bool" => asBool, "np_bool_to_f64" => boolToF64,
		"np_add" => add, "np_subtract" => subtract, "np_multiply" => multiply, "np_divide" => divide,
		"np_power" => power, "np_minimum" => minimum, "np_maximum" => maximum,
		"np_equal" => equal, "np_not_equal" => notEqual,
		"np_greater" => greater, "np_greater_equal" => greaterEqual,
		"np_less" => less, "np_less_equal" => lessEqual,
		"np_negative" => negative, "np_abs" => abs, "np_sqrt" => sqrt,
		"np_exp" => exp, "np_log" => log, "np_square" => square, "np_sign" => sign,
		"np_clip" => clip, "np_where" => where, "np_compress" => compress, "np_assign_where" => assignWhere,
		"np_sum" => sum, "np_mean" => mean, "np_min" => min, "np_max" => max, "np_prod" => prod,
		"np_std" => std, "np_var" => variance, "np_any" => any, "np_all" => all,
		"np_cumsum" => cumsum, "np_diff" => diff,
		"np_matmul" => matmul, "np_dot" => dot, "np_outer" => outer,
		"np_to_vector" => toVector,
		"np_vol_target_qty" => volTargetQty, "np_mask_qty" => maskQty,
		"np_rolling_log_vol" => rollingLogVol
	];

	static final METHOD_NAMES:Map<String, Dynamic> = [
		"zeros" => zeros, "ones" => ones, "full" => full, "empty" => empty,
		"arange" => arange, "linspace" => linspace, "eye" => eye, "identity" => identity,
		"asarray" => asarray, "array" => asarray,
		"reshape" => reshape, "transpose" => transpose, "swapaxes" => swapaxes, "copy" => copy,
		"ravel" => ravel, "flatten" => flatten, "expand_dims" => expandDims,
		"squeeze" => squeeze, "broadcast_to" => broadcastTo,
		"concatenate" => concatenate, "stack" => stack,
		"shape" => shapeOf, "ndim" => ndimOf, "size" => sizeOf,
		"is_c_contiguous" => isCContiguous,
		"get" => get, "get_flat" => getFlat, "slice" => slice, "slice_axis" => sliceAxis,
		"take" => take, "gather" => gather, "take_along" => takeAlong,
		"astype" => astype, "dtype" => dtypeOf, "bool" => asBool, "bool_to_f64" => boolToF64,
		"add" => add, "subtract" => subtract, "multiply" => multiply, "divide" => divide,
		"power" => power, "minimum" => minimum, "maximum" => maximum,
		"equal" => equal, "not_equal" => notEqual,
		"greater" => greater, "greater_equal" => greaterEqual,
		"less" => less, "less_equal" => lessEqual,
		"negative" => negative, "abs" => abs, "sqrt" => sqrt,
		"exp" => exp, "log" => log, "square" => square, "sign" => sign,
		"clip" => clip, "where" => where, "compress" => compress, "assign_where" => assignWhere,
		"sum" => sum, "mean" => mean, "min" => min, "max" => max, "prod" => prod,
		"std" => std, "var" => variance, "any" => any, "all" => all,
		"cumsum" => cumsum, "diff" => diff,
		"matmul" => matmul, "dot" => dot, "outer" => outer,
		"to_vector" => toVector,
		"vol_target_qty" => volTargetQty, "mask_qty" => maskQty,
		"rolling_log_vol" => rollingLogVol
	];

	public static function zeros(shape:Dynamic):NdArrayF64 return Np.zeros(toShape(shape));
	public static function ones(shape:Dynamic):NdArrayF64 return Np.ones(toShape(shape));
	public static function full(shape:Dynamic, value:Float):NdArrayF64 return Np.full(toShape(shape), value);
	public static function empty(shape:Dynamic):NdArrayF64 return Np.empty(toShape(shape));
	public static function arange(a:Float, ?b:Float, ?c:Float):NdArrayF64 return Np.arange(a, b, c);
	public static function linspace(start:Float, stop:Float, ?num:Float = 50, ?endpoint:Bool = true):NdArrayF64
		return Np.linspace(start, stop, Std.int(num), endpoint);
	public static function eye(n:Float, ?m:Float):NdArrayF64
		return Np.eye(Std.int(n), m == null ? null : Std.int(m));
	public static function identity(n:Float):NdArrayF64 return Np.identity(Std.int(n));

	public static function asarray(value:Dynamic, ?shape:Dynamic):NdArrayF64 {
		var existing = asNd(value);
		if (existing != null) {
			if (shape == null) return existing.copy();
			return Np.reshape(existing, toShape(shape));
		}
		var f32 = asF32Nd(value);
		if (f32 != null) {
			var w = f32.toF64();
			if (shape == null) return w;
			return Np.reshape(w, toShape(shape));
		}
		var i32 = asI32Nd(value);
		if (i32 != null) {
			var w = i32.toF64();
			if (shape == null) return w;
			return Np.reshape(w, toShape(shape));
		}
		var asBoolArr = asBoolNd(value);
		if (asBoolArr != null) return asBoolArr.toF64();
		if (isLegacyMatrix(value)) {
			var rows = Std.int(Reflect.field(value, "rows"));
			var cols = Std.int(Reflect.field(value, "cols"));
			var data:Array<Float> = cast Reflect.field(value, "data");
			return Np.asarray(data.copy(), [rows, cols]);
		}
		if (Std.isOfType(value, Array)) {
			var arr:Array<Dynamic> = cast value;
			if (arr.length > 0 && Std.isOfType(arr[0], Array)) {
				var rows:Array<Array<Float>> = [];
				for (r in arr) {
					if (!Std.isOfType(r, Array)) return NdArrayF64.empty([0, 0]);
					var row:Array<Float> = [];
					var cells:Array<Dynamic> = cast r;
					for (c in cells) row.push(toFloat(c));
					rows.push(row);
				}
				return Np.asarray2d(rows);
			}
			var flat:Array<Float> = [for (x in arr) toFloat(x)];
			if (shape != null) return Np.asarray(flat, toShape(shape));
			return Np.asarray(flat);
		}
		if (value != null && !Reflect.isObject(value)) {
			var a = NdArrayF64.empty([]);
			a.setFlat(0, toFloat(value));
			return a;
		}
		return NdArrayF64.empty([0]);
	}

	public static function reshape(a:Dynamic, shape:Dynamic):NdArrayF64 return Np.reshape(requireNd(a), toShape(shape));
	public static function transpose(a:Dynamic, ?axes:Dynamic):NdArrayF64 {
		var nd = requireNd(a);
		if (axes == null) return Np.transpose(nd);
		return Np.transpose(nd, toShape(axes));
	}
	public static function swapaxes(a:Dynamic, i:Float, j:Float):NdArrayF64
		return Np.swapaxes(requireNd(a), Std.int(i), Std.int(j));
	public static function copy(a:Dynamic):NdArrayF64 return Np.copy(requireNd(a));
	public static function ravel(a:Dynamic):NdArrayF64 return Np.ravel(requireNd(a));
	public static function flatten(a:Dynamic):NdArrayF64 return Np.flatten(requireNd(a));
	public static function expandDims(a:Dynamic, axis:Float):NdArrayF64 return Np.expandDims(requireNd(a), Std.int(axis));
	public static function squeeze(a:Dynamic, ?axis:Float):NdArrayF64
		return Np.squeeze(requireNd(a), axis == null ? null : Std.int(axis));
	public static function broadcastTo(a:Dynamic, shape:Dynamic):NdArrayF64
		return Np.broadcastTo(requireNd(a), toShape(shape));
	public static function concatenate(arrays:Dynamic, ?axis:Float = 0):NdArrayF64
		return Np.concatenate(toNdList(arrays), Std.int(axis));
	public static function stack(arrays:Dynamic, ?axis:Float = 0):NdArrayF64
		return Np.stack(toNdList(arrays), Std.int(axis));

	public static function shapeOf(a:Dynamic):Array<Int> {
		var any = asAny(a);
		if (any != null) {
			return switch (any) {
				case F64(x): (x.shape : Array<Int>).copy();
				case F32(x): (x.shape : Array<Int>).copy();
				case I32(x): (x.shape : Array<Int>).copy();
				case Bool(x): (x.shape : Array<Int>).copy();
			};
		}
		return Np.shapeOf(requireNd(a));
	}
	public static function ndimOf(a:Dynamic):Int {
		var any = asAny(a);
		if (any != null) {
			return switch (any) {
				case F64(x): x.ndim;
				case F32(x): x.ndim;
				case I32(x): x.ndim;
				case Bool(x): x.ndim;
			};
		}
		return Np.ndimOf(requireNd(a));
	}
	public static function sizeOf(a:Dynamic):Int {
		var any = asAny(a);
		if (any != null) {
			return switch (any) {
				case F64(x): x.size;
				case F32(x): x.size;
				case I32(x): x.size;
				case Bool(x): x.size;
			};
		}
		return Np.sizeOf(requireNd(a));
	}
	public static function isCContiguous(a:Dynamic):Bool return Np.isCContiguous(requireNd(a));
	public static function get(a:Dynamic, indices:Dynamic):Float return Np.get(requireNd(a), toShape(indices));
	public static function getFlat(a:Dynamic, i:Float):Float return Np.getFlat(requireNd(a), Std.int(i));
	public static function slice(a:Dynamic, start:Float, stop:Float, ?step:Float):NdArrayF64 {
		var st = step == null ? 1 : Std.int(step);
		return Np.slice(requireNd(a), Std.int(start), Std.int(stop), st);
	}
	public static function sliceAxis(a:Dynamic, axis:Float, start:Float, stop:Float, ?step:Float):NdArrayF64 {
		var st = step == null ? 1 : Std.int(step);
		return Np.sliceAxis(requireNd(a), Std.int(axis), Std.int(start), Std.int(stop), st);
	}
	/** Integer gather. `indices` = Array, F64 NdArray, or I32 NdArray; optional `axis`. */
	public static function take(a:Dynamic, indices:Dynamic, ?axis:Dynamic):NdArrayF64 {
		var nd = requireNd(a);
		var ax:Null<Int> = axis == null ? null : Std.int(toFloat(axis));
		var asI32 = asI32Nd(indices);
		if (asI32 != null) return Np.takeI32(nd, asI32, ax);
		var asNd = asNd(indices);
		if (asNd != null) return Np.takeNd(nd, asNd, ax);
		return Np.take(nd, toShape(indices), ax);
	}
	public static function gather(a:Dynamic, indices:Dynamic):NdArrayF64 {
		var nd = requireNd(a);
		var asI32 = asI32Nd(indices);
		if (asI32 != null) return Np.gatherI32(nd, asI32);
		var asNd = asNd(indices);
		if (asNd != null) return Np.gatherNd(nd, asNd);
		return Np.gather(nd, toShape(indices));
	}
	public static function takeAlong(a:Dynamic, indices:Dynamic, axis:Float):NdArrayF64 {
		var nd = requireNd(a);
		var asI32 = asI32Nd(indices);
		if (asI32 != null) return Np.takeAlongI32(nd, asI32, Std.int(axis));
		return Np.takeAlong(nd, requireNd(indices), Std.int(axis));
	}
	public static function astype(a:Dynamic, dtype:String):Dynamic
		return AnyNdArrays.unwrap(Np.astypeAny(boxAny(a), dtype));
	public static function dtypeOf(a:Dynamic):String {
		var any = asAny(a);
		return any == null ? "f64" : NdCast.dtypeOf(any);
	}
	public static function asBool(a:Dynamic):NdArrayBool {
		var b = asBoolNd(a);
		if (b != null) return b.copy();
		return Np.boolFromF64(requireNd(a));
	}
	public static function boolToF64(a:Dynamic):NdArrayF64 {
		var b = asBoolNd(a);
		if (b != null) return b.toF64();
		return requireNd(a).copy();
	}

	public static function add(a:Dynamic, b:Dynamic):Dynamic
		return AnyNdArrays.unwrap(Np.addAny(boxAny(a), boxAny(b)));
	public static function subtract(a:Dynamic, b:Dynamic):Dynamic {
		var r = NdTypedOps.subAny(boxAny(a), boxAny(b));
		return AnyNdArrays.unwrap(r != null ? r : AnyNdArray.F64(NdArrayF64.empty([0])));
	}
	public static function multiply(a:Dynamic, b:Dynamic):Dynamic
		return AnyNdArrays.unwrap(Np.mulAny(boxAny(a), boxAny(b)));
	public static function divide(a:Dynamic, b:Dynamic):Dynamic {
		var r = NdTypedOps.divAny(boxAny(a), boxAny(b));
		return AnyNdArrays.unwrap(r != null ? r : AnyNdArray.F64(NdArrayF64.empty([0])));
	}
	public static function power(a:Dynamic, b:Dynamic):NdArrayF64 return Np.power(requireNd(a), requireNd(b));
	public static function minimum(a:Dynamic, b:Dynamic):NdArrayF64 return Np.minimum(requireNd(a), requireNd(b));
	public static function maximum(a:Dynamic, b:Dynamic):NdArrayF64 return Np.maximum(requireNd(a), requireNd(b));
	public static function equal(a:Dynamic, b:Dynamic):NdArrayBool return Np.equal(requireNd(a), requireNd(b));
	public static function notEqual(a:Dynamic, b:Dynamic):NdArrayBool return Np.notEqual(requireNd(a), requireNd(b));
	public static function greater(a:Dynamic, b:Dynamic):NdArrayBool return Np.greater(requireNd(a), requireNd(b));
	public static function greaterEqual(a:Dynamic, b:Dynamic):NdArrayBool return Np.greaterEqual(requireNd(a), requireNd(b));
	public static function less(a:Dynamic, b:Dynamic):NdArrayBool return Np.less(requireNd(a), requireNd(b));
	public static function lessEqual(a:Dynamic, b:Dynamic):NdArrayBool return Np.lessEqual(requireNd(a), requireNd(b));
	public static function negative(a:Dynamic):NdArrayF64 return Np.negative(requireNd(a));
	public static function abs(a:Dynamic):NdArrayF64 return Np.abs(requireNd(a));
	public static function sqrt(a:Dynamic):NdArrayF64 return Np.sqrt(requireNd(a));
	public static function exp(a:Dynamic):NdArrayF64 return Np.exp(requireNd(a));
	public static function log(a:Dynamic):NdArrayF64 return Np.log(requireNd(a));
	public static function square(a:Dynamic):NdArrayF64 return Np.square(requireNd(a));
	public static function sign(a:Dynamic):NdArrayF64 return Np.sign(requireNd(a));
	public static function clip(a:Dynamic, lo:Float, hi:Float):NdArrayF64 return Np.clip(requireNd(a), lo, hi);
	public static function where(cond:Dynamic, x:Dynamic, y:Dynamic):NdArrayF64 {
		var b = asBoolNd(cond);
		if (b != null) return Np.whereBool(b, requireNd(x), requireNd(y));
		return Np.where(requireNd(cond), requireNd(x), requireNd(y));
	}
	public static function compress(a:Dynamic, mask:Dynamic):NdArrayF64
		return Np.compress(requireNd(a), requireBool(mask));
	public static function assignWhere(a:Dynamic, mask:Dynamic, values:Dynamic):Bool
		return Np.assignWhere(requireNd(a), requireBool(mask), requireNd(values));

	/** `sum(a)` or `sum(a, axis, keepdims)` — axis may be Int or Array<Int>. */
	public static function sum(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false):Dynamic {
		if (axis == null) {
			var any = asAny(a);
			if (any != null) return NdTypedOps.sumAny(any);
		}
		var nd = requireNd(a);
		if (axis == null) return Np.sum(nd);
		if (Std.isOfType(axis, Array))
			return maybeScalarNd(Np.sumAxes(nd, toShape(axis), keepdims == true), keepdims == true);
		return maybeScalarNd(Np.sumAxis(nd, Std.int(toFloat(axis)), keepdims == true), keepdims == true);
	}
	public static function mean(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.mean(nd);
		if (Std.isOfType(axis, Array))
			return maybeScalarNd(Np.meanAxes(nd, toShape(axis), keepdims == true), keepdims == true);
		return maybeScalarNd(Np.meanAxis(nd, Std.int(toFloat(axis)), keepdims == true), keepdims == true);
	}
	public static function min(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.min(nd);
		if (Std.isOfType(axis, Array))
			return maybeScalarNd(Np.minAxes(nd, toShape(axis), keepdims == true), keepdims == true);
		return maybeScalarNd(Np.minAxis(nd, Std.int(toFloat(axis)), keepdims == true), keepdims == true);
	}
	public static function max(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.max(nd);
		if (Std.isOfType(axis, Array))
			return maybeScalarNd(Np.maxAxes(nd, toShape(axis), keepdims == true), keepdims == true);
		return maybeScalarNd(Np.maxAxis(nd, Std.int(toFloat(axis)), keepdims == true), keepdims == true);
	}
	public static function prod(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.prod(nd);
		if (Std.isOfType(axis, Array))
			return maybeScalarNd(Np.prodAxes(nd, toShape(axis), keepdims == true), keepdims == true);
		return maybeScalarNd(Np.prodAxis(nd, Std.int(toFloat(axis)), keepdims == true), keepdims == true);
	}
	public static function std(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false, ?ddof:Float = 0):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.std(nd, Std.int(ddof));
		if (Std.isOfType(axis, Array))
			return maybeScalarNd(Np.stdAxes(nd, toShape(axis), keepdims == true, Std.int(ddof)), keepdims == true);
		return maybeScalarNd(Np.stdAxis(nd, Std.int(toFloat(axis)), keepdims == true, Std.int(ddof)), keepdims == true);
	}
	public static function variance(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false, ?ddof:Float = 0):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.variance(nd, Std.int(ddof));
		if (Std.isOfType(axis, Array))
			return maybeScalarNd(Np.varAxes(nd, toShape(axis), keepdims == true, Std.int(ddof)), keepdims == true);
		return maybeScalarNd(Np.varAxis(nd, Std.int(toFloat(axis)), keepdims == true, Std.int(ddof)), keepdims == true);
	}
	public static function any(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.any(nd);
		if (Std.isOfType(axis, Array))
			return maybeScalarBool(Np.anyAxes(nd, toShape(axis), keepdims == true), keepdims == true);
		return maybeScalarBool(Np.anyAxis(nd, Std.int(toFloat(axis)), keepdims == true), keepdims == true);
	}
	public static function all(a:Dynamic, ?axis:Dynamic, ?keepdims:Bool = false):Dynamic {
		var nd = requireNd(a);
		if (axis == null) return Np.all(nd);
		if (Std.isOfType(axis, Array))
			return maybeScalarBool(Np.allAxes(nd, toShape(axis), keepdims == true), keepdims == true);
		return maybeScalarBool(Np.allAxis(nd, Std.int(toFloat(axis)), keepdims == true), keepdims == true);
	}

	/**
	 * Muse/NumPy-feel: full collapse (0-d, `keepdims=false`) → host Float
	 * so `muse.np.sum(xs, 0)` on 1-D compares like a number (matches WASM vec_sum).
	 */
	static function maybeScalarNd(r:Null<NdArrayF64>, keepdims:Bool):Dynamic {
		if (r == null) return NdArrayF64.empty([0]);
		if (!keepdims && r.ndim == 0) return r.getFlat(0);
		return r;
	}

	static function maybeScalarBool(r:Null<NdArrayBool>, keepdims:Bool):Dynamic {
		if (r == null) return NdArrayBool.empty([0]);
		if (!keepdims && r.ndim == 0) return r.getFlat(0);
		return r;
	}
	public static function cumsum(a:Dynamic, ?axis:Float = -1):NdArrayF64
		return Np.cumsum(requireNd(a), Std.int(axis));
	public static function diff(a:Dynamic):NdArrayF64 return Np.diff(requireNd(a));

	public static function matmul(a:Dynamic, b:Dynamic):Dynamic {
		var r = NdTypedOps.matmulAny(boxAny(a), boxAny(b));
		return AnyNdArrays.unwrap(r != null ? r : AnyNdArray.F64(NdArrayF64.empty([0])));
	}
	public static function dot(a:Dynamic, b:Dynamic):Float return Np.dot(requireNd(a), requireNd(b));
	public static function outer(a:Dynamic, b:Dynamic):NdArrayF64 return Np.outer(requireNd(a), requireNd(b));
	public static function toVector(a:Dynamic):Array<Float> {
		var nd = requireNd(a);
		return nd == null ? [] : nd.toArray();
	}

	/**
	 * Vol-target sizing: `qty = clip(base * target / max(|vol|, eps), min, max)`.
	 *
	 * Args: `(vol_or_prices, target_vol, base_qty [, max_qty [, min_qty [, window [, eps]]]])`.
	 * When `window` > 0, first arg is prices → rolling DetMath log-return std, then scale.
	 * Scalar × scalar collapses to Float (Muse feel); else f64 NdArray.
	 *
	 * Returns **requested** qty only — `OrderSim.riskCappedQty` / cash still clamp at fill
	 * (e.g. evolved `size = volume` remains sim-capped at 25% cash).
	 */
	public static function volTargetQty(
		volOrPrices:Dynamic,
		targetVol:Float,
		baseQty:Dynamic,
		?maxQty:Float,
		?minQty:Float,
		?window:Float,
		?eps:Float
	):Dynamic {
		var base = asScalarOrNd(baseQty);
		var win = window == null || !(window == window) ? 0 : Std.int(window);
		var out:NdArrayF64;
		if (win > 0) {
			out = Np.volTargetQtyFromPrices(requireNd(volOrPrices), targetVol, base, win, maxQty, minQty, eps);
		} else {
			out = Np.volTargetQty(requireNd(volOrPrices), targetVol, base, maxQty, minQty, eps);
		}
		return maybeScalarQty(out);
	}

	/** Rolling DetMath log-return std (1-D prices). WASM → host_eval. */
	public static function rollingLogVol(prices:Dynamic, window:Float, ?ddof:Float = 0):NdArrayF64
		return Np.rollingLogVol(requireNd(prices), Std.int(window), Std.int(ddof));

	/**
	 * Bool/mask × base qty with clamps: true → clip(base), false → 0.
	 * `(mask, base_qty [, max_qty [, min_qty]])`.
	 */
	public static function maskQty(
		mask:Dynamic,
		baseQty:Dynamic,
		?maxQty:Float,
		?minQty:Float
	):Dynamic {
		var out = Np.maskQty(requireBool(mask), asScalarOrNd(baseQty), maxQty, minQty);
		return maybeScalarQty(out);
	}

	/** Promote scalar Float/Int to 0-d NdArray so broadcast works. */
	static function asScalarOrNd(value:Dynamic):NdArrayF64 {
		if (value == null) return NdArrayF64.empty([]);
		var nd = asNd(value);
		if (nd != null) return nd;
		var f32 = asF32Nd(value);
		if (f32 != null) return f32.toF64();
		var i32 = asI32Nd(value);
		if (i32 != null) return i32.toF64();
		var b = asBoolNd(value);
		if (b != null) return b.toF64();
		if (Std.isOfType(value, Array)) return asarray(value);
		var a = NdArrayF64.empty([]);
		a.setFlat(0, toFloat(value));
		return a;
	}

	static function maybeScalarQty(r:NdArrayF64):Dynamic {
		if (r == null) return NdArrayF64.empty([0]);
		if (r.ndim == 0) return r.getFlat(0);
		return r;
	}

	public static function asNd(value:Dynamic):Null<NdArrayF64> {
		if (value == null) return null;
		if (Std.isOfType(value, NdArrayF64)) return cast value;
		return null;
	}

	public static function asF32Nd(value:Dynamic):Null<NdArrayF32> {
		if (value == null) return null;
		if (Std.isOfType(value, NdArrayF32)) return cast value;
		return null;
	}

	public static function asI32Nd(value:Dynamic):Null<NdArrayI32> {
		if (value == null) return null;
		if (Std.isOfType(value, NdArrayI32)) return cast value;
		return null;
	}

	public static function asBoolNd(value:Dynamic):Null<NdArrayBool> {
		if (value == null) return null;
		if (Std.isOfType(value, NdArrayBool)) return cast value;
		return null;
	}

	public static function asAny(value:Dynamic):Null<AnyNdArray> {
		if (value == null) return null;
		var f64 = asNd(value);
		if (f64 != null) return AnyNdArray.F64(f64);
		var f32 = asF32Nd(value);
		if (f32 != null) return AnyNdArray.F32(f32);
		var i32 = asI32Nd(value);
		if (i32 != null) return AnyNdArray.I32(i32);
		var b = asBoolNd(value);
		if (b != null) return AnyNdArray.Bool(b);
		return null;
	}

	public static function boxAny(value:Dynamic):AnyNdArray {
		var any = asAny(value);
		if (any != null) return any;
		return AnyNdArray.F64(asarray(value));
	}

	/** Promote to F64 for F64-only kernels (axis reductions, where, etc.). */
	public static function requireNd(value:Dynamic):NdArrayF64 {
		var a = asNd(value);
		if (a != null) return a;
		var f32 = asF32Nd(value);
		if (f32 != null) return f32.toF64();
		var i32 = asI32Nd(value);
		if (i32 != null) return i32.toF64();
		var b = asBoolNd(value);
		if (b != null) return b.toF64();
		return asarray(value);
	}

	public static function requireBool(value:Dynamic):NdArrayBool {
		var b = asBoolNd(value);
		if (b != null) return b;
		return NdArrayBool.fromF64(requireNd(value));
	}

	public static function box(a:NdArrayF64):AnyNdArray return AnyNdArrays.ofF64(a);
	public static function boxF32(a:NdArrayF32):AnyNdArray return AnyNdArrays.ofF32(a);
	public static function boxI32(a:NdArrayI32):AnyNdArray return AnyNdArrays.ofI32(a);
	public static function boxBool(a:NdArrayBool):AnyNdArray return AnyNdArrays.ofBool(a);

	static function toNdList(arrays:Dynamic):Array<NdArrayF64> {
		if (arrays == null) return [];
		if (Std.isOfType(arrays, Array)) {
			var arr:Array<Dynamic> = cast arrays;
			return [for (x in arr) requireNd(x)];
		}
		return [requireNd(arrays)];
	}

	static function toShape(shape:Dynamic):Array<Int> {
		if (shape == null) return [];
		if (Std.isOfType(shape, Array)) {
			var arr:Array<Dynamic> = cast shape;
			return [for (x in arr) Std.int(toFloat(x))];
		}
		return [Std.int(toFloat(shape))];
	}

	static function toFloat(v:Dynamic):Float {
		if (v == null) return Math.NaN;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return cast v;
		return Std.parseFloat(Std.string(v));
	}

	static function isLegacyMatrix(value:Dynamic):Bool {
		if (value == null || Std.isOfType(value, Array) || !Reflect.isObject(value)) return false;
		return Reflect.hasField(value, "rows")
			&& Reflect.hasField(value, "cols")
			&& Reflect.hasField(value, "data");
	}
}

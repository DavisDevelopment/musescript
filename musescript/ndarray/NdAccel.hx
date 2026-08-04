package musescript.ndarray;

/**
 * Accel / backend hooks for NdArray kernels.
 *
 * Doctrine (frozen for M0+):
 *   - **Default forever** = pure Haxe f64 loops (`PureNdKernelF64`).
 *   - DetMath for transcendentals when those ufuncs land (fitness parity).
 *   - **No** numjs / math.js runtime deps.
 *   - Optional Python NumPy / npyjs are **later** — leave `#if` stubs only; do
 *     not add npm/pip hard deps here.
 *   - JVM: kernels stay Haxe/Java — do **not** rewrite `muse.np` in MuseScript.
 *   - Target invest order: JS + JVM + WASM honesty; JS tests gate first.
 *
 * Optional accel flags (compile-time, opt-in, never silent on fitness):
 *   - `#if muse_np_blas` — JVM BLAS JNI/Panama behind parity gate (M4+)
 *   - `#if muse_np_python` — Python host fixture / experimental consume (later)
 *   - `#if muse_np_npyjs` — browser npyjs bridge (later)
 */
interface INdKernelF64 {
	function fill(buf:NdArrayF64, value:Float):Void;
	function add(a:NdArrayF64, b:NdArrayF64, out:NdArrayF64):Bool;
	function mul(a:NdArrayF64, b:NdArrayF64, out:NdArrayF64):Bool;
}

/** Default / forever kernel: pure Haxe indexed loops, no Dynamic. */
class PureNdKernelF64 implements INdKernelF64 {
	public function new() {}

	public function fill(buf:NdArrayF64, value:Float):Void {
		var n = buf.size;
		for (i in 0...n) buf.setFlat(i, value);
	}

	public function add(a:NdArrayF64, b:NdArrayF64, out:NdArrayF64):Bool {
		return NdUfuncs.binopInto(a, b, out, (x, y) -> x + y);
	}

	public function mul(a:NdArrayF64, b:NdArrayF64, out:NdArrayF64):Bool {
		return NdUfuncs.binopInto(a, b, out, (x, y) -> x * y);
	}
}

class NdAccel {
	static var kernel:INdKernelF64 = resolveKernel();

	public static function active():INdKernelF64 return kernel;

	/** Test/injection only — production fitness paths must keep PureNdKernelF64. */
	public static function setKernel(k:INdKernelF64):Void {
		kernel = k != null ? k : new PureNdKernelF64();
	}

	static function resolveKernel():INdKernelF64 {
		#if muse_np_blas
		// JVM BLAS backend placeholder — wire when parity harness exists (M4).
		// return new BlasNdKernelF64();
		#end
		#if muse_np_python
		// Optional Python NumPy host bridge — not linked in M0.
		#end
		#if muse_np_npyjs
		// Optional npyjs bridge — not linked in M0.
		#end
		return new PureNdKernelF64();
	}
}

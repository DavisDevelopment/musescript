package musescript.evo.nma;

import musescript.indicators.GrowableVec;

/**
 * P4 WASM fused-logic emitter — columnar AND/OR over two f64 columns in linear memory.
 *
 * Spec §5.3 “WASM-fused” path: WAT the Graal/wasmtime host can instantiate. Haxe reference
 * `fuseColumnsHaxe` stays bit-exact with `NmaEval.logic2`. StrategyWasmEmitter embeds both
 * helpers into every on-bar module so genome-level WASM and NMA share one fuse ABI.
 *
 * Memory layout (bytes): aBase/bBase/outBase = f64 columns of length n (bool as 0.0/1.0).
 *
 * «δύο χορδαί· εἷς ἦχος· ὕδωρ πυρί μιγέν.»
 */
class NmaWasmFusedEmitter {

	public static inline var EXPORT_AND = "fuse_and_cols";
	public static inline var EXPORT_OR = "fuse_or_cols";

	/** Full WAT module with both AND and OR exports. */
	public static function emitModule():String {
		var buf = new StringBuf();
		buf.add("(module\n");
		// 16 pages ≈ 1MiB — enough for 3×f64 columns × ~40k bars.
		buf.add("  (memory (export \"memory\") 16)\n");
		buf.add(emitFunc(true));
		buf.add(emitFunc(false));
		// Separate export decls — WatAssembler does not parse inline `(func (export ...) ...)`.
		buf.add('  (export "$EXPORT_AND" (func $$$EXPORT_AND))\n');
		buf.add('  (export "$EXPORT_OR" (func $$$EXPORT_OR))\n');
		buf.add(")\n");
		return buf.toString();
	}

	/** Helpers block for embedding inside StrategyWasmEmitter's larger `(module ...)`. */
	public static function emitHelpersForStrategyModule():String {
		return emitFunc(true) + emitFunc(false);
	}

	/** Single named function WAT (`$fuse_and_cols` / `$fuse_or_cols`). */
	public static function emitFunc(andOp:Bool):String {
		var name = andOp ? EXPORT_AND : EXPORT_OR;
		var op = andOp ? "i32.and" : "i32.or";
		return
			'  (func $$$name (param $$aBase i32) (param $$bBase i32) (param $$outBase i32) (param $$n i32)\n' +
			'    (local $$i i32) (local $$off i32) (local $$av f64) (local $$bv f64) (local $$ai i32) (local $$bi i32)\n' +
			'    (local.set $$i (i32.const 0))\n' +
			'    (block $$done\n' +
			'      (loop $$loop\n' +
			'        (br_if $$done (i32.ge_u (local.get $$i) (local.get $$n)))\n' +
			'        (local.set $$off (i32.shl (local.get $$i) (i32.const 3)))\n' +
			'        (local.set $$av (f64.load (i32.add (local.get $$aBase) (local.get $$off))))\n' +
			'        (local.set $$bv (f64.load (i32.add (local.get $$bBase) (local.get $$off))))\n' +
			'        (local.set $$ai (f64.ge (local.get $$av) (f64.const 0.5)))\n' +
			'        (local.set $$bi (f64.ge (local.get $$bv) (f64.const 0.5)))\n' +
			'        (f64.store (i32.add (local.get $$outBase) (local.get $$off))\n' +
			'          (select (f64.const 1) (f64.const 0) ($op (local.get $$ai) (local.get $$bi))))\n' +
			'        (local.set $$i (i32.add (local.get $$i) (i32.const 1)))\n' +
			'        (br $$loop)))\n' +
			'  )\n';
	}

	/** Haxe reference — bit-exact with `NmaEval.logic2Public`. */
	public static function fuseColumnsHaxe(a:GrowableVec<Float>, b:GrowableVec<Float>, andOp:Bool, n:Int):GrowableVec<Float> {
		return NmaEval.logic2Public(a, b, andOp, n);
	}

	/** Attach emitted WAT snippet to a BAnd/BOr node (no megamorphic kernel install). */
	public static function attachWat(node:NmaNode):Void {
		switch (node.kind) {
			case BAnd: node.kernelWat = emitFunc(true);
			case BOr: node.kernelWat = emitFunc(false);
			default:
		}
	}

	#if js
	/** @deprecated Prefer `NmaFuseHost.fuse` (cached instance). Kept for direct tests. */
	public static function fuseColumnsWasm(a:GrowableVec<Float>, b:GrowableVec<Float>, andOp:Bool, n:Int):GrowableVec<Float> {
		NmaFuseHost.reset();
		NmaFuseHost.enabled = true;
		var out = NmaFuseHost.fuse(a, b, andOp, n);
		if (out == null) throw "NmaFuseHost.fuse failed on JS";
		return out;
	}
	#end
}

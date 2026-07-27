package musescript.evo.nma;

import musescript.indicators.GrowableVec;
import haxe.io.Bytes;

/**
 * Process-wide host for `fuse_and_cols` / `fuse_or_cols` — makes P4 `kernelWat` *run*, not
 * attach-only. JS: cached `WebAssembly.Instance`. JVM: GraalWasm from assembled bytes.
 * On init failure, disables and callers fall back to Haxe `logic2`.
 *
 * «χαλκὸς ἐν πυρί· σίδηρος ἐν ὕδατι.»
 */
class NmaFuseHost {
	/** When true, warm BAnd/BOr path may use WASM fuse over Haxe logic2. Off by default. */
	public static var enabled:Bool = false;
	public static var fuseCalls:Int = 0;
	public static var fuseFallbacks:Int = 0;
	public static var fuseSkips:Int = 0;
	/** Host-boundary copies dominate ordinary columns; CorpusEvoRun defaults this to 8192. */
	public static var minLength:Int = 0;

	static var inited:Bool = false;
	static var readyFlag:Bool = false;

	#if js
	static var jsFnAnd:Dynamic = null;
	static var jsFnOr:Dynamic = null;
	static var jsView:js.lib.Float64Array = null;
	static var jsMemPages:Int = 0;
	#end

	#if (java || jvm)
	static var jvmHost:musescript.evo.graal.GraalWasmHost = null;
	static var jvmExports:musescript.evo.graal.Polyglot.Value = null;
	static var jvmFnAnd:musescript.evo.graal.Polyglot.Value = null;
	static var jvmFnOr:musescript.evo.graal.Polyglot.Value = null;
	static var jvmMem:musescript.evo.graal.Polyglot.Value = null;
	#end

	public static function ready():Bool {
		if (!enabled) return false;
		if (!inited) init();
		return readyFlag;
	}

	public static function reset():Void {
		inited = false;
		readyFlag = false;
		fuseCalls = 0;
		fuseFallbacks = 0;
		fuseSkips = 0;
		#if js
		jsFnAnd = null; jsFnOr = null; jsView = null; jsMemPages = 0;
		#end
		#if (java || jvm)
		if (jvmHost != null) try jvmHost.close() catch (_:Dynamic) {}
		jvmHost = null; jvmExports = null; jvmFnAnd = null; jvmFnOr = null; jvmMem = null;
		#end
	}

	public static function shouldFuse(n:Int):Bool {
		if (!enabled || n < minLength) {
			if (enabled && n < minLength) fuseSkips++;
			return false;
		}
		return ready();
	}

	static function init():Void {
		inited = true;
		readyFlag = false;
		try {
			#if js
			initJs();
			#elseif (java || jvm)
			initJvm();
			#else
			return;
			#end
			readyFlag = true;
		} catch (e:Dynamic) {
			readyFlag = false;
			#if sys
			Sys.println('NmaFuseHost: init failed, Haxe logic2 fallback — $e');
			#end
		}
	}

	/**
	 * Fuse two bool columns. Caller must ensure `ready()`. On internal error, returns null
	 * (caller should fall back to logic2 and bump `fuseFallbacks`).
	 */
	public static function fuse(a:GrowableVec<Float>, b:GrowableVec<Float>, andOp:Bool, n:Int):Null<GrowableVec<Float>> {
		if (!ready()) return null;
		try {
			#if js
			var out = fuseJs(a, b, andOp, n);
			#elseif (java || jvm)
			var out = fuseJvm(a, b, andOp, n);
			#else
			var out:GrowableVec<Float> = null;
			#end
			if (out != null) fuseCalls++;
			return out;
		} catch (e:Dynamic) {
			fuseFallbacks++;
			return null;
		}
	}

	#if js
	static function initJs():Void {
		var wat = NmaWasmFusedEmitter.emitModule();
		var bytes = musescript.compile.WatAssembler.assemble(wat).getData();
		var mod:Dynamic = js.Syntax.code("new WebAssembly.Module({0})", bytes);
		var inst:Dynamic = js.Syntax.code("new WebAssembly.Instance({0})", mod);
		jsFnAnd = inst.exports.fuse_and_cols;
		jsFnOr = inst.exports.fuse_or_cols;
		var mem:Dynamic = inst.exports.memory;
		jsView = new js.lib.Float64Array(mem.buffer);
		jsMemPages = Std.int(mem.buffer.byteLength / 65536);
	}

	static function ensureJsMem(n:Int):Void {
		var needBytes = n * 3 * 8;
		var needPages = Std.int(Math.ceil(needBytes / 65536.0));
		if (needPages <= jsMemPages) return;
		// Re-init with larger module if emitModule pages insufficient — bump emitter pages instead.
		throw 'NmaFuseHost: n=$n needs ${needPages} pages (have $jsMemPages)';
	}

	static function fuseJs(a:GrowableVec<Float>, b:GrowableVec<Float>, andOp:Bool, n:Int):GrowableVec<Float> {
		ensureJsMem(n);
		for (i in 0...n) {
			jsView[i] = a.at(i);
			jsView[n + i] = b.at(i);
		}
		var fn:Dynamic = andOp ? jsFnAnd : jsFnOr;
		fn(0, n * 8, n * 16, n);
		var out = new GrowableVec<Float>(n);
		var base = n * 2;
		for (i in 0...n) out.push(jsView[base + i]);
		return out;
	}
	#end

	#if (java || jvm)
	static function initJvm():Void {
		var wat = NmaWasmFusedEmitter.emitModule();
		var bytes:Bytes = musescript.compile.WatAssembler.assemble(wat);
		var path = "build/graal/nma_fuse_host.wasm";
		try sys.FileSystem.createDirectory("build/graal") catch (_:Dynamic) {}
		sys.io.File.saveBytes(path, bytes);
		jvmHost = new musescript.evo.graal.GraalWasmHost();
		var module = jvmHost.loadModuleFile(path);
		// Fuse module has no imports — empty Instantiator args.
		var instance = module.newInstance(musescript.evo.graal.GraalWasmHost.objArr([]));
		jvmExports = instance.getMember("exports");
		if (jvmExports == null || jvmExports.isNull()) {
			// Some Graal builds expose members on the instance itself.
			jvmExports = instance;
		}
		jvmFnAnd = jvmExports.getMember(NmaWasmFusedEmitter.EXPORT_AND);
		jvmFnOr = jvmExports.getMember(NmaWasmFusedEmitter.EXPORT_OR);
		jvmMem = jvmExports.getMember("memory");
		if (jvmFnAnd == null || jvmFnAnd.isNull()) throw "fuse_and_cols export missing";
		if (jvmMem == null || jvmMem.isNull()) throw "memory export missing";
	}

	static function fuseJvm(a:GrowableVec<Float>, b:GrowableVec<Float>, andOp:Bool, n:Int):GrowableVec<Float> {
		var order = musescript.evo.graal.Polyglot.ByteOrder.LITTLE_ENDIAN;
		for (i in 0...n) {
			jvmMem.writeBufferDouble(order, haxe.Int64.ofInt(i * 8), a.at(i));
			jvmMem.writeBufferDouble(order, haxe.Int64.ofInt((n + i) * 8), b.at(i));
		}
		var fn = andOp ? jvmFnAnd : jvmFnOr;
		fn.execute(musescript.evo.graal.GraalWasmHost.objArr([
			0, n * 8, n * 16, n
		]));
		var out = new GrowableVec<Float>(n);
		var base = n * 2;
		for (i in 0...n) {
			out.push(jvmMem.readBufferDouble(order, haxe.Int64.ofInt((base + i) * 8)));
		}
		return out;
	}
	#end
}

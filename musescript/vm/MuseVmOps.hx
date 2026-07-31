package musescript.vm;

/**
 * Value-semantics primitives for the Tier-A VM, kept **byte-identical** to the
 * matching helpers in `MuseInterp` (`toNum`, `truthy`, `preserveNum`,
 * `isStringy`). The parity gate (SPEC_BYTECODE_VM.md §4) is what guards this:
 * `TestBytecodeVmParity` runs interp and VM on the same corpus and asserts the
 * same trades — any drift here fails it. If you touch `MuseInterp`'s versions,
 * mirror the change here (and vice-versa) or the gate goes red.
 *
 * These are copied rather than shared because `MuseInterp`'s copies are private
 * and refactoring the audited reference interpreter to expose them is a bigger,
 * riskier move than a small mirrored helper the parity test polices for free.
 */
class MuseVmOps {
	/** Mirror of MuseInterp.truthy. */
	public static function truthy(v:Dynamic):Bool {
		if (v == null) return false;
		if (Std.isOfType(v, Bool)) return (v : Bool);
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float) != 0;
		if (Std.isOfType(v, String)) return (v : String).length > 0;
		return true;
	}

	/** Mirror of MuseInterp.toNum. */
	public static function toNum(v:Dynamic):Float {
		if (v == null) return 0;
		if (Std.isOfType(v, Int)) return (v : Int) * 1.0;
		#if (java || jvm)
		if (Std.isOfType(v, Float))
			return (v : Float);
		var n = Std.parseFloat(Std.string(v));
		return Math.isNaN(n) ? 0.0 : n;
		#elseif python
		try {
			return python.Syntax.code("float({0})", v);
		}
		catch (_:Dynamic) {
			return 0;
		}
		#else
		if (Std.isOfType(v, Float)) return (v : Float);
		return Std.parseFloat(Std.string(v));
		#end
	}

	/** Mirror of MuseInterp.preserveNum (JVM Dynamic Float→Int truncation guard). */
	public static function preserveNum(v:Dynamic):Dynamic {
		#if (java || jvm)
		if (v == null) return null;
		if (Std.isOfType(v, Int))
			return java.lang.Double.valueOf((v : Int) * 1.0);
		if (Std.isOfType(v, Float))
			return java.lang.Double.valueOf((v : Float));
		return v;
		#else
		return v;
		#end
	}

	public static inline function isStringy(v:Dynamic):Bool {
		return Std.isOfType(v, String);
	}
}

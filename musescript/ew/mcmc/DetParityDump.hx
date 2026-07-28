package musescript.ew.mcmc;

import haxe.Int64;
import haxe.io.FPHelper;

/**
 * Cross-target parity proof for the MCMC determinism foundation. Prints the RAW bit patterns of a
 * DetRng stream + DetMath.exp/log results as hex. Compiled to BOTH node (WASM/JS proxy) and JVM and
 * diffed: identical output ⇒ our operation set is byte-identical across the two backends the
 * dual-compiled kernel will run on. (Compare bits, never decimals — decimal formatting itself can
 * differ across targets even when the underlying double is identical.)
 */
class DetParityDump {
	static function main() {
		var buf = new StringBuf();

		var rng = new DetRng(Int64.make(0x12345678, 0x9ABCDEF0));
		buf.add("-- rng.next (hex32) --\n");
		for (_ in 0...20) buf.add(hex32(rng.next()) + "\n");

		buf.add("-- rng.nextUnit (raw f64 bits) --\n");
		for (_ in 0...10) buf.add(fbits(rng.nextUnit()) + "\n");

		buf.add("-- rng.nextInt(7) --\n");
		for (_ in 0...15) buf.add(Std.string(rng.nextInt(7)) + "\n");

		buf.add("-- DetMath.log / exp (raw f64 bits) --\n");
		var xs = [0.1, 0.5, 1.0, 1.5, 2.0, 2.718281828459045, 3.14159265, 10.0, 42.0, 100.0];
		for (x in xs) {
			buf.add("log(" + x + ")=" + fbits(DetMath.log(x)) + "\n");
			buf.add("exp(" + (x - 5.0) + ")=" + fbits(DetMath.exp(x - 5.0)) + "\n");
		}

		Sys.print(buf.toString());
	}

	static function hex32(v:Int):String
		return StringTools.hex(v, 8);

	/** Raw IEEE-754 bits of a double as 16 hex chars (high32:low32) — the true byte-identity check. */
	static function fbits(f:Float):String {
		var b = FPHelper.doubleToI64(f);
		return StringTools.hex(b.high, 8) + StringTools.hex(b.low, 8);
	}
}

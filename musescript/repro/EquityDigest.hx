package musescript.repro;

import haxe.io.FPHelper;

/**
 * Bit-identity fingerprint of an equity curve (Initiative 4.1).
 *
 * Digests RAW IEEE-754 bit patterns — never decimal formatting — so a consumer
 * can verify that backtest / browser-preview / live-preview curves reproduce
 * exactly. Same discipline as `DetParityDump.fbits`.
 */
class EquityDigest {
	/** 16-hex SHA1 prefix of concatenated f64 bit hex; empty curve → `"empty"`. */
	public static function of(equity:Null<Array<Float>>):String {
		if (equity == null || equity.length == 0) return "empty";
		var buf = new StringBuf();
		for (x in equity) {
			buf.add(fbits(x));
			buf.addChar(10); // '\n'
		}
		return haxe.crypto.Sha1.encode(buf.toString()).substr(0, 16);
	}

	/** True iff both curves have the same length and identical raw f64 bits. */
	public static function identical(a:Null<Array<Float>>, b:Null<Array<Float>>):Bool {
		if (a == null && b == null) return true;
		if (a == null || b == null) return false;
		if (a.length != b.length) return false;
		for (i in 0...a.length) {
			if (fbits(a[i]) != fbits(b[i])) return false;
		}
		return true;
	}

	/** Raw IEEE-754 bits of a double as 16 hex chars (high32:low32). */
	public static function fbits(f:Float):String {
		var b = FPHelper.doubleToI64(f);
		return StringTools.hex(b.high, 8) + StringTools.hex(b.low, 8);
	}
}

package musescript.evo;

import musescript.harness.Fill;

/**
 * IS-epoch fill-sequence fingerprint for semantic dedup / unique-behavior telemetry.
 * Hashes `(kind, bar)` only — price/qty drift must not invent new semantics.
 */
class FillHash {
	public static function of(fills:Null<Array<Fill>>):String {
		if (fills == null || fills.length == 0) return "empty";
		var buf = new StringBuf();
		for (f in fills) {
			buf.add(f.kind);
			buf.addChar(58); // ':'
			buf.add(Std.string(f.bar));
			buf.addChar(59); // ';'
		}
		return haxe.crypto.Sha1.encode(buf.toString()).substr(0, 16);
	}
}

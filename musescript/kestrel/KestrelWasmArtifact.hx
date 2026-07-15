package musescript.kestrel;

/**
 * Host-side metadata for Kestrel feature tapes in strategy WASM artifacts.
 *
 * The emitter encodes Kestrel feature slots into the normal string table as
 * `kestrel:<key>`. Feature rows use their encounter order within that filtered
 * list, independent of unrelated parameter/plot strings.
 */
class KestrelWasmArtifact {
	public static inline var PREFIX = "kestrel:";

	public static function featureSlots(strings:Array<String>):Array<FeatureSlot> {
		var out:Array<FeatureSlot> = [];
		for (s in strings) {
			if (StringTools.startsWith(s, PREFIX))
				out.push({ id: out.length, key: s.substr(PREFIX.length) });
		}
		return out;
	}

	public static function featureCount(strings:Array<String>):Int {
		return featureSlots(strings).length;
	}

	public static function featureTapeBytes(barCount:Int, strings:Array<String>):Int {
		return (barCount < 0 ? 0 : barCount) * featureCount(strings) * 8;
	}

	public static function toJson(strings:Array<String>, barCount:Int):Dynamic {
		return {
			schema: "musescript.kestrel.wasm-artifact/1",
			featureCount: featureCount(strings),
			featureTapeKind: KestrelWasmAbi.FEATURE_TAPE_KIND,
			featureTapeBytes: featureTapeBytes(barCount, strings),
			slots: [for (s in featureSlots(strings)) { id: s.id, key: s.key }]
		};
	}
}

typedef FeatureSlot = {
	var id:Int;
	var key:String;
}

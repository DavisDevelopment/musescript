package musescript.kestrel;

/**
 * Packs sparse Kestrel feature tapes into the dense feature-id layout expected
 * by KestrelWasmAbi/StrategyWasmRuntimeWat.
 */
class KestrelFeatureTape {
	public static function dense(
		strings:Array<String>,
		keyedTapes:Map<String, Array<Float>>,
		barCount:Int
	):Array<Array<Float>> {
		var count = KestrelWasmArtifact.featureCount(strings);
		var out:Array<Array<Float>> = [for (_ in 0...count) nanTape(barCount)];
		for (slot in KestrelWasmArtifact.featureSlots(strings)) {
			var tape = keyedTapes.get(slot.key);
			if (tape == null) continue;
			var row = out[slot.id];
			var n = Std.int(Math.min(barCount, tape.length));
			for (i in 0...n) row[i] = tape[i];
		}
		return out;
	}

	public static function fromConstant(
		strings:Array<String>,
		values:Map<String, Float>,
		barCount:Int
	):Array<Array<Float>> {
		var keyed = new Map<String, Array<Float>>();
		for (k in values.keys()) keyed.set(k, [for (_ in 0...barCount) values.get(k)]);
		return dense(strings, keyed, barCount);
	}

	static function nanTape(n:Int):Array<Float> {
		return [for (_ in 0...Std.int(Math.max(0, n))) Math.NaN];
	}
}

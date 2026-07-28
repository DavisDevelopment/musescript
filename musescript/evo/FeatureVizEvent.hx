package musescript.evo;

import musescript.harness.Bar;
import musescript.indicators.lib.FibRetracement;
import musescript.indicators.geom.GeomViz; // LevelSet, PivotMarkSet

/**
 * Shared FeatureViz contract — one POD/JSON frame for Swing `--gui`, the app chart
 * workbench, and (later) website replay. Not the hot-path GeomViz LevelSet slots;
 * those stay inside indicators. This is the scrub-/gen-boundary snapshot bus.
 *
 * Update cadence: generation boundary or explicit scrub only — never per Murmuration tick.
 *
 * Kind strings (extensible):
 * - `fib` — live now (from FibRetracement)
 * - `elliot` — reserved (Elliott count ribbon)
 * - `forecast` — live for `--ew-host` (cloud p50/band/inv + aux entropy/equity paths)
 *
 * Payload stays flexible: levels + anchors proven for fib; confidence / paths
 * for forecast / Elliott emitters.
 */
enum abstract FeatureVizKind(String) from String to String {
	var Fib = "fib";
	var Elliot = "elliot";
	var Forecast = "forecast";
}

typedef FeatureVizLevel = {
	var price:Float;
	var ratio:Float;
	var ?status:Float;
}

typedef FeatureVizAnchor = {
	var price:Float;
	var bar:Float;
	var ?dir:Float;
}

typedef FeatureVizPathPoint = {
	var bar:Float;
	var price:Float;
}

/**
 * Kind-specific bag. Fib fills `levels` + `anchors`. Elliott later: wave labels in
 * `extra` / confidence. Forecast later: `paths` (sample fans) + confidence band.
 */
typedef FeatureVizPayload = {
	var ?levels:Array<FeatureVizLevel>;
	var ?anchors:Array<FeatureVizAnchor>;
	var ?confidence:Float;
	var ?paths:Array<Array<FeatureVizPathPoint>>;
	var ?note:String;
	var ?extra:Dynamic;
}

typedef FeatureVizMeta = {
	var ?genomeKey:String;
	var ?sourceId:String;
	var ?epoch:Int;
}

/**
 * One feature claim on a bar range. JSON-friendly POD (plain fields, no class methods
 * required on the wire — use FeatureVizCodec for round-trip).
 */
@:structInit
class FeatureVizEvent {
	public var kind:String;
	/** Inclusive bar index range this frame describes. */
	public var barLo:Int;
	public var barHi:Int;
	public var payload:FeatureVizPayload;
	public var genomeKey:Null<String> = null;
	public var sourceId:Null<String> = null;
	/** Generation / scrub epoch (optional). */
	public var epoch:Null<Int> = null;

	public static function make(kind:String, barLo:Int, barHi:Int, payload:FeatureVizPayload,
			?meta:FeatureVizMeta):FeatureVizEvent {
		return {
			kind: kind,
			barLo: barLo,
			barHi: barHi,
			payload: payload,
			genomeKey: meta != null ? meta.genomeKey : null,
			sourceId: meta != null ? meta.sourceId : null,
			epoch: meta != null ? meta.epoch : null
		};
	}
}

/** JSON encode/decode — shared by unit tests, file dumps, future website replay. */
class FeatureVizCodec {
	public static function toDyn(e:FeatureVizEvent):Dynamic {
		var o:Dynamic = {
			kind: e.kind,
			barLo: e.barLo,
			barHi: e.barHi,
			payload: payloadToDyn(e.payload)
		};
		if (e.genomeKey != null) o.genomeKey = e.genomeKey;
		if (e.sourceId != null) o.sourceId = e.sourceId;
		if (e.epoch != null) o.epoch = e.epoch;
		return o;
	}

	public static function fromDyn(o:Dynamic):FeatureVizEvent {
		if (o == null) throw "FeatureVizCodec.fromDyn: null";
		var kind:String = o.kind;
		if (kind == null || kind.length == 0) throw "FeatureVizCodec.fromDyn: missing kind";
		var barLo:Int = o.barLo != null ? Std.int(o.barLo) : 0;
		var barHi:Int = o.barHi != null ? Std.int(o.barHi) : barLo;
		return {
			kind: kind,
			barLo: barLo,
			barHi: barHi,
			payload: payloadFromDyn(o.payload),
			genomeKey: o.genomeKey,
			sourceId: o.sourceId,
			epoch: o.epoch != null ? Std.int(o.epoch) : null
		};
	}

	public static function toJson(e:FeatureVizEvent):String {
		return haxe.Json.stringify(toDyn(e));
	}

	public static function parse(json:String):FeatureVizEvent {
		return fromDyn(haxe.Json.parse(json));
	}

	public static function arrayToJson(events:Array<FeatureVizEvent>):String {
		return haxe.Json.stringify([for (e in events) toDyn(e)]);
	}

	public static function parseArray(json:String):Array<FeatureVizEvent> {
		var arr:Array<Dynamic> = haxe.Json.parse(json);
		return [for (o in arr) fromDyn(o)];
	}

	static function payloadToDyn(p:FeatureVizPayload):Dynamic {
		if (p == null) return {};
		var o:Dynamic = {};
		if (p.levels != null) o.levels = p.levels;
		if (p.anchors != null) o.anchors = p.anchors;
		if (p.confidence != null) o.confidence = p.confidence;
		if (p.paths != null) o.paths = p.paths;
		if (p.note != null) o.note = p.note;
		if (p.extra != null) o.extra = p.extra;
		return o;
	}

	static function payloadFromDyn(o:Dynamic):FeatureVizPayload {
		if (o == null) return {};
		var levels:Array<FeatureVizLevel> = null;
		if (o.levels != null) {
			levels = [];
			var raw:Array<Dynamic> = o.levels;
			for (L in raw) {
				levels.push({
					price: (L.price : Float),
					ratio: (L.ratio : Float),
					status: L.status
				});
			}
		}
		var anchors:Array<FeatureVizAnchor> = null;
		if (o.anchors != null) {
			anchors = [];
			var rawA:Array<Dynamic> = o.anchors;
			for (a in rawA) {
				anchors.push({
					price: (a.price : Float),
					bar: (a.bar : Float),
					dir: a.dir
				});
			}
		}
		return {
			levels: levels,
			anchors: anchors,
			confidence: o.confidence,
			paths: o.paths,
			note: o.note,
			extra: o.extra
		};
	}
}

/**
 * Gen-/scrub-boundary collector. Push from emit sites; consumers take `snapshot()`
 * (copy) so the bus can clear without racing paint.
 */
class FeatureVizBus {
	var events:Array<FeatureVizEvent> = [];

	public function new() {}

	public function clear():Void {
		events = [];
	}

	public function push(e:FeatureVizEvent):Void {
		if (e != null) events.push(e);
	}

	public function pushAll(xs:Array<FeatureVizEvent>):Void {
		if (xs == null) return;
		for (e in xs) push(e);
	}

	/** Defensive copy for Swing / scrub consumers. */
	public function snapshot():Array<FeatureVizEvent> {
		return events.copy();
	}

	public function length():Int return events.length;
}

/**
 * Fib emit — ONE real engine (`FibRetracement`), no second ladder.
 * Converts the indicator's GeomViz packs into a FeatureVizEvent for the shared bus.
 */
class FeatureVizFib {
	/**
	 * Build a frame from an already-evaluated `FibRetracement` output (same object the
	 * indicator mutates in place — caller must snapshot fields before the next update).
	 */
	public static function fromRetracement(out:{
			levels:LevelSet,
			pivots:PivotMarkSet
		}, barLo:Int, barHi:Int, ?meta:FeatureVizMeta):FeatureVizEvent {
		var payload:FeatureVizPayload = {
			levels: unpackLevels(out.levels),
			anchors: unpackPivots(out.pivots),
			note: "fib_retracement"
		};
		return FeatureVizEvent.make(FeatureVizKind.Fib, barLo, barHi, payload, withSource(meta, "fib_retracement"));
	}

	/**
	 * Walk `bars` once through `FibRetracement(period)` (Window mode — same math as
	 * `NmaFeatureHost.fibCol` / IndicatorCache). Returns the last ready frame, or null
	 * if the tape never warmed. Gen-boundary / scrub only.
	 */
	public static function snapshotTape(bars:Array<Bar>, period:Int = 20,
			?meta:FeatureVizMeta):Null<FeatureVizEvent> {
		if (bars == null || bars.length == 0 || period <= 0) return null;
		var fr = new FibRetracement(period);
		var last:{levels:LevelSet, pivots:PivotMarkSet} = null;
		var lastIdx = 0;
		for (b in bars) {
			var o = fr.update(b);
			if (o != null) {
				last = o;
				lastIdx = b.index;
			}
		}
		if (last == null) return null;
		var barLo = lastIdx - period + 1;
		if (barLo < 0) barLo = 0;
		return fromRetracement(last, barLo, lastIdx, withSource(meta, "fib_retracement:" + period));
	}

	static function withSource(meta:Null<FeatureVizMeta>, defaultSource:String):FeatureVizMeta {
		return {
			genomeKey: meta != null ? meta.genomeKey : null,
			sourceId: (meta != null && meta.sourceId != null) ? meta.sourceId : defaultSource,
			epoch: meta != null ? meta.epoch : null
		};
	}

	static function unpackLevels(ls:LevelSet):Array<FeatureVizLevel> {
		var out:Array<FeatureVizLevel> = [];
		if (ls == null) return out;
		var n = Std.int(ls.count);
		if (n > LevelSet.CAP) n = LevelSet.CAP;
		for (i in 0...n) {
			var price = Math.NaN;
			var ratio = Math.NaN;
			var status = Math.NaN;
			switch (i) {
				case 0: price = ls.p0; ratio = ls.r0; status = ls.s0;
				case 1: price = ls.p1; ratio = ls.r1; status = ls.s1;
				case 2: price = ls.p2; ratio = ls.r2; status = ls.s2;
				case 3: price = ls.p3; ratio = ls.r3; status = ls.s3;
				case 4: price = ls.p4; ratio = ls.r4; status = ls.s4;
				case 5: price = ls.p5; ratio = ls.r5; status = ls.s5;
				case 6: price = ls.p6; ratio = ls.r6; status = ls.s6;
				case 7: price = ls.p7; ratio = ls.r7; status = ls.s7;
				default:
			}
			if (Math.isFinite(price)) out.push({price: price, ratio: ratio, status: status});
		}
		return out;
	}

	static function unpackPivots(pm:PivotMarkSet):Array<FeatureVizAnchor> {
		var out:Array<FeatureVizAnchor> = [];
		if (pm == null) return out;
		var n = Std.int(pm.count);
		if (n > PivotMarkSet.CAP) n = PivotMarkSet.CAP;
		for (i in 0...n) {
			var price = Math.NaN;
			var bar = Math.NaN;
			var dir = Math.NaN;
			switch (i) {
				case 0: price = pm.p0; dir = pm.d0; bar = pm.b0;
				case 1: price = pm.p1; dir = pm.d1; bar = pm.b1;
				case 2: price = pm.p2; dir = pm.d2; bar = pm.b2;
				case 3: price = pm.p3; dir = pm.d3; bar = pm.b3;
				case 4: price = pm.p4; dir = pm.d4; bar = pm.b4;
				case 5: price = pm.p5; dir = pm.d5; bar = pm.b5;
				case 6: price = pm.p6; dir = pm.d6; bar = pm.b6;
				case 7: price = pm.p7; dir = pm.d7; bar = pm.b7;
				default:
			}
			if (Math.isFinite(price)) out.push({price: price, bar: bar, dir: dir});
		}
		return out;
	}
}

/**
 * Forecast emit for EW host clouds — gen-boundary series the dashboard can paint as real curves
 * (not constant fib levels). Paths are price-space: close, p50, p05, p95, invalidate.
 * Aux series (entropy, equity) live in `payload.extra.aux` as `{name, values}` for a second strip.
 */
class FeatureVizForecast {
	/**
	 * Build a `forecast` frame from a provider that already materialised (or will materialise)
	 * clouds over `bars`. Optional `equity` (same length or shorter) becomes an aux sparkline.
	 * `stride` downsamples for Swing paint cost (default 2).
	 */
	public static function fromProvider(
		provider:ProjectionProvider,
		bars:Array<Bar>,
		?equity:Array<Float>,
		?meta:FeatureVizMeta,
		?stride:Int = 2,
		?hitRate:Float,
		?projScore:Float
	):Null<FeatureVizEvent> {
		if (provider == null || bars == null || bars.length < 2)
			return null;
		var cs = provider.materialize(bars);
		if (cs == null || cs.length == 0)
			return null;
		var step = stride != null && stride > 0 ? stride : 1;
		var closeP:Array<FeatureVizPathPoint> = [];
		var p50P:Array<FeatureVizPathPoint> = [];
		var p05P:Array<FeatureVizPathPoint> = [];
		var p95P:Array<FeatureVizPathPoint> = [];
		var invP:Array<FeatureVizPathPoint> = [];
		var entVals:Array<Float> = [];
		var i = 0;
		while (i < bars.length && i < cs.length) {
			var b = bars[i];
			var c = cs[i];
			var barIdx:Float = b.index;
			closeP.push({bar: barIdx, price: b.close});
			if (finite(c.priceMid)) p50P.push({bar: barIdx, price: c.priceMid});
			if (finite(c.priceLo)) p05P.push({bar: barIdx, price: c.priceLo});
			if (finite(c.priceHi)) p95P.push({bar: barIdx, price: c.priceHi});
			if (finite(c.invalidatePrice)) invP.push({bar: barIdx, price: c.invalidatePrice});
			entVals.push(finite(c.countEntropy) ? c.countEntropy : Math.NaN);
			i += step;
		}
		if (p50P.length < 2)
			return null;
		var aux:Array<Dynamic> = [
			{name: "entropy", values: entVals}
		];
		if (equity != null && equity.length > 1) {
			var eqVals:Array<Float> = [];
			var j = 0;
			while (j < equity.length) {
				eqVals.push(equity[j]);
				j += step;
			}
			aux.push({name: "equity", values: eqVals});
		}
		var conf = Math.NaN;
		if (hitRate != null && Math.isFinite(hitRate))
			conf = hitRate;
		else if (projScore != null && Math.isFinite(projScore))
			conf = (projScore + 1.0) / 2.0;
		var note = "ew_host_cloud";
		if (hitRate != null && Math.isFinite(hitRate))
			note += " hitRate=" + round3(hitRate);
		if (projScore != null && Math.isFinite(projScore))
			note += " projScore=" + round3(projScore);
		var payload:FeatureVizPayload = {
			paths: [closeP, p50P, p05P, p95P, invP],
			confidence: Math.isFinite(conf) ? conf : null,
			note: note,
			extra: {
				pathLabels: ["close", "p50", "p05", "p95", "inv"],
				aux: aux
			}
		};
		var barLo = bars[0].index;
		var barHi = bars[bars.length - 1].index;
		return FeatureVizEvent.make(
			FeatureVizKind.Forecast, barLo, barHi, payload,
			withSourceMeta(meta, "ew_host_forecast")
		);
	}

	static function withSourceMeta(meta:Null<FeatureVizMeta>, defaultSource:String):FeatureVizMeta {
		return {
			genomeKey: meta != null ? meta.genomeKey : null,
			sourceId: (meta != null && meta.sourceId != null) ? meta.sourceId : defaultSource,
			epoch: meta != null ? meta.epoch : null
		};
	}

	static inline function finite(x:Float):Bool
		return !Math.isNaN(x) && Math.isFinite(x);

	static function round3(x:Float):String
		return Std.string(Math.round(x * 1000) / 1000);
}

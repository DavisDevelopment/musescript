package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.lib.FibRetracement;
import musescript.evo.FeatureVizEvent;
import musescript.evo.FeatureVizEvent.FeatureVizBus;
import musescript.evo.FeatureVizEvent.FeatureVizCodec;
import musescript.evo.FeatureVizEvent.FeatureVizFib;
import musescript.evo.FeatureVizEvent.FeatureVizKind;

class TestFeatureViz extends Test {
	static var barCounter:Int = 0;

	static function bar(o:Float, h:Float, l:Float, c:Float):Bar {
		var i = barCounter++;
		return {open: o, high: h, low: l, close: c, volume: 1.0, time: (i : Float), index: i};
	}

	public function testSchemaJsonRoundTrip() {
		var e = FeatureVizEvent.make(FeatureVizKind.Fib, 10, 29, {
			levels: [{price: 100.0, ratio: 0.618, status: 1.0}, {price: 90.0, ratio: 0.786}],
			anchors: [{price: 80.0, bar: 10.0, dir: -1.0}, {price: 120.0, bar: 29.0, dir: 1.0}],
			confidence: 0.9,
			note: "unit"
		}, {genomeKey: "champ", sourceId: "fib_retracement:20", epoch: 3});
		var json = FeatureVizCodec.toJson(e);
		Assert.isTrue(json.indexOf('"fib"') >= 0);
		var back = FeatureVizCodec.parse(json);
		Assert.equals("fib", back.kind);
		Assert.equals(10, back.barLo);
		Assert.equals(29, back.barHi);
		Assert.equals("champ", back.genomeKey);
		Assert.equals("fib_retracement:20", back.sourceId);
		Assert.equals(3, back.epoch);
		Assert.equals(2, back.payload.levels.length);
		Assert.floatEquals(100.0, back.payload.levels[0].price, 1e-9);
		Assert.floatEquals(0.618, back.payload.levels[0].ratio, 1e-9);
		Assert.equals(2, back.payload.anchors.length);
		Assert.floatEquals(0.9, back.payload.confidence, 1e-9);
	}

	public function testArrayCodecRoundTrip() {
		var a = FeatureVizEvent.make(FeatureVizKind.Fib, 0, 5, {levels: [{price: 1.0, ratio: 0.0}]});
		var b = FeatureVizEvent.make(FeatureVizKind.Elliot, 0, 5, {confidence: 0.5, note: "stub"});
		var json = FeatureVizCodec.arrayToJson([a, b]);
		var back = FeatureVizCodec.parseArray(json);
		Assert.equals(2, back.length);
		Assert.equals("fib", back[0].kind);
		Assert.equals("elliot", back[1].kind);
		Assert.floatEquals(0.5, back[1].payload.confidence, 1e-9);
	}

	public function testEmitCollectFromFibRetracement() {
		barCounter = 0;
		var bars:Array<Bar> = [];
		for (i in 0...8) {
			var base = 100.0 + i * 2;
			bars.push(bar(base, base + 5, base - 3, base));
		}
		var bus = new FeatureVizBus();
		var frame = FeatureVizFib.snapshotTape(bars, 3, {epoch: 1, genomeKey: "g0"});
		Assert.notNull(frame);
		bus.push(frame);
		Assert.equals(1, bus.length());
		var snap = bus.snapshot();
		Assert.equals("fib", snap[0].kind);
		Assert.isTrue(snap[0].payload.levels.length >= 5);
		Assert.isTrue(Math.isFinite(snap[0].payload.levels[0].price));
		Assert.equals("g0", snap[0].genomeKey);
		Assert.equals(1, snap[0].epoch);
		Assert.isTrue(snap[0].sourceId.indexOf("fib_retracement") >= 0);

		// Same engine path as indicator update — levels.count matches GeomViz pack.
		barCounter = 0;
		var fr = new FibRetracement(3);
		var last = null;
		for (b in bars) {
			var o = fr.update(b);
			if (o != null) last = o;
		}
		Assert.notNull(last);
		var direct = FeatureVizFib.fromRetracement(last, 0, 7);
		Assert.equals(Std.int(last.levels.count), direct.payload.levels.length);
	}

	public function testBusSnapshotIsCopy() {
		var bus = new FeatureVizBus();
		bus.push(FeatureVizEvent.make(FeatureVizKind.Forecast, 0, 1, {note: "reserved"}));
		var a = bus.snapshot();
		bus.clear();
		Assert.equals(1, a.length);
		Assert.equals(0, bus.length());
		Assert.equals("forecast", a[0].kind);
	}
}

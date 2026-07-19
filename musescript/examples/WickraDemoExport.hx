package musescript.examples;

import musescript.harness.Bar;
import musescript.harness.HarnessContext;
import musescript.indicators.IndicatorRegistry;
import musescript.indicators.IndicatorSpec;
import musescript.types.MuseType;

/**
 * Demo export: runs every registered Wickra-port indicator over one shared
 * synthetic OHLCV tape and dumps a JSON file of per-bar series, for the
 * standalone visual-demo artifact. Not a test — a one-shot data generator.
 */
class WickraDemoExport {
	public static function main():Void {
		var bars = syntheticBars(240);
		var closeSeries = [for (b in bars) b.close];

		var results:Array<Dynamic> = [];
		var skipped:Array<String> = [];

		for (name => spec in IndicatorRegistry.all()) {
			try {
				switch (spec.ret) {
					case TObject(fieldDefs):
						var fieldNames = [for (f in fieldDefs) f.name];
						var fields = runIndicatorFields(spec, bars, fieldNames);
						results.push({ name: name, category: "Multi-line & Bands", fieldNames: fieldNames, fields: fields });
					default:
						var series = runIndicator(spec, bars);
						var category = classify(series);
						results.push({ name: name, category: category, values: series });
				}
			} catch (e:Dynamic) {
				skipped.push(name + ": " + Std.string(e));
			}
		}

		results.sort((a, b) -> {
			var an:String = a.name;
			var bn:String = b.name;
			return an < bn ? -1 : (an > bn ? 1 : 0);
		});

		var out = {
			prices: closeSeries,
			indicatorCount: results.length,
			skippedCount: skipped.length,
			indicators: results
		};

		sys.io.File.saveContent("wickra-demo-data.json", haxe.Json.stringify(out));
		Sys.println('Wrote wickra-demo-data.json: ${results.length} indicators, ${skipped.length} skipped');
		if (skipped.length > 0) Sys.println("Skipped: " + skipped.join(", "));
	}

	static function synthArgs(spec:IndicatorSpec):Array<Dynamic> {
		var windowIdx = 0;
		return [for (t in spec.args) {
			switch (t) {
				case TSeries: "close";
				case TWindow: { windowIdx++; (5 * windowIdx : Float); }
				case TString: "x";
				default: 0.5;
			}
		}];
	}

	static function runIndicator(spec:IndicatorSpec, bars:Array<Bar>):Array<Dynamic> {
		var h = new HarnessContext();
		var args = synthArgs(spec);
		var out:Array<Dynamic> = [];
		for (bar in bars) {
			h.observeBar(bar);
			var v:Dynamic = spec.eval(h, args);
			out.push(scalarOf(v));
		}
		return out;
	}

	/** Multi-output indicators: run once, but record EVERY declared field's own series (not just one). */
	static function runIndicatorFields(spec:IndicatorSpec, bars:Array<Bar>, fieldNames:Array<String>):Dynamic {
		var h = new HarnessContext();
		var args = synthArgs(spec);
		var perField:Map<String, Array<Dynamic>> = new Map();
		for (fn in fieldNames) perField.set(fn, []);

		for (bar in bars) {
			h.observeBar(bar);
			var v:Dynamic = spec.eval(h, args);
			for (fn in fieldNames) {
				var arr = perField.get(fn);
				if (v != null && Reflect.hasField(v, fn)) {
					var f:Float = Reflect.field(v, fn);
					arr.push(Math.isFinite(f) ? f : null);
				} else {
					arr.push(null);
				}
			}
		}
		var out = {};
		for (fn in fieldNames) Reflect.setField(out, fn, perField.get(fn));
		return out;
	}

	/** Scalar-output indicators only (TObject outputs are routed through runIndicatorFields instead). */
	static function scalarOf(v:Dynamic):Dynamic {
		if (v == null) return null;
		var f:Float = v;
		return Math.isFinite(f) ? f : null;
	}

	static function classify(series:Array<Dynamic>):String {
		var nonNull = 0;
		var patternLike = 0;
		for (v in series) {
			if (v == null) continue;
			var f:Float = v;
			nonNull++;
			if (f == -1.0 || f == 0.0 || f == 1.0) patternLike++;
		}
		if (nonNull > 0 && patternLike / nonNull > 0.9) return "Candlestick & Pattern Signals";
		return "Oscillators & Overlays";
	}

	static function syntheticBars(n:Int):Array<Bar> {
		var bars:Array<Bar> = [];
		var price = 100.0;
		var rng = 7;
		for (i in 0...n) {
			rng = (rng * 1103515245 + 12345) & 0x7fffffff;
			var noise = ((rng % 1000) / 1000.0 - 0.5) * 2.0;
			var trend = Math.sin(i * 0.05) * 8.0 + i * 0.05;
			var o = price;
			var target = 100.0 + trend;
			var c = o + (target - o) * 0.15 + noise * 0.6;
			var h = Math.max(o, c) + Math.abs(noise) * 0.4 + 0.1;
			var l = Math.min(o, c) - Math.abs(noise) * 0.4 - 0.1;
			var v = 1000.0 + (rng % 800) + (i % 15 == 0 ? 2000.0 : 0.0);
			bars.push({ open: o, high: h, low: l, close: c, volume: v, time: (i * 60.0 : Float), index: i });
			price = c;
		}
		return bars;
	}
}

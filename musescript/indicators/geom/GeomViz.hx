package musescript.indicators.geom;

import musescript.types.MuseType;

/**
 * Shared chart-viz payload contract for geometry / EW / harmonic indicators.
 *
 * Design for V8 + JVM JIT:
 * - Fixed field shapes (no dynamic property add/delete after first write)
 * - Capped slots with `count` + NaN sentinels for unused slots
 * - Status as Float (PivotStatus ordinal) for flat TObject / JS emit
 * - Nested TObject fragments (`levels`, `rays`, `zones`, `pivots`, `labels`, `forecast`)
 *
 * Chart agent binds: `out.levels.p0`..`p7` for i in 0...count, etc.
 * Caps: LEVEL=8, RAY=6, ZONE=4, PIVOT=8, LABEL=8, ARC=4, RING_PRICE=8.
 */

/** Kind codes for zones (chart styling). */
enum abstract ZoneKind(Int) from Int to Int {
	var RetraceBand = 1;
	var Prz = 2;
	var Extension = 3;
	var Channel = 4;
	var TimeWindow = 5;
	var Forecast = 6;
	var MurreyOctave = 7;
	var GannFan = 8;
	var Cycle = 9;
	/** EW count-kill level (thin projected band). */
	var Invalidation = 10;
	/** Coarse parent degree span (EW nesting overlay). */
	var ParentDegree = 11;
}

/** Label codes (avoid free-form strings on hot path). */
enum abstract GeomLabelCode(Int) from Int to Int {
	var None = 0;
	var Wave1 = 1;
	var Wave2 = 2;
	var Wave3 = 3;
	var Wave4 = 4;
	var Wave5 = 5;
	var WaveA = 6;
	var WaveB = 7;
	var WaveC = 8;
	var X = 10;
	var A = 11;
	var B = 12;
	var C = 13;
	var D = 14;
	var SwingHigh = 20;
	var SwingLow = 21;
	var FibLevel = 30;
	var PrzLabel = 40;
	var Impulse = 50;
	var Zigzag = 51;
	/** Matches contract.js GeomLabelCode.Projected (forecast arrow label). */
	var Projected = 60;
}

@:structInit
class LevelSet {
	public var count:Float;
	public var p0:Float; public var r0:Float; public var s0:Float;
	public var p1:Float; public var r1:Float; public var s1:Float;
	public var p2:Float; public var r2:Float; public var s2:Float;
	public var p3:Float; public var r3:Float; public var s3:Float;
	public var p4:Float; public var r4:Float; public var s4:Float;
	public var p5:Float; public var r5:Float; public var s5:Float;
	public var p6:Float; public var r6:Float; public var s6:Float;
	public var p7:Float; public var r7:Float; public var s7:Float;

	public static inline var CAP = 8;

	public static function nan():LevelSet {
		return {
			count: 0,
			p0: Math.NaN, r0: Math.NaN, s0: Math.NaN,
			p1: Math.NaN, r1: Math.NaN, s1: Math.NaN,
			p2: Math.NaN, r2: Math.NaN, s2: Math.NaN,
			p3: Math.NaN, r3: Math.NaN, s3: Math.NaN,
			p4: Math.NaN, r4: Math.NaN, s4: Math.NaN,
			p5: Math.NaN, r5: Math.NaN, s5: Math.NaN,
			p6: Math.NaN, r6: Math.NaN, s6: Math.NaN,
			p7: Math.NaN, r7: Math.NaN, s7: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		p0 = r0 = s0 = Math.NaN;
		p1 = r1 = s1 = Math.NaN;
		p2 = r2 = s2 = Math.NaN;
		p3 = r3 = s3 = Math.NaN;
		p4 = r4 = s4 = Math.NaN;
		p5 = r5 = s5 = Math.NaN;
		p6 = r6 = s6 = Math.NaN;
		p7 = r7 = s7 = Math.NaN;
	}

	public function set(i:Int, price:Float, ratio:Float, status:Float):Void {
		switch (i) {
			case 0: p0 = price; r0 = ratio; s0 = status;
			case 1: p1 = price; r1 = ratio; s1 = status;
			case 2: p2 = price; r2 = ratio; s2 = status;
			case 3: p3 = price; r3 = ratio; s3 = status;
			case 4: p4 = price; r4 = ratio; s4 = status;
			case 5: p5 = price; r5 = ratio; s5 = status;
			case 6: p6 = price; r6 = ratio; s6 = status;
			case 7: p7 = price; r7 = ratio; s7 = status;
			default:
		}
	}
}

@:structInit
class RaySet {
	public var count:Float;
	public var y0_0:Float; public var y1_0:Float; public var b0_0:Float; public var b1_0:Float; public var s0:Float;
	public var y0_1:Float; public var y1_1:Float; public var b0_1:Float; public var b1_1:Float; public var s1:Float;
	public var y0_2:Float; public var y1_2:Float; public var b0_2:Float; public var b1_2:Float; public var s2:Float;
	public var y0_3:Float; public var y1_3:Float; public var b0_3:Float; public var b1_3:Float; public var s3:Float;
	public var y0_4:Float; public var y1_4:Float; public var b0_4:Float; public var b1_4:Float; public var s4:Float;
	public var y0_5:Float; public var y1_5:Float; public var b0_5:Float; public var b1_5:Float; public var s5:Float;

	public static inline var CAP = 6;

	public static function nan():RaySet {
		return {
			count: 0,
			y0_0: Math.NaN, y1_0: Math.NaN, b0_0: Math.NaN, b1_0: Math.NaN, s0: Math.NaN,
			y0_1: Math.NaN, y1_1: Math.NaN, b0_1: Math.NaN, b1_1: Math.NaN, s1: Math.NaN,
			y0_2: Math.NaN, y1_2: Math.NaN, b0_2: Math.NaN, b1_2: Math.NaN, s2: Math.NaN,
			y0_3: Math.NaN, y1_3: Math.NaN, b0_3: Math.NaN, b1_3: Math.NaN, s3: Math.NaN,
			y0_4: Math.NaN, y1_4: Math.NaN, b0_4: Math.NaN, b1_4: Math.NaN, s4: Math.NaN,
			y0_5: Math.NaN, y1_5: Math.NaN, b0_5: Math.NaN, b1_5: Math.NaN, s5: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		y0_0 = y1_0 = b0_0 = b1_0 = s0 = Math.NaN;
		y0_1 = y1_1 = b0_1 = b1_1 = s1 = Math.NaN;
		y0_2 = y1_2 = b0_2 = b1_2 = s2 = Math.NaN;
		y0_3 = y1_3 = b0_3 = b1_3 = s3 = Math.NaN;
		y0_4 = y1_4 = b0_4 = b1_4 = s4 = Math.NaN;
		y0_5 = y1_5 = b0_5 = b1_5 = s5 = Math.NaN;
	}

	public function set(i:Int, y0:Float, y1:Float, b0:Float, b1:Float, status:Float):Void {
		switch (i) {
			case 0: y0_0 = y0; y1_0 = y1; b0_0 = b0; b1_0 = b1; s0 = status;
			case 1: y0_1 = y0; y1_1 = y1; b0_1 = b0; b1_1 = b1; s1 = status;
			case 2: y0_2 = y0; y1_2 = y1; b0_2 = b0; b1_2 = b1; s2 = status;
			case 3: y0_3 = y0; y1_3 = y1; b0_3 = b0; b1_3 = b1; s3 = status;
			case 4: y0_4 = y0; y1_4 = y1; b0_4 = b0; b1_4 = b1; s4 = status;
			case 5: y0_5 = y0; y1_5 = y1; b0_5 = b0; b1_5 = b1; s5 = status;
			default:
		}
	}
}

@:structInit
class ZoneSet {
	public var count:Float;
	public var lo0:Float; public var hi0:Float; public var b0_0:Float; public var b1_0:Float; public var s0:Float; public var k0:Float;
	public var lo1:Float; public var hi1:Float; public var b0_1:Float; public var b1_1:Float; public var s1:Float; public var k1:Float;
	public var lo2:Float; public var hi2:Float; public var b0_2:Float; public var b1_2:Float; public var s2:Float; public var k2:Float;
	public var lo3:Float; public var hi3:Float; public var b0_3:Float; public var b1_3:Float; public var s3:Float; public var k3:Float;

	public static inline var CAP = 4;

	public static function nan():ZoneSet {
		return {
			count: 0,
			lo0: Math.NaN, hi0: Math.NaN, b0_0: Math.NaN, b1_0: Math.NaN, s0: Math.NaN, k0: Math.NaN,
			lo1: Math.NaN, hi1: Math.NaN, b0_1: Math.NaN, b1_1: Math.NaN, s1: Math.NaN, k1: Math.NaN,
			lo2: Math.NaN, hi2: Math.NaN, b0_2: Math.NaN, b1_2: Math.NaN, s2: Math.NaN, k2: Math.NaN,
			lo3: Math.NaN, hi3: Math.NaN, b0_3: Math.NaN, b1_3: Math.NaN, s3: Math.NaN, k3: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		lo0 = hi0 = b0_0 = b1_0 = s0 = k0 = Math.NaN;
		lo1 = hi1 = b0_1 = b1_1 = s1 = k1 = Math.NaN;
		lo2 = hi2 = b0_2 = b1_2 = s2 = k2 = Math.NaN;
		lo3 = hi3 = b0_3 = b1_3 = s3 = k3 = Math.NaN;
	}

	public function set(i:Int, lo:Float, hi:Float, barLo:Float, barHi:Float, status:Float, kind:Float):Void {
		switch (i) {
			case 0: lo0 = lo; hi0 = hi; b0_0 = barLo; b1_0 = barHi; s0 = status; k0 = kind;
			case 1: lo1 = lo; hi1 = hi; b0_1 = barLo; b1_1 = barHi; s1 = status; k1 = kind;
			case 2: lo2 = lo; hi2 = hi; b0_2 = barLo; b1_2 = barHi; s2 = status; k2 = kind;
			case 3: lo3 = lo; hi3 = hi; b0_3 = barLo; b1_3 = barHi; s3 = status; k3 = kind;
			default:
		}
	}
}

@:structInit
class PivotMarkSet {
	public var count:Float;
	public var p0:Float; public var d0:Float; public var b0:Float; public var s0:Float;
	public var p1:Float; public var d1:Float; public var b1:Float; public var s1:Float;
	public var p2:Float; public var d2:Float; public var b2:Float; public var s2:Float;
	public var p3:Float; public var d3:Float; public var b3:Float; public var s3:Float;
	public var p4:Float; public var d4:Float; public var b4:Float; public var s4:Float;
	public var p5:Float; public var d5:Float; public var b5:Float; public var s5:Float;
	public var p6:Float; public var d6:Float; public var b6:Float; public var s6:Float;
	public var p7:Float; public var d7:Float; public var b7:Float; public var s7:Float;

	public static inline var CAP = 8;

	public static function nan():PivotMarkSet {
		return {
			count: 0,
			p0: Math.NaN, d0: Math.NaN, b0: Math.NaN, s0: Math.NaN,
			p1: Math.NaN, d1: Math.NaN, b1: Math.NaN, s1: Math.NaN,
			p2: Math.NaN, d2: Math.NaN, b2: Math.NaN, s2: Math.NaN,
			p3: Math.NaN, d3: Math.NaN, b3: Math.NaN, s3: Math.NaN,
			p4: Math.NaN, d4: Math.NaN, b4: Math.NaN, s4: Math.NaN,
			p5: Math.NaN, d5: Math.NaN, b5: Math.NaN, s5: Math.NaN,
			p6: Math.NaN, d6: Math.NaN, b6: Math.NaN, s6: Math.NaN,
			p7: Math.NaN, d7: Math.NaN, b7: Math.NaN, s7: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		p0 = d0 = b0 = s0 = Math.NaN;
		p1 = d1 = b1 = s1 = Math.NaN;
		p2 = d2 = b2 = s2 = Math.NaN;
		p3 = d3 = b3 = s3 = Math.NaN;
		p4 = d4 = b4 = s4 = Math.NaN;
		p5 = d5 = b5 = s5 = Math.NaN;
		p6 = d6 = b6 = s6 = Math.NaN;
		p7 = d7 = b7 = s7 = Math.NaN;
	}

	public function set(i:Int, price:Float, dir:Float, bar:Float, status:Float):Void {
		switch (i) {
			case 0: p0 = price; d0 = dir; b0 = bar; s0 = status;
			case 1: p1 = price; d1 = dir; b1 = bar; s1 = status;
			case 2: p2 = price; d2 = dir; b2 = bar; s2 = status;
			case 3: p3 = price; d3 = dir; b3 = bar; s3 = status;
			case 4: p4 = price; d4 = dir; b4 = bar; s4 = status;
			case 5: p5 = price; d5 = dir; b5 = bar; s5 = status;
			case 6: p6 = price; d6 = dir; b6 = bar; s6 = status;
			case 7: p7 = price; d7 = dir; b7 = bar; s7 = status;
			default:
		}
	}
}

@:structInit
class LabelSet {
	public var count:Float;
	public var c0:Float; public var p0:Float; public var b0:Float; public var s0:Float;
	public var c1:Float; public var p1:Float; public var b1:Float; public var s1:Float;
	public var c2:Float; public var p2:Float; public var b2:Float; public var s2:Float;
	public var c3:Float; public var p3:Float; public var b3:Float; public var s3:Float;
	public var c4:Float; public var p4:Float; public var b4:Float; public var s4:Float;
	public var c5:Float; public var p5:Float; public var b5:Float; public var s5:Float;
	public var c6:Float; public var p6:Float; public var b6:Float; public var s6:Float;
	public var c7:Float; public var p7:Float; public var b7:Float; public var s7:Float;

	public static inline var CAP = 8;

	public static function nan():LabelSet {
		return {
			count: 0,
			c0: Math.NaN, p0: Math.NaN, b0: Math.NaN, s0: Math.NaN,
			c1: Math.NaN, p1: Math.NaN, b1: Math.NaN, s1: Math.NaN,
			c2: Math.NaN, p2: Math.NaN, b2: Math.NaN, s2: Math.NaN,
			c3: Math.NaN, p3: Math.NaN, b3: Math.NaN, s3: Math.NaN,
			c4: Math.NaN, p4: Math.NaN, b4: Math.NaN, s4: Math.NaN,
			c5: Math.NaN, p5: Math.NaN, b5: Math.NaN, s5: Math.NaN,
			c6: Math.NaN, p6: Math.NaN, b6: Math.NaN, s6: Math.NaN,
			c7: Math.NaN, p7: Math.NaN, b7: Math.NaN, s7: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		c0 = p0 = b0 = s0 = Math.NaN;
		c1 = p1 = b1 = s1 = Math.NaN;
		c2 = p2 = b2 = s2 = Math.NaN;
		c3 = p3 = b3 = s3 = Math.NaN;
		c4 = p4 = b4 = s4 = Math.NaN;
		c5 = p5 = b5 = s5 = Math.NaN;
		c6 = p6 = b6 = s6 = Math.NaN;
		c7 = p7 = b7 = s7 = Math.NaN;
	}

	public function set(i:Int, code:Float, price:Float, bar:Float, status:Float):Void {
		switch (i) {
			case 0: c0 = code; p0 = price; b0 = bar; s0 = status;
			case 1: c1 = code; p1 = price; b1 = bar; s1 = status;
			case 2: c2 = code; p2 = price; b2 = bar; s2 = status;
			case 3: c3 = code; p3 = price; b3 = bar; s3 = status;
			case 4: c4 = code; p4 = price; b4 = bar; s4 = status;
			case 5: c5 = code; p5 = price; b5 = bar; s5 = status;
			case 6: c6 = code; p6 = price; b6 = bar; s6 = status;
			case 7: c7 = code; p7 = price; b7 = bar; s7 = status;
			default:
		}
	}
}

/** Forecast cone / band (price × time), always status=Projected. */
@:structInit
class ForecastBand {
	public var active:Float;
	public var priceLo:Float;
	public var priceHi:Float;
	public var barLo:Float;
	public var barHi:Float;
	public var status:Float;

	public static function nan():ForecastBand {
		return {
			active: 0, priceLo: Math.NaN, priceHi: Math.NaN,
			barLo: Math.NaN, barHi: Math.NaN, status: Math.NaN
		};
	}

	public function clear():Void {
		active = 0;
		priceLo = priceHi = barLo = barHi = status = Math.NaN;
	}

	public function set(priceLo:Float, priceHi:Float, barLo:Float, barHi:Float):Void {
		this.active = 1;
		this.priceLo = priceLo;
		this.priceHi = priceHi;
		this.barLo = barLo;
		this.barHi = barHi;
		this.status = (PivotStatus.Projected : Int) * 1.0;
	}
}

/**
 * Fib-style elliptical arcs (chart: cxBar/cyPrice/rBars/rPrice).
 * Fixed slots — no free-form arrays on the Haxe hot path.
 */
@:structInit
class ArcSet {
	public var count:Float;
	public var cx0:Float; public var cy0:Float; public var rb0:Float; public var rp0:Float; public var s0:Float; public var r0:Float;
	public var cx1:Float; public var cy1:Float; public var rb1:Float; public var rp1:Float; public var s1:Float; public var r1:Float;
	public var cx2:Float; public var cy2:Float; public var rb2:Float; public var rp2:Float; public var s2:Float; public var r2:Float;
	public var cx3:Float; public var cy3:Float; public var rb3:Float; public var rp3:Float; public var s3:Float; public var r3:Float;

	public static inline var CAP = 4;

	public static function nan():ArcSet {
		return {
			count: 0,
			cx0: Math.NaN, cy0: Math.NaN, rb0: Math.NaN, rp0: Math.NaN, s0: Math.NaN, r0: Math.NaN,
			cx1: Math.NaN, cy1: Math.NaN, rb1: Math.NaN, rp1: Math.NaN, s1: Math.NaN, r1: Math.NaN,
			cx2: Math.NaN, cy2: Math.NaN, rb2: Math.NaN, rp2: Math.NaN, s2: Math.NaN, r2: Math.NaN,
			cx3: Math.NaN, cy3: Math.NaN, rb3: Math.NaN, rp3: Math.NaN, s3: Math.NaN, r3: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		cx0 = cy0 = rb0 = rp0 = s0 = r0 = Math.NaN;
		cx1 = cy1 = rb1 = rp1 = s1 = r1 = Math.NaN;
		cx2 = cy2 = rb2 = rp2 = s2 = r2 = Math.NaN;
		cx3 = cy3 = rb3 = rp3 = s3 = r3 = Math.NaN;
	}

	public function set(i:Int, cx:Float, cy:Float, rBars:Float, rPrice:Float, status:Float, ratio:Float):Void {
		switch (i) {
			case 0: cx0 = cx; cy0 = cy; rb0 = rBars; rp0 = rPrice; s0 = status; r0 = ratio;
			case 1: cx1 = cx; cy1 = cy; rb1 = rBars; rp1 = rPrice; s1 = status; r1 = ratio;
			case 2: cx2 = cx; cy2 = cy; rb2 = rBars; rp2 = rPrice; s2 = status; r2 = ratio;
			case 3: cx3 = cx; cy3 = cy; rb3 = rBars; rp3 = rPrice; s3 = status; r3 = ratio;
			default:
		}
	}
}

/**
 * Square-of-Nine style price rings: one center + up to RING_PRICE horizontal levels.
 * Chart unpacks to `[{ centerPrice, prices:[...], status }]`.
 */
@:structInit
class RingBag {
	public var active:Float;
	public var center:Float;
	public var status:Float;
	public var count:Float;
	public var p0:Float; public var p1:Float; public var p2:Float; public var p3:Float;
	public var p4:Float; public var p5:Float; public var p6:Float; public var p7:Float;

	public static inline var CAP = 8;

	public static function nan():RingBag {
		return {
			active: 0, center: Math.NaN, status: Math.NaN, count: 0,
			p0: Math.NaN, p1: Math.NaN, p2: Math.NaN, p3: Math.NaN,
			p4: Math.NaN, p5: Math.NaN, p6: Math.NaN, p7: Math.NaN
		};
	}

	public function clear():Void {
		active = 0;
		center = status = count = Math.NaN;
		p0 = p1 = p2 = p3 = p4 = p5 = p6 = p7 = Math.NaN;
		count = 0;
	}

	public function setCenter(centerPrice:Float, status:Float):Void {
		this.active = 1;
		this.center = centerPrice;
		this.status = status;
	}

	public function setPrice(i:Int, price:Float):Void {
		switch (i) {
			case 0: p0 = price;
			case 1: p1 = price;
			case 2: p2 = price;
			case 3: p3 = price;
			case 4: p4 = price;
			case 5: p5 = price;
			case 6: p6 = price;
			case 7: p7 = price;
			default:
		}
	}
}

/**
 * Capped SSA / Fourier cycle overlay polyline (bar, price samples).
 * Avoids full-tape `values[]` on the Haxe / JIT hot path — chart unpacks to paint.
 */
@:structInit
class CycleSeries {
	public var count:Float;
	public var status:Float;
	public var cycleBars:Float;
	public var b0:Float; public var p0:Float;
	public var b1:Float; public var p1:Float;
	public var b2:Float; public var p2:Float;
	public var b3:Float; public var p3:Float;
	public var b4:Float; public var p4:Float;
	public var b5:Float; public var p5:Float;
	public var b6:Float; public var p6:Float;
	public var b7:Float; public var p7:Float;

	public static inline var CAP = 8;

	public static function nan():CycleSeries {
		return {
			count: 0, status: Math.NaN, cycleBars: Math.NaN,
			b0: Math.NaN, p0: Math.NaN, b1: Math.NaN, p1: Math.NaN,
			b2: Math.NaN, p2: Math.NaN, b3: Math.NaN, p3: Math.NaN,
			b4: Math.NaN, p4: Math.NaN, b5: Math.NaN, p5: Math.NaN,
			b6: Math.NaN, p6: Math.NaN, b7: Math.NaN, p7: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		status = cycleBars = Math.NaN;
		b0 = p0 = b1 = p1 = b2 = p2 = b3 = p3 = Math.NaN;
		b4 = p4 = b5 = p5 = b6 = p6 = b7 = p7 = Math.NaN;
	}

	public function set(i:Int, bar:Float, price:Float):Void {
		switch (i) {
			case 0: b0 = bar; p0 = price;
			case 1: b1 = bar; p1 = price;
			case 2: b2 = bar; p2 = price;
			case 3: b3 = bar; p3 = price;
			case 4: b4 = bar; p4 = price;
			case 5: b5 = bar; p5 = price;
			case 6: b6 = bar; p6 = price;
			case 7: b7 = bar; p7 = price;
			default:
		}
	}
}

/**
 * Capped LPPL risk-ribbon polyline (bar, ceiling-price samples).
 * Same shape cost rationale as CycleSeries / ArcSet / RingBag.
 */
@:structInit
class RibbonSeries {
	public var count:Float;
	public var status:Float;
	public var b0:Float; public var p0:Float;
	public var b1:Float; public var p1:Float;
	public var b2:Float; public var p2:Float;
	public var b3:Float; public var p3:Float;
	public var b4:Float; public var p4:Float;
	public var b5:Float; public var p5:Float;
	public var b6:Float; public var p6:Float;
	public var b7:Float; public var p7:Float;

	public static inline var CAP = 8;

	public static function nan():RibbonSeries {
		return {
			count: 0, status: Math.NaN,
			b0: Math.NaN, p0: Math.NaN, b1: Math.NaN, p1: Math.NaN,
			b2: Math.NaN, p2: Math.NaN, b3: Math.NaN, p3: Math.NaN,
			b4: Math.NaN, p4: Math.NaN, b5: Math.NaN, p5: Math.NaN,
			b6: Math.NaN, p6: Math.NaN, b7: Math.NaN, p7: Math.NaN
		};
	}

	public function clear():Void {
		count = 0;
		status = Math.NaN;
		b0 = p0 = b1 = p1 = b2 = p2 = b3 = p3 = Math.NaN;
		b4 = p4 = b5 = p5 = b6 = p6 = b7 = p7 = Math.NaN;
	}

	public function set(i:Int, bar:Float, price:Float):Void {
		switch (i) {
			case 0: b0 = bar; p0 = price;
			case 1: b1 = bar; p1 = price;
			case 2: b2 = bar; p2 = price;
			case 3: b3 = bar; p3 = price;
			case 4: b4 = bar; p4 = price;
			case 5: b5 = bar; p5 = price;
			case 6: b6 = bar; p6 = price;
			case 7: b7 = bar; p7 = price;
			default:
		}
	}
}

/**
 * Fill helpers — mutate pre-allocated sets (stable shapes).
 */
class GeomVizFill {
	public static function statusOf(p:PivotStatus):Float return (p : Int) * 1.0;

	/** Copy last `n` Confirmed pivots from SwingGraph into marks (newest last). */
	public static function pivotsFromGraph(g:SwingGraph, marks:PivotMarkSet, maxN:Int = 8):Void {
		marks.clear();
		var n = g.pivotCount();
		if (n <= 0) return;
		var take = n < maxN ? n : maxN;
		if (take > PivotMarkSet.CAP) take = PivotMarkSet.CAP;
		var start = n - take;
		for (i in 0...take) {
			var p = g.pivotAt(start + i);
			marks.set(i, p.price, p.direction, p.bar * 1.0, statusOf(p.status));
		}
		marks.count = take * 1.0;
		var f = g.forming();
		if (f != null && take < PivotMarkSet.CAP) {
			marks.set(take, f.price, f.direction, f.bar * 1.0, statusOf(PivotStatus.Forming));
			marks.count = (take + 1) * 1.0;
		}
	}

	/** Fill LevelSet from parallel price/ratio arrays (indexed). */
	public static function levels(prices:haxe.ds.Vector<Float>, ratios:haxe.ds.Vector<Float>, n:Int, status:Float, out:LevelSet):Void {
		out.clear();
		var take = n < LevelSet.CAP ? n : LevelSet.CAP;
		for (i in 0...take) out.set(i, prices[i], ratios[i], status);
		out.count = take * 1.0;
	}

	public static function levelsFromPairs(pairs:Array<{price:Float, ratio:Float}>, status:Float, out:LevelSet):Void {
		out.clear();
		var take = pairs.length < LevelSet.CAP ? pairs.length : LevelSet.CAP;
		for (i in 0...take) out.set(i, pairs[i].price, pairs[i].ratio, status);
		out.count = take * 1.0;
	}

	/** XABCD labels on last five pivots. */
	public static function xabcdLabels(g:SwingGraph, labels:LabelSet):Void {
		labels.clear();
		if (g.pivotCount() < 5) return;
		var n = g.pivotCount();
		var codes = [GeomLabelCode.X, GeomLabelCode.A, GeomLabelCode.B, GeomLabelCode.C, GeomLabelCode.D];
		for (i in 0...5) {
			var p = g.pivotAt(n - 5 + i);
			labels.set(i, (codes[i] : Int) * 1.0, p.price, p.bar * 1.0, statusOf(p.status));
		}
		labels.count = 5;
	}
}

/** MuseType helpers for IndicatorSpec nested viz fragments. */
class GeomVizSpec {
	public static function levelFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar},
			{name: "p0", ty: TScalar}, {name: "r0", ty: TScalar}, {name: "s0", ty: TScalar},
			{name: "p1", ty: TScalar}, {name: "r1", ty: TScalar}, {name: "s1", ty: TScalar},
			{name: "p2", ty: TScalar}, {name: "r2", ty: TScalar}, {name: "s2", ty: TScalar},
			{name: "p3", ty: TScalar}, {name: "r3", ty: TScalar}, {name: "s3", ty: TScalar},
			{name: "p4", ty: TScalar}, {name: "r4", ty: TScalar}, {name: "s4", ty: TScalar},
			{name: "p5", ty: TScalar}, {name: "r5", ty: TScalar}, {name: "s5", ty: TScalar},
			{name: "p6", ty: TScalar}, {name: "r6", ty: TScalar}, {name: "s6", ty: TScalar},
			{name: "p7", ty: TScalar}, {name: "r7", ty: TScalar}, {name: "s7", ty: TScalar}
		];
	}

	public static function rayFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar},
			{name: "y0_0", ty: TScalar}, {name: "y1_0", ty: TScalar}, {name: "b0_0", ty: TScalar}, {name: "b1_0", ty: TScalar}, {name: "s0", ty: TScalar},
			{name: "y0_1", ty: TScalar}, {name: "y1_1", ty: TScalar}, {name: "b0_1", ty: TScalar}, {name: "b1_1", ty: TScalar}, {name: "s1", ty: TScalar},
			{name: "y0_2", ty: TScalar}, {name: "y1_2", ty: TScalar}, {name: "b0_2", ty: TScalar}, {name: "b1_2", ty: TScalar}, {name: "s2", ty: TScalar},
			{name: "y0_3", ty: TScalar}, {name: "y1_3", ty: TScalar}, {name: "b0_3", ty: TScalar}, {name: "b1_3", ty: TScalar}, {name: "s3", ty: TScalar},
			{name: "y0_4", ty: TScalar}, {name: "y1_4", ty: TScalar}, {name: "b0_4", ty: TScalar}, {name: "b1_4", ty: TScalar}, {name: "s4", ty: TScalar},
			{name: "y0_5", ty: TScalar}, {name: "y1_5", ty: TScalar}, {name: "b0_5", ty: TScalar}, {name: "b1_5", ty: TScalar}, {name: "s5", ty: TScalar}
		];
	}

	public static function zoneFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar},
			{name: "lo0", ty: TScalar}, {name: "hi0", ty: TScalar}, {name: "b0_0", ty: TScalar}, {name: "b1_0", ty: TScalar}, {name: "s0", ty: TScalar}, {name: "k0", ty: TScalar},
			{name: "lo1", ty: TScalar}, {name: "hi1", ty: TScalar}, {name: "b0_1", ty: TScalar}, {name: "b1_1", ty: TScalar}, {name: "s1", ty: TScalar}, {name: "k1", ty: TScalar},
			{name: "lo2", ty: TScalar}, {name: "hi2", ty: TScalar}, {name: "b0_2", ty: TScalar}, {name: "b1_2", ty: TScalar}, {name: "s2", ty: TScalar}, {name: "k2", ty: TScalar},
			{name: "lo3", ty: TScalar}, {name: "hi3", ty: TScalar}, {name: "b0_3", ty: TScalar}, {name: "b1_3", ty: TScalar}, {name: "s3", ty: TScalar}, {name: "k3", ty: TScalar}
		];
	}

	public static function pivotFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar},
			{name: "p0", ty: TScalar}, {name: "d0", ty: TScalar}, {name: "b0", ty: TScalar}, {name: "s0", ty: TScalar},
			{name: "p1", ty: TScalar}, {name: "d1", ty: TScalar}, {name: "b1", ty: TScalar}, {name: "s1", ty: TScalar},
			{name: "p2", ty: TScalar}, {name: "d2", ty: TScalar}, {name: "b2", ty: TScalar}, {name: "s2", ty: TScalar},
			{name: "p3", ty: TScalar}, {name: "d3", ty: TScalar}, {name: "b3", ty: TScalar}, {name: "s3", ty: TScalar},
			{name: "p4", ty: TScalar}, {name: "d4", ty: TScalar}, {name: "b4", ty: TScalar}, {name: "s4", ty: TScalar},
			{name: "p5", ty: TScalar}, {name: "d5", ty: TScalar}, {name: "b5", ty: TScalar}, {name: "s5", ty: TScalar},
			{name: "p6", ty: TScalar}, {name: "d6", ty: TScalar}, {name: "b6", ty: TScalar}, {name: "s6", ty: TScalar},
			{name: "p7", ty: TScalar}, {name: "d7", ty: TScalar}, {name: "b7", ty: TScalar}, {name: "s7", ty: TScalar}
		];
	}

	public static function labelFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar},
			{name: "c0", ty: TScalar}, {name: "p0", ty: TScalar}, {name: "b0", ty: TScalar}, {name: "s0", ty: TScalar},
			{name: "c1", ty: TScalar}, {name: "p1", ty: TScalar}, {name: "b1", ty: TScalar}, {name: "s1", ty: TScalar},
			{name: "c2", ty: TScalar}, {name: "p2", ty: TScalar}, {name: "b2", ty: TScalar}, {name: "s2", ty: TScalar},
			{name: "c3", ty: TScalar}, {name: "p3", ty: TScalar}, {name: "b3", ty: TScalar}, {name: "s3", ty: TScalar},
			{name: "c4", ty: TScalar}, {name: "p4", ty: TScalar}, {name: "b4", ty: TScalar}, {name: "s4", ty: TScalar},
			{name: "c5", ty: TScalar}, {name: "p5", ty: TScalar}, {name: "b5", ty: TScalar}, {name: "s5", ty: TScalar},
			{name: "c6", ty: TScalar}, {name: "p6", ty: TScalar}, {name: "b6", ty: TScalar}, {name: "s6", ty: TScalar},
			{name: "c7", ty: TScalar}, {name: "p7", ty: TScalar}, {name: "b7", ty: TScalar}, {name: "s7", ty: TScalar}
		];
	}

	public static function forecastFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "active", ty: TScalar}, {name: "priceLo", ty: TScalar}, {name: "priceHi", ty: TScalar},
			{name: "barLo", ty: TScalar}, {name: "barHi", ty: TScalar}, {name: "status", ty: TScalar}
		];
	}

	public static function arcFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar},
			{name: "cx0", ty: TScalar}, {name: "cy0", ty: TScalar}, {name: "rb0", ty: TScalar}, {name: "rp0", ty: TScalar}, {name: "s0", ty: TScalar}, {name: "r0", ty: TScalar},
			{name: "cx1", ty: TScalar}, {name: "cy1", ty: TScalar}, {name: "rb1", ty: TScalar}, {name: "rp1", ty: TScalar}, {name: "s1", ty: TScalar}, {name: "r1", ty: TScalar},
			{name: "cx2", ty: TScalar}, {name: "cy2", ty: TScalar}, {name: "rb2", ty: TScalar}, {name: "rp2", ty: TScalar}, {name: "s2", ty: TScalar}, {name: "r2", ty: TScalar},
			{name: "cx3", ty: TScalar}, {name: "cy3", ty: TScalar}, {name: "rb3", ty: TScalar}, {name: "rp3", ty: TScalar}, {name: "s3", ty: TScalar}, {name: "r3", ty: TScalar}
		];
	}

	public static function ringFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "active", ty: TScalar}, {name: "center", ty: TScalar}, {name: "status", ty: TScalar}, {name: "count", ty: TScalar},
			{name: "p0", ty: TScalar}, {name: "p1", ty: TScalar}, {name: "p2", ty: TScalar}, {name: "p3", ty: TScalar},
			{name: "p4", ty: TScalar}, {name: "p5", ty: TScalar}, {name: "p6", ty: TScalar}, {name: "p7", ty: TScalar}
		];
	}

	public static function cycleFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar}, {name: "status", ty: TScalar}, {name: "cycleBars", ty: TScalar},
			{name: "b0", ty: TScalar}, {name: "p0", ty: TScalar},
			{name: "b1", ty: TScalar}, {name: "p1", ty: TScalar},
			{name: "b2", ty: TScalar}, {name: "p2", ty: TScalar},
			{name: "b3", ty: TScalar}, {name: "p3", ty: TScalar},
			{name: "b4", ty: TScalar}, {name: "p4", ty: TScalar},
			{name: "b5", ty: TScalar}, {name: "p5", ty: TScalar},
			{name: "b6", ty: TScalar}, {name: "p6", ty: TScalar},
			{name: "b7", ty: TScalar}, {name: "p7", ty: TScalar}
		];
	}

	public static function ribbonFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "count", ty: TScalar}, {name: "status", ty: TScalar},
			{name: "b0", ty: TScalar}, {name: "p0", ty: TScalar},
			{name: "b1", ty: TScalar}, {name: "p1", ty: TScalar},
			{name: "b2", ty: TScalar}, {name: "p2", ty: TScalar},
			{name: "b3", ty: TScalar}, {name: "p3", ty: TScalar},
			{name: "b4", ty: TScalar}, {name: "p4", ty: TScalar},
			{name: "b5", ty: TScalar}, {name: "p5", ty: TScalar},
			{name: "b6", ty: TScalar}, {name: "p6", ty: TScalar},
			{name: "b7", ty: TScalar}, {name: "p7", ty: TScalar}
		];
	}

	public static function levelObj():MuseType return TObject(levelFields());
	public static function rayObj():MuseType return TObject(rayFields());
	public static function zoneObj():MuseType return TObject(zoneFields());
	public static function pivotObj():MuseType return TObject(pivotFields());
	public static function labelObj():MuseType return TObject(labelFields());
	public static function forecastObj():MuseType return TObject(forecastFields());
	public static function arcObj():MuseType return TObject(arcFields());
	public static function ringObj():MuseType return TObject(ringFields());
	public static function cycleObj():MuseType return TObject(cycleFields());
	public static function ribbonObj():MuseType return TObject(ribbonFields());
}

/** Module anchor — `import musescript.indicators.geom.GeomViz` pulls viz set types. */
class GeomViz {}

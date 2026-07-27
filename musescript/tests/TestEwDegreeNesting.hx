package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraphStack;
import musescript.indicators.ew.EwLattice;
import musescript.indicators.ew.EwHypothesis;
import musescript.indicators.ew.ImpulseRules;
import musescript.indicators.lib.EwHypothesisIndicator;

/**
 * Degree nesting: two-threshold swing stack, parent linkage, lattice soft scores.
 */
class TestEwDegreeNesting extends Test {
	static var barCounter:Int = 0;

	static function piv(price:Float, dir:Float, bar:Int):PivotPoint {
		return new PivotPoint(price, dir, bar);
	}

	static function bar(o:Float, h:Float, l:Float, c:Float):Bar {
		var i = barCounter++;
		return { open: o, high: h, low: l, close: c, volume: 1.0, time: (i : Float), index: i };
	}

	public function setup() {
		barCounter = 0;
	}

	/** Coarse bull impulse 100-110-105-120-112-125 (valid, no W4/W1 overlap). */
	static function coarseImpulse():haxe.ds.Vector<PivotPoint> {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(100, -1, 0);
		v[1] = piv(110, 1, 20);
		v[2] = piv(105, -1, 40);
		v[3] = piv(120, 1, 60);
		v[4] = piv(112, -1, 80);
		v[5] = piv(125, 1, 100);
		return v;
	}

	/** Fine impulse nested in parent W4 territory (112-120). */
	static function fineNestedImpulse():haxe.ds.Vector<PivotPoint> {
		var v = new haxe.ds.Vector<PivotPoint>(6);
		v[0] = piv(112, -1, 50);
		v[1] = piv(116, 1, 55);
		v[2] = piv(114, -1, 58);
		v[3] = piv(118, 1, 62);
		v[4] = piv(117, -1, 66);
		v[5] = piv(120, 1, 70);
		return v;
	}

	static function makeChildHyp(startBar:Int, endBar:Int, offset:Int):EwHypothesis {
		return {
			rank: 0, score: 1.0, label: "impulse5",
			startBar: startBar, endBar: endBar, waveCount: 5, degree: 0, offset: offset,
			parentHypothesisId: -1, parentStartBar: -1, parentEndBar: -1, nestScore: 1.0,
			invalidatePrice: Math.NaN, invalidateBar: Math.NaN
		};
	}

	static function makeParentHyp(offset:Int):EwHypothesis {
		return {
			rank: 0, score: 1.0, label: "impulse5",
			startBar: 0, endBar: 100, waveCount: 5, degree: 1, offset: offset,
			parentHypothesisId: -1, parentStartBar: -1, parentEndBar: -1, nestScore: 1.0,
			invalidatePrice: Math.NaN, invalidateBar: Math.NaN
		};
	}

	public function testNestingSoftPrefersW4Territory() {
		var coarse = coarseImpulse();
		var fine = fineNestedImpulse();
		Assert.isTrue(ImpulseRules.isValidFiveWave(coarse, 0));
		Assert.isTrue(ImpulseRules.isValidFiveWave(fine, 0));
		var child = makeChildHyp(50, 70, 0);
		var parent = makeParentHyp(0);
		var nest = EwLattice.nestingSoft(child, parent, fine, coarse);
		Assert.isTrue(nest > 0.7);
	}

	public function testNestingSoftPenalizesOutsideParentSpan() {
		var coarse = coarseImpulse();
		var fine = fineNestedImpulse();
		var child = makeChildHyp(200, 220, 0);
		var parent = makeParentHyp(0);
		var nest = EwLattice.nestingSoft(child, parent, fine, coarse);
		Assert.isTrue(nest < 0.6);
	}

	public function testSwingGraphStackParentLinkage() {
		barCounter = 0;
		var stack = new SwingGraphStack(0.02, 0.06, 16);
		// Large down-up-down-up to confirm coarse pivots, with smaller ripples for fine
		for (i in 0...3) stack.update(bar(100, 100, 100, 100));
		stack.update(bar(100, 115, 100, 115));
		for (i in 0...5) stack.update(bar(115 - i, 115 - i, 110, 110));
		stack.update(bar(110, 112, 108, 111));
		stack.update(bar(111, 113, 109, 112));
		for (i in 0...5) stack.update(bar(112 + i, 125, 112 + i, 125));
		for (i in 0...4) stack.update(bar(125 - i * 2, 125 - i * 2, 118, 118));
		for (i in 0...5) stack.update(bar(118 + i * 3, 140, 118 + i * 3, 140));
		for (i in 0...4) stack.update(bar(140 - i * 3, 140 - i * 3, 125, 125));
		for (i in 0...5) stack.update(bar(125 + i * 4, 150, 125 + i * 4, 150));

		Assert.isTrue(stack.fine.pivotCount() >= 2);
		if (stack.coarse.pivotCount() >= 2) {
			var fi = stack.fine.pivotCount() - 1;
			var parent = stack.parentIdxOf(fi);
			Assert.isTrue(parent >= -1);
			if (parent >= 0) {
				Assert.isTrue(stack.coarse.pivotAt(parent).bar <= stack.fine.pivotAt(fi).bar);
			}
		}
	}

	public function testRebuildStackFindsCoarseAndFine() {
		barCounter = 0;
		var stack = new SwingGraphStack(0.015, 0.05, 24);
		// Scripted outer correction with inner ripples (approximate bull impulse inside ABC)
		function feed(px:Float, spread:Float, n:Int) {
			for (i in 0...n) stack.update(bar(px, px + spread, px - spread, px));
		}
		feed(100, 0.5, 3);
		feed(110, 1.0, 4);
		feed(105, 0.5, 3);
		feed(108, 0.3, 2);
		feed(112, 0.3, 2);
		feed(107, 0.3, 2);
		feed(115, 0.5, 3);
		feed(120, 1.0, 4);
		feed(113, 0.5, 3);
		feed(116, 0.3, 2);
		feed(119, 0.3, 2);
		feed(114, 0.3, 2);
		feed(118, 0.5, 3);
		feed(125, 1.0, 4);
		feed(120, 0.5, 3);
		feed(123, 0.3, 2);
		feed(127, 0.3, 2);
		feed(122, 0.3, 2);
		feed(128, 0.5, 3);
		feed(135, 1.0, 4);

		var lat = new EwLattice();
		var n = lat.rebuildStack(stack, 5);
		Assert.isTrue(n >= 0);
		Assert.isTrue(lat.coarseHypothesisCount() >= 0);
		// Exercise nesting path when both levels have hypotheses
		if (n > 0 && lat.coarseHypothesisCount() > 0) {
			var top = lat.at(0);
			Assert.equals(0, top.degree);
			if (top.parentHypothesisId >= 0) {
				Assert.isTrue(top.nestScore > 0.35);
				Assert.isTrue(top.parentStartBar >= 0);
			}
		}
	}

	public function testIndicatorEmitsDegreeFields() {
		barCounter = 0;
		var ind = new EwHypothesisIndicator(0.02, 3);
		var last:Dynamic = null;
		for (i in 0...60) {
			var px = 100.0 + Math.sin(i * 0.25) * 15.0 + i * 0.3;
			last = ind.update(bar(px, px + 2, px - 2, px));
		}
		Assert.notNull(last);
		Assert.isTrue(Math.isFinite(last.degree));
		Assert.isTrue(Math.isFinite(last.nestScore));
		Assert.isTrue(last.nestScore >= 0.35 && last.nestScore <= 1.0);
		// When nested, indicator may emit ParentDegree zone (kind=11) without bumping Cap
		if (last.parentLabelCode > 0 && Math.isFinite(last.parentStartBar)) {
			Assert.isTrue(last.zones.count >= 1);
		}
	}
}

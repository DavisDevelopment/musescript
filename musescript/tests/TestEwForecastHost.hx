package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.ew.EwForecastHost;
import musescript.ew.LatticeForecastHost;
import musescript.indicators.ew.ImpulseRules;
import musescript.indicators.geom.PivotPoint;
import musescript.indicators.geom.SwingGraph;

/**
 * LatticeForecastHost adapter: synthetic pivots → ForecastCloud with finite band
 * + invalidate when an impulse is found.
 */
class TestEwForecastHost extends Test {
	static function piv(price:Float, dir:Float, bar:Int):PivotPoint {
		return new PivotPoint(price, dir, bar);
	}

	/** Classic bull impulse: 100-110-105-120-112-125 */
	static function bullImpulse():Array<PivotPoint> {
		return [
			piv(100, -1, 0),
			piv(110, 1, 10),
			piv(105, -1, 20),
			piv(120, 1, 30),
			piv(112, -1, 40),
			piv(125, 1, 50)
		];
	}

	public function testCloudFromSeededImpulse() {
		var g = new SwingGraph(0.02, 16);
		g.seedConfirmed(bullImpulse(), 51);
		var v = new haxe.ds.Vector<PivotPoint>(6);
		var arr = bullImpulse();
		for (i in 0...6) v[i] = arr[i];
		Assert.isTrue(ImpulseRules.isValidFiveWave(v, 0));

		var host:EwForecastHost = LatticeForecastHost.withGraph(g, null, 5);
		var cloud = host.cloudAt(50);

		Assert.isTrue(cloud.samples >= 1);
		Assert.isTrue(Math.isFinite(cloud.priceLo));
		Assert.isTrue(Math.isFinite(cloud.priceHi));
		Assert.isTrue(cloud.priceHi >= cloud.priceLo);
		Assert.isTrue(Math.isFinite(cloud.priceMid));
		Assert.isTrue(Math.isFinite(cloud.spread));
		Assert.isTrue(Math.isFinite(cloud.invalidatePrice));
		// Motive invalidate = W1 origin
		Assert.floatEquals(100.0, cloud.invalidatePrice, 1e-9);
		Assert.isTrue(cloud.topMass > 0 && cloud.topMass <= 1.0);
		Assert.isTrue(cloud.labelCode != 0);

		var counts = host.topCounts(50, 5);
		Assert.isTrue(counts.length >= 1);
		Assert.isTrue(ImpulseRules.isImpulseFamily(counts[0].label)
			|| ImpulseRules.isDiagonalFamily(counts[0].label)
			|| counts[0].label == "zigzag"
			|| counts[0].label.indexOf("flat") == 0
			|| counts[0].label.indexOf("triangle") == 0
			|| counts[0].label.indexOf("double") == 0);
		// Never invent unknown as a preferred count when lattice found structure
		Assert.notEquals("unknown", counts[0].label);
	}

	public function testEmptyWhenTooFewPivots() {
		var g = new SwingGraph(0.02, 8);
		g.seedConfirmed([piv(100, -1, 0), piv(110, 1, 5)], 6);
		var host = LatticeForecastHost.withGraph(g);
		var cloud = host.cloudAt(5);
		Assert.equals(0, cloud.samples);
		Assert.isTrue(Math.isNaN(cloud.priceLo));
		Assert.equals(0, host.topCounts(5, 3).length);
	}

	public function testSamplesOnePath() {
		var g = new SwingGraph(0.02, 16);
		g.seedConfirmed(bullImpulse(), 51);
		var host = LatticeForecastHost.withGraph(g, null, 1);
		var cloud = host.cloudAt(50);
		Assert.equals(1, host.topK());
		Assert.isTrue(cloud.samples >= 1);
		Assert.floatEquals(0.0, cloud.countEntropy, 1e-12);
		Assert.floatEquals(1.0, cloud.topMass, 1e-9);
	}
}

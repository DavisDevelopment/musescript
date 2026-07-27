package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.IntPairMap;
import musescript.evo.nma.NmaColumnCache;
import musescript.indicators.GrowableVec;

class TestIntPairMap extends Test {
	public function testGetSetRoundTrip() {
		var m = new IntPairMap<String>();
		m.set(1, 2, "x");
		Assert.equals("x", m.get(1, 2));
		Assert.isNull(m.get(1, 3));
	}

	public function testExistsAndSize() {
		var m = new IntPairMap<Int>();
		Assert.isFalse(m.exists(0, 0));
		Assert.equals(0, m.size());
		m.set(10, 20, 99);
		Assert.isTrue(m.exists(10, 20));
		Assert.equals(1, m.size());
		m.set(10, 20, 100);
		Assert.equals(1, m.size());
		Assert.equals(100, m.get(10, 20));
	}

	public function testZeroAndNegativeKeys() {
		var m = new IntPairMap<String>();
		m.set(0, 0, "origin");
		m.set(-1, -1, "neg");
		Assert.equals("origin", m.get(0, 0));
		Assert.equals("neg", m.get(-1, -1));
		Assert.equals(2, m.size());
	}

	public function testResizeUnderCollisions() {
		var m = new IntPairMap<Int>(4);
		for (i in 0...64) m.set(i, i * 31, i);
		for (i in 0...64) Assert.equals(i, m.get(i, i * 31));
		Assert.equals(64, m.size());
	}

	public function testNmaColumnCacheWordsPath() {
		var cache = new NmaColumnCache();
		var col = new GrowableVec<Float>();
		col.push(1.5);
		col.push(2.5);
		Assert.isNull(cache.getWords(7, 13));
		cache.putWords(7, 13, col);
		var hit = cache.getWords(7, 13);
		Assert.notNull(hit);
		Assert.equals(2, hit.length);
		Assert.floatEquals(1.5, hit[0]);
		Assert.floatEquals(2.5, hit[1]);
		Assert.equals(1, cache.size());
		Assert.floatEquals(2, cache.cells());
	}
}

package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.IntPairList;
import musescript.evo.StructuralDigest;

class TestIntPairList extends Test {
	public function testEmptyList() {
		var l = new IntPairList();
		Assert.equals(0, l.length);
		Assert.equals(-1, l.indexOfPair(0, 0));
		Assert.isFalse(l.containsPair(0, 0));
	}

	public function testPushReadRoundTrip() {
		var l = new IntPairList();
		l.push(1, 2);
		l.push(3, 4);
		l.push(5, 6);
		Assert.equals(3, l.length);
		Assert.equals(1, l.a(0));
		Assert.equals(2, l.b(0));
		Assert.equals(3, l.a(1));
		Assert.equals(4, l.b(1));
		Assert.equals(5, l.a(2));
		Assert.equals(6, l.b(2));
	}

	public function testGrowthAcrossReallocations() {
		var l = new IntPairList(2);
		for (i in 0...1000) l.push(i, -i);
		Assert.equals(1000, l.length);
		var ok = true;
		var i = 0;
		while (i < 1000) {
			if (l.a(i) != i || l.b(i) != -i) ok = false;
			i++;
		}
		Assert.isTrue(ok);
		Assert.equals(999, l.a(999));
		Assert.equals(-999, l.b(999));
	}

	public function testExtremeAndNegativeLanes() {
		var l = new IntPairList(1);
		l.push(0, 0);
		l.push(-1, 1);
		l.push(0x7fffffff, -2147483648);
		l.push(-2147483648, 0x7fffffff);
		Assert.equals(4, l.length);
		Assert.equals(0, l.a(0));
		Assert.equals(0, l.b(0));
		Assert.equals(-1, l.a(1));
		Assert.equals(1, l.b(1));
		Assert.equals(0x7fffffff, l.a(2));
		Assert.equals(-2147483648, l.b(2));
		Assert.equals(-2147483648, l.a(3));
		Assert.equals(0x7fffffff, l.b(3));
		Assert.isTrue(l.containsPair(0x7fffffff, -2147483648));
		Assert.isTrue(l.containsPair(-2147483648, 0x7fffffff));
	}

	public function testClearThenReuse() {
		var l = new IntPairList(4);
		l.push(7, 8);
		l.push(9, 10);
		l.clear();
		Assert.equals(0, l.length);
		Assert.isFalse(l.containsPair(7, 8));
		l.push(11, 12);
		Assert.equals(1, l.length);
		Assert.equals(11, l.a(0));
		Assert.equals(12, l.b(0));
	}

	public function testIndexOfAndContains() {
		var l = new IntPairList();
		l.push(1, 2);
		l.push(3, 4);
		l.push(0, 0);
		Assert.equals(0, l.indexOfPair(1, 2));
		Assert.equals(1, l.indexOfPair(3, 4));
		Assert.equals(2, l.indexOfPair(0, 0));
		Assert.equals(-1, l.indexOfPair(5, 6));
		Assert.isTrue(l.containsPair(3, 4));
		Assert.isFalse(l.containsPair(3, 5));
		// Ordered pairs: (a,b) is not (b,a).
		Assert.equals(-1, l.indexOfPair(2, 1));
		Assert.isFalse(l.containsPair(4, 3));
	}

	public function testCopyIndependence() {
		var l = new IntPairList(2);
		l.push(1, 2);
		l.push(3, 4);
		var c = l.copy();
		Assert.equals(2, c.length);
		Assert.equals(1, c.a(0));
		Assert.equals(4, c.b(1));
		c.push(5, 6);
		Assert.equals(3, c.length);
		Assert.equals(2, l.length);
		Assert.isFalse(l.containsPair(5, 6));
		c.clear();
		Assert.equals(0, c.length);
		Assert.equals(2, l.length);
		Assert.equals(3, l.a(1));
	}

	public function testToString() {
		var l = new IntPairList();
		l.push(1, 2);
		l.push(3, 4);
		Assert.equals("IntPairList[2: (1,2) (3,4)]", l.toString());
	}

	public function testStructuralDigestResetMatchesFreshInstance() {
		var reused = new StructuralDigest();
		// Sequence X.
		reused.tag(3).int(-7).str("alpha").float(1.5);
		reused.finishWords();
		reused.reset();
		// Sequence Y on the same instance.
		reused.tag(9).int(0x7fffffff).str("beta").float(-0.0);
		reused.finishWords();

		var fresh = new StructuralDigest();
		fresh.tag(9).int(0x7fffffff).str("beta").float(-0.0);
		fresh.finishWords();

		Assert.equals(fresh.outA, reused.outA);
		Assert.equals(fresh.outB, reused.outB);
	}

	public function testStructuralDigestResetReproducesSameInput() {
		var d = new StructuralDigest();
		d.tag(1).str("gamma").int(-2147483648);
		d.finishWords();
		var a0 = d.outA;
		var b0 = d.outB;

		d.reset();
		Assert.equals(0, d.outA);
		Assert.equals(0, d.outB);

		d.tag(1).str("gamma").int(-2147483648);
		d.finishWords();
		Assert.equals(a0, d.outA);
		Assert.equals(b0, d.outB);
	}
}

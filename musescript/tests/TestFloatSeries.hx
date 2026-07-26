package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.FloatSeries;

class TestFloatSeries extends Test {
	static function seriesValues(s:FloatSeries):Array<Float> {
		var out:Array<Float> = [];
		for (i in 0...s.length)
			out.push(s.at(i));
		return out;
	}

	public function testPushAndAtAbsoluteIndexing() {
		var s = new FloatSeries();
		s.push(1.0);
		s.push(2.5);
		s.push(3.0);
		Assert.equals(3, s.length);
		Assert.equals(1.0, s.at(0));
		Assert.equals(2.5, s.at(1));
		Assert.equals(3.0, s.at(2));
		Assert.same([1.0, 2.5, 3.0], seriesValues(s));
	}

	public function testAtAndSetAtIndexedAccess() {
		var s = new FloatSeries();
		s.push(10.0);
		s.push(20.0);
		Assert.equals(10.0, s.at(0));
		s.setAt(1, 99.0);
		Assert.equals(99.0, s.at(1));
	}

	public function testSetAtMutatesBackingStore() {
		var s = new FloatSeries();
		s.push(1.0);
		s.push(2.0);
		s.setAt(0, 42.0);
		Assert.equals(42.0, s.at(0));
		Assert.equals(2.0, s.at(1));
	}

	public function testFromArrayCopiesIntoOwnedVector() {
		var src = [1.0, 2.0, 3.0, 4.0];
		var s = FloatSeries.fromArray(src);
		Assert.isTrue(s.isOwned);
		Assert.equals(4, s.length);
		Assert.same([1.0, 2.0, 3.0, 4.0], seriesValues(s));
		src[0] = 999.0;
		Assert.equals(1.0, s.at(0));
	}

	public function testFromArrayVisiblePrefix() {
		var src = [1.0, 2.0, 3.0, 4.0];
		var s = FloatSeries.fromArray(src, 2);
		Assert.equals(2, s.length);
		Assert.same([1.0, 2.0], seriesValues(s));
	}

	public function testFromVectorAliasesWithoutCopy() {
		var tape = new haxe.ds.Vector<Float>(4);
		tape[0] = 1.0;
		tape[1] = 2.0;
		tape[2] = 3.0;
		tape[3] = 4.0;
		var s = FloatSeries.fromVector(tape, 2);
		Assert.isFalse(s.isOwned);
		Assert.equals(2, s.length);
		Assert.equals(4, s.backingLength);
		tape[1] = 99.0;
		Assert.equals(99.0, s.at(1));
	}

	public function testLengthSetterExpandsVisiblePrefixOnAliasedView() {
		var tape = new haxe.ds.Vector<Float>(3);
		tape[0] = 10.0;
		tape[1] = 20.0;
		tape[2] = 30.0;
		var s = FloatSeries.fromVector(tape, 1);
		Assert.equals(10.0, s.at(0));
		s.length = 2;
		Assert.equals(20.0, s.at(1));
		s.length = 3;
		Assert.same([10.0, 20.0, 30.0], seriesValues(s));
	}

	public function testLengthSetterTruncatesVisiblePrefix() {
		var s = new FloatSeries();
		s.push(1.0);
		s.push(2.0);
		s.push(3.0);
		s.length = 1;
		Assert.equals(1, s.length);
		Assert.equals(1.0, s.at(0));
		s.length = 3;
		Assert.equals(3.0, s.at(2));
	}

	public function testPushOnAliasedViewThrows() {
		var tape = new haxe.ds.Vector<Float>(1);
		var s = FloatSeries.fromVector(tape, 0);
		var threw = false;
		try {
			s.push(1.0);
		} catch (_:Dynamic) {
			threw = true;
		}
		Assert.isTrue(threw);
	}
}

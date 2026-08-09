package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.SortedWindow;

/**
 * SortedWindow must match full-window sort outputs bit-for-bit on order stats,
 * and keep ring chronology identical to the plain Array + shift pattern.
 */
class TestSortedWindow extends Test {
	static function assertSameSorted(sw:SortedWindow, values:Array<Float>) {
		var expected = values.copy();
		expected.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		Assert.same(expected, sw.sorted);
	}

	public function testInsertMaintainsAscendingOrder() {
		var sw = new SortedWindow(5);
		for (v in [3.0, 1.0, 4.0, 1.5, 2.0]) sw.push(v);
		assertSameSorted(sw, [3.0, 1.0, 4.0, 1.5, 2.0]);
		Assert.equals(5, sw.length);
		Assert.isTrue(sw.isFull());
	}

	public function testEvictionRemovesOldestFromSorted() {
		var sw = new SortedWindow(3);
		Assert.isNull(sw.push(10));
		Assert.isNull(sw.push(1));
		Assert.isNull(sw.push(5));
		Assert.floatEquals(10.0, sw.push(7), "first eviction is the oldest chronological value");
		assertSameSorted(sw, [1.0, 5.0, 7.0]);
		Assert.floatEquals(1.0, sw.oldest(0));
		Assert.floatEquals(7.0, sw.oldest(2));
	}

	public function testDuplicateValuesEvictCorrectly() {
		var sw = new SortedWindow(3);
		for (v in [2.0, 2.0, 2.0]) sw.push(v);
		Assert.floatEquals(2.0, sw.push(2.0));
		assertSameSorted(sw, [2.0, 2.0, 2.0]);
		Assert.equals(3, sw.length);
	}

	public function testZeroValueEvictionDoesNotCorruptSorted() {
		// Regresses the JS Null<Float>/0.0 trap: eviction of exact 0 must still
		// remove from the sorted spine.
		var sw = new SortedWindow(2);
		sw.push(0.0);
		sw.push(1.0);
		sw.push(2.0); // evicts 0.0
		assertSameSorted(sw, [1.0, 2.0]);
		Assert.equals(2, sw.length);
	}

	public function testMedianOddAndEven() {
		var odd = new SortedWindow(5);
		for (v in [9.0, 1.0, 5.0, 3.0, 7.0]) odd.push(v);
		Assert.floatEquals(5.0, odd.median());

		var even = new SortedWindow(4);
		for (v in [4.0, 1.0, 3.0, 2.0]) even.push(v);
		Assert.floatEquals(2.5, even.median());
	}

	public function testQuantileMatchesFullSortType7() {
		var sw = new SortedWindow(6);
		var vals = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0];
		for (v in vals) sw.push(v);
		var sorted = vals.copy();
		sorted.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));
		for (q in [0.0, 0.25, 0.5, 0.75, 1.0]) {
			Assert.floatEquals(SortedWindow.quantileSorted(sorted, q), sw.quantile(q));
		}
	}

	public function testChronologicalIteratorOldestFirst() {
		var sw = new SortedWindow(4);
		for (v in [1.0, 2.0, 3.0, 4.0, 5.0]) sw.push(v);
		var seen = [];
		for (v in sw) seen.push(v);
		Assert.same([2.0, 3.0, 4.0, 5.0], seen);
	}

	public function testResetClearsBothSpines() {
		var sw = new SortedWindow(3);
		for (v in [1.0, 2.0, 3.0]) sw.push(v);
		sw.reset();
		Assert.equals(0, sw.length);
		Assert.same([], sw.sorted);
		sw.push(9.0);
		assertSameSorted(sw, [9.0]);
	}
}

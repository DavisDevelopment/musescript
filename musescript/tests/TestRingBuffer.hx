package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.indicators.RingBuffer;

/**
 * RingBuffer's ordering contract — pinned, because it is subtle enough to have already caused
 * a wrong bulk migration.
 *
 * `at(i)`/`buf[i]` count NEWEST-first while `iterator()` runs OLDEST-first, so the two access
 * paths traverse in opposite directions. That is deliberate (indexed access reads naturally as
 * "n bars ago"; iteration matches `for (v in plainArray)`), but it means a mechanical
 * `Array<Float>` → `RingBuffer<Float>` swap that leaves `window[i]` alone silently reverses the
 * window in time — with no compile error, because `@:arrayAccess` keeps `window[i]` valid.
 *
 * These tests exist so nobody "fixes" one direction and quietly breaks the other, and so the
 * `oldest(i)` migration helper keeps meaning what the migration needs it to mean.
 */
class TestRingBuffer extends Test {
	static function filled(capacity:Int, values:Array<Float>):RingBuffer<Float> {
		var rb = new RingBuffer<Float>(capacity);
		for (v in values) rb.push(v);
		return rb;
	}

	public function testIndexedAccessIsNewestFirst() {
		var rb = filled(4, [1, 2, 3, 4, 5, 6]); // retains 3,4,5,6
		Assert.equals(4, rb.length);
		Assert.floatEquals(6.0, rb.at(0), "at(0) must be the newest push");
		Assert.floatEquals(5.0, rb.at(1));
		Assert.floatEquals(4.0, rb.at(2));
		Assert.floatEquals(3.0, rb.at(3), "at(length-1) must be the oldest retained value");
	}

	public function testArrayAccessSugarMatchesAt() {
		var rb = filled(4, [1, 2, 3, 4, 5, 6]);
		for (i in 0...rb.length) Assert.floatEquals(rb.at(i), rb[i]);
	}

	public function testIteratorIsOldestFirst() {
		var rb = filled(4, [1, 2, 3, 4, 5, 6]);
		var seen = [];
		for (v in rb) seen.push(v);
		Assert.same([3.0, 4.0, 5.0, 6.0], seen,
			"iteration must match `for (v in plainArray)` order (oldest -> newest)");
	}

	public function testOldestIsTheArrayMigrationOrder() {
		// The whole point of `oldest(i)`: identical indexing to the Array window being replaced.
		var rb = filled(4, [1, 2, 3, 4, 5, 6]);
		Assert.floatEquals(3.0, rb.oldest(0), "oldest(0) must be the oldest retained value");
		Assert.floatEquals(4.0, rb.oldest(1));
		Assert.floatEquals(5.0, rb.oldest(2));
		Assert.floatEquals(6.0, rb.oldest(3), "oldest(length-1) must be the newest push");
	}

	public function testOldestMatchesIterationOrderExactly() {
		var rb = filled(5, [10, 20, 30, 40, 50, 60, 70]);
		var byIter = [];
		for (v in rb) byIter.push(v);
		var byOldest = [for (i in 0...rb.length) rb.oldest(i)];
		Assert.same(byIter, byOldest,
			"oldest(i) and iterator() must agree — both are the plain-Array order");
	}

	public function testOldestIsExactReverseOfAt() {
		var rb = filled(5, [10, 20, 30, 40, 50, 60, 70]);
		for (i in 0...rb.length) Assert.floatEquals(rb.at(rb.length - 1 - i), rb.oldest(i));
	}

	public function testPushEvictsOldestAndReportsIt() {
		var rb = new RingBuffer<Float>(3);
		Assert.isNull(rb.push(1), "nothing is evicted while the buffer is still filling");
		Assert.isNull(rb.push(2));
		Assert.isNull(rb.push(3));
		Assert.floatEquals(1.0, rb.push(4), "first eviction must be the oldest value");
		Assert.equals(3, rb.length, "length is capped at capacity");
	}

	public function testWhileFillingOrdersStillHold() {
		// Partially-filled buffers are the warmup case every indicator hits first.
		var rb = filled(4, [7, 8]);
		Assert.equals(2, rb.length);
		Assert.floatEquals(8.0, rb.at(0));
		Assert.floatEquals(7.0, rb.oldest(0));
		var seen = [];
		for (v in rb) seen.push(v);
		Assert.same([7.0, 8.0], seen);
	}

	public function testGenericImplHasTheSameOrdering() {
		// The @:multiType fallback (non-Float T) must not diverge from the Float fast path.
		var rb = new RingBuffer<String>(3);
		for (v in ["a", "b", "c", "d"]) rb.push(v);
		Assert.equals("d", rb.at(0));
		Assert.equals("b", rb.oldest(0));
		var seen = [];
		for (v in rb) seen.push(v);
		Assert.same(["b", "c", "d"], seen);
	}
}

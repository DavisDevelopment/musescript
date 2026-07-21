package musescript.tests.ports;

import utest.Assert;
import utest.Test;
import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorBatch;
import musescript.indicators.lib.LadderBottom;
import musescript.indicators.lib.PiercingDarkCloud;
import musescript.indicators.lib.RickshawMan;
import musescript.indicators.lib.RisingThreeMethods;
import musescript.indicators.lib.SeparatingLines;
import musescript.indicators.lib.ShootingStar;
import musescript.indicators.lib.ShortLine;
import musescript.indicators.lib.SpinningTop;
import musescript.indicators.lib.StalledPattern;
import musescript.indicators.lib.StickSandwich;
import musescript.indicators.lib.Takuri;
import musescript.indicators.lib.TasukiGap;
import musescript.indicators.lib.ThreeInside;
import musescript.indicators.lib.ThreeLineStrike;
import musescript.indicators.lib.ThreeOutside;
import musescript.indicators.lib.ThreeSoldiersOrCrows;

/**
 * Batch 37: 16 Tier-1 candlestick-pattern indicators ported from wickra-core.
 * Known-value cases transcribed directly from the Rust fixture blocks.
 * batch_equals_streaming verifies IndicatorBatch.run equals streaming updates.
 */
class TestPortBatch37 extends Test {
	static function c(o:Float, h:Float, l:Float, cl:Float, i:Int):Bar {
		return { open: o, high: h, low: l, close: cl, volume: 1.0, time: (i : Float), index: i };
	}

	static function assertBatchEqualsStreaming(a:MuseIndicator<Bar, Float>, b:MuseIndicator<Bar, Float>, bars:Array<Bar>) {
		var batched = IndicatorBatch.run(a, bars);
		var streamed = [for (x in bars) b.update(x)];
		Assert.equals(batched.length, streamed.length);
		for (i in 0...batched.length) {
			if (batched[i] == null) {
				Assert.isNull(streamed[i]);
			} else {
				Assert.floatEquals(batched[i], streamed[i]);
			}
		}
	}

	// ── LadderBottom ─────────────────────────────────────────────────────────

	public function testLadderBottomAccessorsAndMetadata() {
		var t = new LadderBottom();
		Assert.equals("LadderBottom", t.name());
		Assert.equals(5, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testLadderBottomIsPlusOne() {
		var t = new LadderBottom();
		Assert.floatEquals(0.0, t.update(c(20.0, 20.1, 17.9, 18.0, 0)));
		Assert.floatEquals(0.0, t.update(c(18.0, 18.1, 15.9, 16.0, 1)));
		Assert.floatEquals(0.0, t.update(c(16.0, 16.1, 13.9, 14.0, 2)));
		Assert.floatEquals(0.0, t.update(c(14.0, 15.0, 12.4, 12.5, 3)));
		Assert.floatEquals(1.0, t.update(c(15.0, 17.1, 14.9, 17.0, 4)));
	}

	public function testLadderBottomFourthBarWithoutUpperShadowYieldsZero() {
		var t = new LadderBottom();
		t.update(c(20.0, 20.1, 17.9, 18.0, 0));
		t.update(c(18.0, 18.1, 15.9, 16.0, 1));
		t.update(c(16.0, 16.1, 13.9, 14.0, 2));
		// bar4 opens at its high -> no upper shadow.
		t.update(c(14.0, 14.0, 12.4, 12.5, 3));
		Assert.floatEquals(0.0, t.update(c(15.0, 17.1, 14.9, 17.0, 4)));
	}

	public function testLadderBottomNotThreeDescendingBlacksYieldsZero() {
		var t = new LadderBottom();
		// bar2 is not lower than bar1.
		t.update(c(20.0, 20.1, 17.9, 18.0, 0));
		t.update(c(21.0, 21.1, 18.9, 19.0, 1));
		t.update(c(16.0, 16.1, 13.9, 14.0, 2));
		t.update(c(14.0, 15.0, 12.4, 12.5, 3));
		Assert.floatEquals(0.0, t.update(c(15.0, 17.1, 14.9, 17.0, 4)));
	}

	public function testLadderBottomFirstFourBarsReturnZero() {
		var t = new LadderBottom();
		Assert.floatEquals(0.0, t.update(c(20.0, 20.1, 17.9, 18.0, 0)));
		Assert.floatEquals(0.0, t.update(c(18.0, 18.1, 15.9, 16.0, 1)));
		Assert.floatEquals(0.0, t.update(c(16.0, 16.1, 13.9, 14.0, 2)));
		Assert.floatEquals(0.0, t.update(c(14.0, 15.0, 12.4, 12.5, 3)));
	}

	public function testLadderBottomBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 200.0 - i;
			c(base, base + 0.1, base - 2.1, base - 2.0, i);
		}];
		assertBatchEqualsStreaming(new LadderBottom(), new LadderBottom(), bars);
	}

	public function testLadderBottomResetClearsState() {
		var t = new LadderBottom();
		t.update(c(20.0, 20.1, 17.9, 18.0, 0));
		t.update(c(18.0, 18.1, 15.9, 16.0, 1));
		t.update(c(16.0, 16.1, 13.9, 14.0, 2));
		t.update(c(14.0, 15.0, 12.4, 12.5, 3));
		t.update(c(15.0, 17.1, 14.9, 17.0, 4));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(20.0, 20.1, 17.9, 18.0, 0)));
	}

	// ── PiercingDarkCloud ────────────────────────────────────────────────────

	public function testPiercingDarkCloudAccessorsAndMetadata() {
		var p = new PiercingDarkCloud();
		Assert.equals("PiercingDarkCloud", p.name());
		Assert.equals(2, p.warmupPeriod());
		Assert.isTrue(!p.isReady());
	}

	public function testPiercingLineIsPlusOne() {
		var p = new PiercingDarkCloud();
		// Prev red: open 12, close 10. Curr green: opens at 9.8 (< prev low 10),
		// closes at 11.5 (> midpoint 11, < prev open 12).
		Assert.floatEquals(0.0, p.update(c(12.0, 12.5, 10.0, 10.0, 0)));
		Assert.floatEquals(1.0, p.update(c(9.8, 11.8, 9.5, 11.5, 1)));
	}

	public function testDarkCloudCoverIsMinusOne() {
		var p = new PiercingDarkCloud();
		// Prev green: open 10, close 12. Curr red: opens 12.3 (> prev high 12.2),
		// closes 10.5 (< midpoint 11, > prev open 10).
		Assert.floatEquals(0.0, p.update(c(10.0, 12.2, 9.5, 12.0, 0)));
		Assert.floatEquals(-1.0, p.update(c(12.3, 12.4, 10.4, 10.5, 1)));
	}

	public function testPiercingCloseBelowMidpointIsNotPiercing() {
		var p = new PiercingDarkCloud();
		p.update(c(12.0, 12.5, 10.0, 10.0, 0));
		// Closes only at 10.8 (below midpoint 11) -> not piercing.
		Assert.floatEquals(0.0, p.update(c(9.8, 11.0, 9.5, 10.8, 1)));
	}

	public function testPiercingFullEngulfIsNotPiercing() {
		var p = new PiercingDarkCloud();
		p.update(c(12.0, 12.5, 10.0, 10.0, 0));
		// Closes above prev.open (12) -> engulfs, not piercing.
		Assert.floatEquals(0.0, p.update(c(9.8, 13.0, 9.5, 12.5, 1)));
	}

	public function testPiercingFirstBarReturnsZero() {
		var p = new PiercingDarkCloud();
		Assert.floatEquals(0.0, p.update(c(12.0, 12.5, 10.0, 10.0, 0)));
	}

	public function testPiercingDarkCloudBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			if (i % 2 == 0) {
				c(base + 2.0, base + 2.5, base, base, i);
			} else {
				c(base - 0.2, base + 1.8, base - 0.5, base + 1.5, i);
			}
		}];
		assertBatchEqualsStreaming(new PiercingDarkCloud(), new PiercingDarkCloud(), bars);
	}

	public function testPiercingDarkCloudResetClearsState() {
		var p = new PiercingDarkCloud();
		p.update(c(12.0, 12.5, 10.0, 10.0, 0));
		p.update(c(9.8, 11.8, 9.5, 11.5, 1));
		Assert.isTrue(p.isReady());
		p.reset();
		Assert.isTrue(!p.isReady());
		Assert.floatEquals(0.0, p.update(c(12.0, 12.5, 10.0, 10.0, 0)));
	}

	// ── RickshawMan ──────────────────────────────────────────────────────────

	public function testRickshawManAccessorsAndMetadata() {
		var t = new RickshawMan();
		Assert.equals("RickshawMan", t.name());
		Assert.equals(1, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testRickshawIsPlusOne() {
		var t = new RickshawMan();
		Assert.floatEquals(1.0, t.update(c(10.0, 12.0, 8.0, 10.0, 0)));
	}

	public function testRickshawOffCentreBodyYieldsZero() {
		var t = new RickshawMan();
		// Long-legged but the body sits near the top, not the middle.
		Assert.floatEquals(0.0, t.update(c(11.4, 12.0, 8.0, 11.45, 0)));
	}

	public function testRickshawOneSidedShadowYieldsZero() {
		var t = new RickshawMan();
		// Dragonfly shape: no upper shadow -> not a rickshaw man.
		Assert.floatEquals(0.0, t.update(c(10.0, 10.05, 6.0, 10.0, 0)));
	}

	public function testRickshawNonDojiYieldsZero() {
		var t = new RickshawMan();
		Assert.floatEquals(0.0, t.update(c(9.0, 12.0, 8.0, 11.0, 0)));
	}

	public function testRickshawZeroRangeYieldsZero() {
		var t = new RickshawMan();
		Assert.floatEquals(0.0, t.update(c(10.0, 10.0, 10.0, 10.0, 0)));
	}

	public function testRickshawManBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 2.0, base - 2.0, base + 0.05, i);
		}];
		assertBatchEqualsStreaming(new RickshawMan(), new RickshawMan(), bars);
	}

	public function testRickshawManResetClearsState() {
		var t = new RickshawMan();
		t.update(c(10.0, 12.0, 8.0, 10.0, 0));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
	}

	// ── RisingThreeMethods ───────────────────────────────────────────────────

	public function testRisingThreeMethodsAccessorsAndMetadata() {
		var t = new RisingThreeMethods();
		Assert.equals("RisingThreeMethods", t.name());
		Assert.equals(5, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testRisingThreeMethodsIsPlusOne() {
		var t = new RisingThreeMethods();
		Assert.floatEquals(0.0, t.update(c(10.0, 15.1, 9.9, 15.0, 0)));
		Assert.floatEquals(0.0, t.update(c(14.0, 14.1, 12.9, 13.0, 1)));
		Assert.floatEquals(0.0, t.update(c(13.5, 13.6, 12.4, 12.5, 2)));
		Assert.floatEquals(0.0, t.update(c(13.0, 13.1, 11.9, 12.0, 3)));
		Assert.floatEquals(1.0, t.update(c(12.5, 16.1, 12.4, 16.0, 4)));
	}

	public function testRisingThreeMethodsMiddleBarBreaksRangeYieldsZero() {
		var t = new RisingThreeMethods();
		t.update(c(10.0, 15.1, 9.9, 15.0, 0));
		t.update(c(14.0, 14.1, 12.9, 13.0, 1));
		// bar3 pokes above bar1's high.
		t.update(c(13.5, 16.0, 12.4, 12.5, 2));
		t.update(c(13.0, 13.1, 11.9, 12.0, 3));
		Assert.floatEquals(0.0, t.update(c(12.5, 16.1, 12.4, 16.0, 4)));
	}

	public function testRisingThreeMethodsBar5NotNewHighYieldsZero() {
		var t = new RisingThreeMethods();
		t.update(c(10.0, 15.1, 9.9, 15.0, 0));
		t.update(c(14.0, 14.1, 12.9, 13.0, 1));
		t.update(c(13.5, 13.6, 12.4, 12.5, 2));
		t.update(c(13.0, 13.1, 11.9, 12.0, 3));
		// bar5 white but closes below bar1's close.
		Assert.floatEquals(0.0, t.update(c(12.5, 14.6, 12.4, 14.5, 4)));
	}

	public function testRisingThreeMethodsFirstFourBarsReturnZero() {
		var t = new RisingThreeMethods();
		Assert.floatEquals(0.0, t.update(c(10.0, 15.1, 9.9, 15.0, 0)));
		Assert.floatEquals(0.0, t.update(c(14.0, 14.1, 12.9, 13.0, 1)));
		Assert.floatEquals(0.0, t.update(c(13.5, 13.6, 12.4, 12.5, 2)));
		Assert.floatEquals(0.0, t.update(c(13.0, 13.1, 11.9, 12.0, 3)));
	}

	public function testRisingThreeMethodsZeroRangeFirstBarYieldsZero() {
		var t = new RisingThreeMethods();
		// Flat first bar (range1 == 0) -> rejected.
		t.update(c(10.0, 10.0, 10.0, 10.0, 0));
		t.update(c(14.0, 14.1, 12.9, 13.0, 1));
		t.update(c(13.5, 13.6, 12.4, 12.5, 2));
		t.update(c(13.0, 13.1, 11.9, 12.0, 3));
		Assert.floatEquals(0.0, t.update(c(12.5, 16.1, 12.4, 16.0, 4)));
	}

	public function testRisingThreeMethodsShortFirstBodyYieldsZero() {
		var t = new RisingThreeMethods();
		// bar1 has a wide range but a tiny body -> not a long white body.
		t.update(c(10.0, 16.0, 9.0, 10.2, 0));
		t.update(c(14.0, 14.1, 12.9, 13.0, 1));
		t.update(c(13.5, 13.6, 12.4, 12.5, 2));
		t.update(c(13.0, 13.1, 11.9, 12.0, 3));
		Assert.floatEquals(0.0, t.update(c(12.5, 16.1, 12.4, 16.0, 4)));
	}

	public function testRisingThreeMethodsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 5.2, base - 0.1, base + 5.0, i);
		}];
		assertBatchEqualsStreaming(new RisingThreeMethods(), new RisingThreeMethods(), bars);
	}

	public function testRisingThreeMethodsResetClearsState() {
		var t = new RisingThreeMethods();
		t.update(c(10.0, 15.1, 9.9, 15.0, 0));
		t.update(c(14.0, 14.1, 12.9, 13.0, 1));
		t.update(c(13.5, 13.6, 12.4, 12.5, 2));
		t.update(c(13.0, 13.1, 11.9, 12.0, 3));
		t.update(c(12.5, 16.1, 12.4, 16.0, 4));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(10.0, 15.1, 9.9, 15.0, 0)));
	}

	// ── SeparatingLines ──────────────────────────────────────────────────────

	public function testSeparatingLinesAccessorsAndMetadata() {
		var t = new SeparatingLines();
		Assert.equals("SeparatingLines", t.name());
		Assert.equals(2, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testBullishSeparatingLinesIsPlusOne() {
		var t = new SeparatingLines();
		Assert.floatEquals(0.0, t.update(c(12.0, 12.1, 9.9, 10.0, 0)));
		Assert.floatEquals(1.0, t.update(c(12.0, 14.1, 12.0, 14.0, 1)));
	}

	public function testBearishSeparatingLinesIsMinusOne() {
		var t = new SeparatingLines();
		Assert.floatEquals(0.0, t.update(c(10.0, 12.1, 9.9, 12.0, 0)));
		Assert.floatEquals(-1.0, t.update(c(10.0, 10.0, 7.9, 8.0, 1)));
	}

	public function testSeparatingLinesSameColorYieldsZero() {
		var t = new SeparatingLines();
		// Both white -> not separating (need opposite colours).
		t.update(c(12.0, 14.1, 11.9, 14.0, 0));
		Assert.floatEquals(0.0, t.update(c(12.0, 14.1, 12.0, 14.0, 1)));
	}

	public function testSeparatingLinesDifferentOpenYieldsZero() {
		var t = new SeparatingLines();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		// bar2 opens far from bar1's open.
		Assert.floatEquals(0.0, t.update(c(13.0, 15.1, 13.0, 15.0, 1)));
	}

	public function testSeparatingLinesOpeningShadowYieldsZero() {
		var t = new SeparatingLines();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		// White bar2 but it has a lower shadow -> not an opening marubozu.
		Assert.floatEquals(0.0, t.update(c(12.0, 14.1, 11.0, 14.0, 1)));
	}

	public function testSeparatingLinesFirstBarReturnsZero() {
		var t = new SeparatingLines();
		Assert.floatEquals(0.0, t.update(c(12.0, 12.1, 9.9, 10.0, 0)));
	}

	public function testSeparatingLinesZeroRangeYieldsZero() {
		var t = new SeparatingLines();
		// Flat first bar (range1 == 0) -> rejected.
		t.update(c(10.0, 10.0, 10.0, 10.0, 0));
		Assert.floatEquals(0.0, t.update(c(10.0, 12.0, 9.0, 11.0, 1)));
	}

	public function testSeparatingLinesShortSecondBodyYieldsZero() {
		var t = new SeparatingLines();
		t.update(c(10.0, 12.0, 8.0, 9.0, 0));
		// Opens coincide but bar2's body is too short to be a separating line.
		Assert.floatEquals(0.0, t.update(c(10.0, 11.0, 9.0, 10.1, 1)));
	}

	public function testSeparatingLinesBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 2.0, base, base + 1.9, i);
		}];
		assertBatchEqualsStreaming(new SeparatingLines(), new SeparatingLines(), bars);
	}

	public function testSeparatingLinesResetClearsState() {
		var t = new SeparatingLines();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		t.update(c(12.0, 14.1, 12.0, 14.0, 1));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(12.0, 12.1, 9.9, 10.0, 0)));
	}

	// ── ShootingStar ─────────────────────────────────────────────────────────

	public function testShootingStarAccessorsAndMetadata() {
		var s = new ShootingStar();
		Assert.equals("ShootingStar", s.name());
		Assert.equals(1, s.warmupPeriod());
		Assert.isTrue(!s.isReady());
	}

	public function testCleanShootingStarIsMinusOne() {
		var s = new ShootingStar();
		Assert.floatEquals(-1.0, s.update(c(10.0, 15.0, 9.9, 10.5, 0)));
	}

	public function testHammerShapeIsNotShootingStar() {
		var s = new ShootingStar();
		Assert.floatEquals(0.0, s.update(c(10.0, 10.6, 5.0, 10.5, 0)));
	}

	public function testDojiIsNotShootingStar() {
		var s = new ShootingStar();
		Assert.floatEquals(0.0, s.update(c(10.0, 11.0, 9.0, 10.0, 0)));
	}

	public function testShootingStarZeroRangeYieldsZero() {
		var s = new ShootingStar();
		Assert.floatEquals(0.0, s.update(c(10.0, 10.0, 10.0, 10.0, 0)));
	}

	public function testShootingStarBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 4.0, base - 0.1, base + 0.5, i);
		}];
		assertBatchEqualsStreaming(new ShootingStar(), new ShootingStar(), bars);
	}

	public function testShootingStarResetClearsState() {
		var s = new ShootingStar();
		s.update(c(10.0, 15.0, 9.9, 10.5, 0));
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
	}

	// ── ShortLine ────────────────────────────────────────────────────────────

	static function warmShortLine(t:ShortLine) {
		for (ts in 0...5) {
			Assert.floatEquals(0.0, t.update(c(10.0, 13.0, 9.5, 12.9, ts)));
		}
	}

	public function testShortLineRejectsZeroPeriod() {
		try {
			new ShortLine(0);
			Assert.fail("Should reject period 0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testShortLineAcceptsValidPeriod() {
		var t = new ShortLine(10);
		Assert.equals(10, t.period());
	}

	public function testShortLineAccessorsAndMetadata() {
		var t = new ShortLine();
		Assert.equals("ShortLine", t.name());
		Assert.equals(5, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
		Assert.equals(5, t.period());
	}

	public function testShortWhiteLineIsPlusOne() {
		var t = new ShortLine();
		warmShortLine(t);
		Assert.isTrue(t.isReady());
		Assert.floatEquals(1.0, t.update(c(10.0, 11.0, 9.9, 10.9, 5)));
	}

	public function testShortBlackLineIsMinusOne() {
		var t = new ShortLine();
		warmShortLine(t);
		Assert.floatEquals(-1.0, t.update(c(10.9, 11.0, 9.9, 10.0, 5)));
	}

	public function testShortLineWideRangeYieldsZero() {
		var t = new ShortLine();
		warmShortLine(t);
		// Range as wide as the average -> not a short line.
		Assert.floatEquals(0.0, t.update(c(10.0, 13.0, 9.5, 12.9, 5)));
	}

	public function testShortLineShortRangeSmallBodyYieldsZero() {
		var t = new ShortLine();
		warmShortLine(t);
		// Compact range but a tiny body -> not a solid short line.
		Assert.floatEquals(0.0, t.update(c(10.4, 11.0, 9.9, 10.5, 5)));
	}

	public function testShortLineWarmupReturnsZero() {
		var t = new ShortLine();
		for (ts in 0...5) {
			Assert.floatEquals(0.0, t.update(c(10.0, 11.0, 9.9, 10.9, ts)));
		}
	}

	public function testShortLineBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			if (i % 7 == 0) {
				c(base, base + 0.6, base - 0.1, base + 0.5, i);
			} else {
				c(base, base + 3.0, base - 1.0, base + 2.8, i);
			}
		}];
		assertBatchEqualsStreaming(new ShortLine(), new ShortLine(), bars);
	}

	public function testShortLineResetClearsState() {
		var t = new ShortLine();
		warmShortLine(t);
		t.update(c(10.0, 11.0, 9.9, 10.9, 5));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(10.0, 11.0, 9.9, 10.9, 0)));
	}

	// ── SpinningTop ──────────────────────────────────────────────────────────

	public function testSpinningTopRejectsInvalidThreshold() {
		try {
			new SpinningTop(0.0);
			Assert.fail("Should reject threshold 0.0");
		} catch (e:Dynamic) {
			Assert.pass();
		}
		try {
			new SpinningTop(1.5);
			Assert.fail("Should reject threshold 1.5");
		} catch (e:Dynamic) {
			Assert.pass();
		}
	}

	public function testSpinningTopAcceptsValidThreshold() {
		var s = new SpinningTop(0.25);
		Assert.isTrue(Math.abs(s.bodyThreshold() - 0.25) < 1e-12);
	}

	public function testSpinningTopAccessorsAndMetadata() {
		var s = new SpinningTop();
		Assert.equals("SpinningTop", s.name());
		Assert.equals(1, s.warmupPeriod());
		Assert.isTrue(!s.isReady());
		Assert.isTrue(Math.abs(s.bodyThreshold() - 0.3) < 1e-12);
	}

	public function testGreenSpinningTopIsPlusOne() {
		var s = new SpinningTop();
		// body 0.5 (10 -> 10.5), upper 3.0, lower 3.0, range 6.5 -> 0.5/6.5 < 0.3.
		Assert.floatEquals(1.0, s.update(c(10.0, 13.5, 7.0, 10.5, 0)));
	}

	public function testRedSpinningTopIsMinusOne() {
		var s = new SpinningTop();
		Assert.floatEquals(-1.0, s.update(c(10.5, 13.5, 7.0, 10.0, 0)));
	}

	public function testMarubozuIsNotSpinning() {
		var s = new SpinningTop();
		Assert.floatEquals(0.0, s.update(c(10.0, 12.0, 10.0, 12.0, 0)));
	}

	public function testDojiIsNotSpinning() {
		// body == 0 fails the body > 0 guard.
		var s = new SpinningTop();
		Assert.floatEquals(0.0, s.update(c(10.0, 11.0, 9.0, 10.0, 0)));
	}

	public function testHammerShapeIsNotSpinningTop() {
		// Lower shadow is long but upper is tiny -> only one long shadow.
		var s = new SpinningTop();
		Assert.floatEquals(0.0, s.update(c(10.0, 10.6, 5.0, 10.5, 0)));
	}

	public function testSpinningTopZeroRangeYieldsZero() {
		var s = new SpinningTop();
		Assert.floatEquals(0.0, s.update(c(10.0, 10.0, 10.0, 10.0, 0)));
	}

	public function testSpinningTopBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 3.0, base - 3.0, base + 0.5, i);
		}];
		assertBatchEqualsStreaming(new SpinningTop(), new SpinningTop(), bars);
	}

	public function testSpinningTopResetClearsState() {
		var s = new SpinningTop();
		s.update(c(10.0, 13.5, 7.0, 10.5, 0));
		Assert.isTrue(s.isReady());
		s.reset();
		Assert.isTrue(!s.isReady());
	}

	// ── StalledPattern ───────────────────────────────────────────────────────

	public function testStalledPatternAccessorsAndMetadata() {
		var t = new StalledPattern();
		Assert.equals("StalledPattern", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testStalledPatternIsMinusOne() {
		var t = new StalledPattern();
		Assert.floatEquals(0.0, t.update(c(10.0, 12.05, 9.9, 12.0, 0)));
		Assert.floatEquals(0.0, t.update(c(11.0, 14.05, 10.9, 14.0, 1)));
		Assert.floatEquals(-1.0, t.update(c(14.0, 14.6, 13.95, 14.15, 2)));
	}

	public function testStalledPatternFirstTwoBarsReturnZero() {
		var t = new StalledPattern();
		Assert.floatEquals(0.0, t.update(c(10.0, 12.05, 9.9, 12.0, 0)));
		Assert.floatEquals(0.0, t.update(c(11.0, 14.05, 10.9, 14.0, 1)));
	}

	public function testStalledPatternZeroRangeYieldsZero() {
		var t = new StalledPattern();
		t.update(c(10.0, 12.05, 9.9, 12.0, 0));
		t.update(c(11.0, 14.05, 10.9, 14.0, 1));
		// bar3 has zero range.
		Assert.floatEquals(0.0, t.update(c(14.0, 14.0, 14.0, 14.0, 2)));
	}

	public function testStalledPatternNonWhiteYieldsZero() {
		var t = new StalledPattern();
		t.update(c(10.0, 12.05, 9.9, 12.0, 0));
		t.update(c(11.0, 14.05, 10.9, 14.0, 1));
		// bar3 is black.
		Assert.floatEquals(0.0, t.update(c(14.2, 14.6, 13.95, 14.05, 2)));
	}

	public function testStalledPatternNonRisingClosesYieldZero() {
		var t = new StalledPattern();
		t.update(c(10.0, 12.05, 9.9, 12.0, 0));
		t.update(c(11.0, 14.05, 10.9, 14.0, 1));
		// bar3 closes below bar2's close (white but not advancing).
		Assert.floatEquals(0.0, t.update(c(13.5, 14.0, 13.45, 13.6, 2)));
	}

	public function testStalledPatternShortFirstBodiesYieldZero() {
		var t = new StalledPattern();
		// bar1 is white but its body is short relative to range.
		t.update(c(11.5, 14.0, 10.0, 12.0, 0));
		t.update(c(11.0, 14.05, 10.9, 14.0, 1));
		Assert.floatEquals(0.0, t.update(c(14.0, 14.6, 13.95, 14.15, 2)));
	}

	public function testStalledPatternLargeThirdBodyYieldsZero() {
		var t = new StalledPattern();
		t.update(c(10.0, 12.05, 9.9, 12.0, 0));
		t.update(c(11.0, 14.05, 10.9, 14.0, 1));
		// bar3 has a large body (not a small stalling candle).
		Assert.floatEquals(0.0, t.update(c(14.0, 16.05, 13.95, 16.0, 2)));
	}

	public function testStalledPatternThirdBarOffShoulderYieldsZero() {
		var t = new StalledPattern();
		t.update(c(10.0, 12.05, 9.9, 12.0, 0));
		t.update(c(11.0, 14.05, 10.9, 14.0, 1));
		// bar3 is a small white candle but opens well below bar2's close,
		// so it is not riding the shoulder.
		Assert.floatEquals(0.0, t.update(c(13.6, 14.1, 12.55, 14.05, 2)));
	}

	public function testStalledPatternBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 2.05, base - 0.1, base + 2.0, i);
		}];
		assertBatchEqualsStreaming(new StalledPattern(), new StalledPattern(), bars);
	}

	public function testStalledPatternResetClearsState() {
		var t = new StalledPattern();
		t.update(c(10.0, 12.05, 9.9, 12.0, 0));
		t.update(c(11.0, 14.05, 10.9, 14.0, 1));
		t.update(c(14.0, 14.6, 13.95, 14.15, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(10.0, 12.05, 9.9, 12.0, 0)));
	}

	// ── StickSandwich ────────────────────────────────────────────────────────

	public function testStickSandwichAccessorsAndMetadata() {
		var t = new StickSandwich();
		Assert.equals("StickSandwich", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testStickSandwichIsPlusOne() {
		var t = new StickSandwich();
		Assert.floatEquals(0.0, t.update(c(12.0, 12.1, 9.9, 10.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 11.6, 10.4, 11.5, 1)));
		Assert.floatEquals(1.0, t.update(c(11.5, 11.6, 9.9, 10.0, 2)));
	}

	public function testStickSandwichFirstTwoBarsReturnZero() {
		var t = new StickSandwich();
		Assert.floatEquals(0.0, t.update(c(12.0, 12.1, 9.9, 10.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 11.6, 10.4, 11.5, 1)));
	}

	public function testStickSandwichFirstCandleNotBlackYieldsZero() {
		var t = new StickSandwich();
		// bar1 white.
		t.update(c(9.9, 12.1, 9.8, 10.0, 0));
		t.update(c(10.5, 11.6, 10.4, 11.5, 1));
		Assert.floatEquals(0.0, t.update(c(11.5, 11.6, 9.9, 10.0, 2)));
	}

	public function testStickSandwichMiddleCandleNotWhiteYieldsZero() {
		var t = new StickSandwich();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		// bar2 black.
		t.update(c(11.5, 11.6, 10.4, 10.5, 1));
		Assert.floatEquals(0.0, t.update(c(11.5, 11.6, 9.9, 10.0, 2)));
	}

	public function testStickSandwichThirdCandleNotBlackYieldsZero() {
		var t = new StickSandwich();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		t.update(c(10.5, 11.6, 10.4, 11.5, 1));
		// bar3 white.
		Assert.floatEquals(0.0, t.update(c(9.9, 11.6, 9.8, 10.0, 2)));
	}

	public function testStickSandwichMiddleLowNotAboveFirstCloseYieldsZero() {
		var t = new StickSandwich();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		// bar2 white but dips below bar1's close.
		t.update(c(10.5, 11.6, 9.0, 11.5, 1));
		Assert.floatEquals(0.0, t.update(c(11.5, 11.6, 9.9, 10.0, 2)));
	}

	public function testStickSandwichMismatchedClosesYieldZero() {
		var t = new StickSandwich();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		t.update(c(10.5, 11.6, 10.4, 11.5, 1));
		// bar3 black but closes well away from bar1's close.
		Assert.floatEquals(0.0, t.update(c(11.5, 11.6, 7.9, 8.0, 2)));
	}

	public function testStickSandwichBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base + 2.0, base + 2.1, base - 0.1, base, i);
		}];
		assertBatchEqualsStreaming(new StickSandwich(), new StickSandwich(), bars);
	}

	public function testStickSandwichResetClearsState() {
		var t = new StickSandwich();
		t.update(c(12.0, 12.1, 9.9, 10.0, 0));
		t.update(c(10.5, 11.6, 10.4, 11.5, 1));
		t.update(c(11.5, 11.6, 9.9, 10.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(12.0, 12.1, 9.9, 10.0, 0)));
	}

	// ── Takuri ───────────────────────────────────────────────────────────────

	public function testTakuriAccessorsAndMetadata() {
		var t = new Takuri();
		Assert.equals("Takuri", t.name());
		Assert.equals(1, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testTakuriIsPlusOne() {
		var t = new Takuri();
		Assert.floatEquals(1.0, t.update(c(10.0, 10.05, 7.0, 10.0, 0)));
	}

	public function testTakuriNonDojiBodyYieldsZero() {
		var t = new Takuri();
		// Large body -> not a doji.
		Assert.floatEquals(0.0, t.update(c(10.0, 12.0, 7.0, 11.5, 0)));
	}

	public function testTakuriUpperShadowYieldsZero() {
		var t = new Takuri();
		// Long upper shadow -> not a Takuri.
		Assert.floatEquals(0.0, t.update(c(10.0, 14.0, 7.0, 10.0, 0)));
	}

	public function testDragonflyButNotTakuriYieldsZero() {
		var t = new Takuri();
		// Upper shadow ~0.07 of range: a Dragonfly Doji, but exceeds Takuri's
		// tighter 0.05 ceiling.
		Assert.floatEquals(0.0, t.update(c(10.0, 10.24, 7.0, 10.0, 0)));
	}

	public function testTakuriZeroRangeYieldsZero() {
		var t = new Takuri();
		Assert.floatEquals(0.0, t.update(c(10.0, 10.0, 10.0, 10.0, 0)));
	}

	public function testTakuriBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 0.02, base - 4.0, base, i);
		}];
		assertBatchEqualsStreaming(new Takuri(), new Takuri(), bars);
	}

	public function testTakuriResetClearsState() {
		var t = new Takuri();
		t.update(c(10.0, 10.05, 7.0, 10.0, 0));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
	}

	// ── TasukiGap ────────────────────────────────────────────────────────────

	public function testTasukiGapAccessorsAndMetadata() {
		var t = new TasukiGap();
		Assert.equals("TasukiGap", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testUpsideTasukiGapIsPlusOne() {
		var t = new TasukiGap();
		Assert.floatEquals(0.0, t.update(c(10.0, 11.2, 9.8, 11.0, 0)));
		Assert.floatEquals(0.0, t.update(c(12.0, 14.0, 11.9, 13.5, 1)));
		Assert.floatEquals(1.0, t.update(c(13.0, 13.1, 11.4, 11.5, 2)));
	}

	public function testDownsideTasukiGapIsMinusOne() {
		var t = new TasukiGap();
		Assert.floatEquals(0.0, t.update(c(13.0, 13.2, 11.8, 12.0, 0)));
		Assert.floatEquals(0.0, t.update(c(11.0, 11.1, 9.5, 10.0, 1)));
		Assert.floatEquals(-1.0, t.update(c(10.5, 11.6, 10.4, 11.5, 2)));
	}

	public function testTasukiGapFirstTwoBarsReturnZero() {
		var t = new TasukiGap();
		Assert.floatEquals(0.0, t.update(c(10.0, 11.2, 9.8, 11.0, 0)));
		Assert.floatEquals(0.0, t.update(c(12.0, 14.0, 11.9, 13.5, 1)));
	}

	public function testTasukiUpNoGapYieldsZero() {
		var t = new TasukiGap();
		t.update(c(10.0, 11.2, 9.8, 11.0, 0));
		// bar2 white but opens below bar1's close -> no upside gap.
		t.update(c(10.5, 13.1, 10.4, 13.0, 1));
		Assert.floatEquals(0.0, t.update(c(12.5, 12.6, 10.9, 11.0, 2)));
	}

	public function testTasukiUpThirdNotBlackYieldsZero() {
		var t = new TasukiGap();
		t.update(c(10.0, 11.2, 9.8, 11.0, 0));
		t.update(c(12.0, 14.0, 11.9, 13.5, 1));
		// bar3 white.
		Assert.floatEquals(0.0, t.update(c(12.5, 13.1, 12.4, 13.0, 2)));
	}

	public function testTasukiUpThirdOpenOutsideBodyYieldsZero() {
		var t = new TasukiGap();
		t.update(c(10.0, 11.2, 9.8, 11.0, 0));
		t.update(c(12.0, 14.0, 11.9, 13.5, 1));
		// bar3 black but opens above bar2's body.
		Assert.floatEquals(0.0, t.update(c(14.0, 14.1, 11.4, 11.5, 2)));
	}

	public function testTasukiUpThirdCloseNotInGapYieldsZero() {
		var t = new TasukiGap();
		t.update(c(10.0, 11.2, 9.8, 11.0, 0));
		t.update(c(12.0, 14.0, 11.9, 13.5, 1));
		// bar3 black, opens in body, but closes below the gap (under bar1's close).
		Assert.floatEquals(0.0, t.update(c(13.0, 13.1, 10.4, 10.5, 2)));
	}

	public function testTasukiDownNoGapYieldsZero() {
		var t = new TasukiGap();
		t.update(c(13.0, 13.2, 11.8, 12.0, 0));
		// bar2 black but opens above bar1's close -> no downside gap.
		t.update(c(12.5, 12.6, 10.4, 10.5, 1));
		Assert.floatEquals(0.0, t.update(c(11.0, 12.6, 10.9, 12.0, 2)));
	}

	public function testTasukiDownThirdNotWhiteYieldsZero() {
		var t = new TasukiGap();
		t.update(c(13.0, 13.2, 11.8, 12.0, 0));
		t.update(c(11.0, 11.1, 9.5, 10.0, 1));
		// bar3 black.
		Assert.floatEquals(0.0, t.update(c(11.5, 11.6, 10.4, 10.5, 2)));
	}

	public function testTasukiDownThirdOpenOutsideBodyYieldsZero() {
		var t = new TasukiGap();
		t.update(c(13.0, 13.2, 11.8, 12.0, 0));
		t.update(c(11.0, 11.1, 9.5, 10.0, 1));
		// bar3 white but opens below bar2's body.
		Assert.floatEquals(0.0, t.update(c(9.5, 11.6, 9.4, 11.5, 2)));
	}

	public function testTasukiDownThirdCloseNotInGapYieldsZero() {
		var t = new TasukiGap();
		t.update(c(13.0, 13.2, 11.8, 12.0, 0));
		t.update(c(11.0, 11.1, 9.5, 10.0, 1));
		// bar3 white, opens in body, but closes above the gap (over bar1's close).
		Assert.floatEquals(0.0, t.update(c(10.5, 13.0, 10.4, 12.5, 2)));
	}

	public function testTasukiMixedColoursYieldZero() {
		var t = new TasukiGap();
		// bar1 white, bar2 black -> neither an upside nor downside setup.
		t.update(c(10.0, 11.2, 9.8, 11.0, 0));
		t.update(c(13.0, 13.2, 11.0, 11.5, 1));
		Assert.floatEquals(0.0, t.update(c(12.0, 12.6, 10.9, 11.0, 2)));
	}

	public function testTasukiGapBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 5.2, base - 0.1, base + 5.0, i);
		}];
		assertBatchEqualsStreaming(new TasukiGap(), new TasukiGap(), bars);
	}

	public function testTasukiGapResetClearsState() {
		var t = new TasukiGap();
		t.update(c(10.0, 11.2, 9.8, 11.0, 0));
		t.update(c(12.0, 14.0, 11.9, 13.5, 1));
		t.update(c(13.0, 13.1, 11.4, 11.5, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(10.0, 11.2, 9.8, 11.0, 0)));
	}

	// ── ThreeInside ──────────────────────────────────────────────────────────

	public function testThreeInsideAccessorsAndMetadata() {
		var t = new ThreeInside();
		Assert.equals("ThreeInside", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testThreeInsideUpIsPlusOne() {
		var t = new ThreeInside();
		Assert.floatEquals(0.0, t.update(c(12.0, 12.5, 9.5, 10.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 11.5, 10.4, 11.0, 1)));
		// Bar 3 closes 12.5 > Bar 1 open 12.
		Assert.floatEquals(1.0, t.update(c(11.0, 13.0, 10.9, 12.5, 2)));
	}

	public function testThreeInsideDownIsMinusOne() {
		var t = new ThreeInside();
		Assert.floatEquals(0.0, t.update(c(10.0, 12.5, 9.5, 12.0, 0)));
		Assert.floatEquals(0.0, t.update(c(11.5, 11.6, 10.9, 11.0, 1)));
		// Bar 3 closes 9.5 < Bar 1 open 10.
		Assert.floatEquals(-1.0, t.update(c(11.0, 11.1, 9.3, 9.5, 2)));
	}

	public function testThreeInsideUnconfirmedThirdBarYieldsZero() {
		var t = new ThreeInside();
		t.update(c(12.0, 12.5, 9.5, 10.0, 0));
		t.update(c(10.5, 11.5, 10.4, 11.0, 1));
		// Bar 3 green but closes below b1.open (12).
		Assert.floatEquals(0.0, t.update(c(11.0, 11.8, 10.9, 11.5, 2)));
	}

	public function testThreeInsideFirstTwoBarsReturnZero() {
		var t = new ThreeInside();
		Assert.floatEquals(0.0, t.update(c(12.0, 12.5, 9.5, 10.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 11.5, 10.4, 11.0, 1)));
	}

	public function testThreeInsideBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 1.0, base - 0.5, base + 0.5, i);
		}];
		assertBatchEqualsStreaming(new ThreeInside(), new ThreeInside(), bars);
	}

	public function testThreeInsideResetClearsState() {
		var t = new ThreeInside();
		t.update(c(12.0, 12.5, 9.5, 10.0, 0));
		t.update(c(10.5, 11.5, 10.4, 11.0, 1));
		t.update(c(11.0, 13.0, 10.9, 12.5, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(12.0, 12.5, 9.5, 10.0, 0)));
	}

	// ── ThreeLineStrike ──────────────────────────────────────────────────────

	public function testThreeLineStrikeAccessorsAndMetadata() {
		var t = new ThreeLineStrike();
		Assert.equals("ThreeLineStrike", t.name());
		Assert.equals(4, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testBullishThreeLineStrikeIsPlusOne() {
		var t = new ThreeLineStrike();
		Assert.floatEquals(0.0, t.update(c(10.0, 11.1, 9.9, 11.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 12.1, 10.4, 12.0, 1)));
		Assert.floatEquals(0.0, t.update(c(11.5, 13.1, 11.4, 13.0, 2)));
		Assert.floatEquals(1.0, t.update(c(13.5, 13.6, 9.4, 9.5, 3)));
	}

	public function testBearishThreeLineStrikeIsMinusOne() {
		var t = new ThreeLineStrike();
		Assert.floatEquals(0.0, t.update(c(13.0, 13.1, 11.9, 12.0, 0)));
		Assert.floatEquals(0.0, t.update(c(12.5, 12.6, 10.9, 11.0, 1)));
		Assert.floatEquals(0.0, t.update(c(11.5, 11.6, 9.9, 10.0, 2)));
		Assert.floatEquals(-1.0, t.update(c(9.5, 13.6, 9.4, 13.5, 3)));
	}

	public function testStrikeNotClearingFirstOpenYieldsZero() {
		var t = new ThreeLineStrike();
		t.update(c(10.0, 11.1, 9.9, 11.0, 0));
		t.update(c(10.5, 12.1, 10.4, 12.0, 1));
		t.update(c(11.5, 13.1, 11.4, 13.0, 2));
		// bar4 closes 10.5, above bar1's open (10.0) -> does not strike through.
		Assert.floatEquals(0.0, t.update(c(13.5, 13.6, 10.4, 10.5, 3)));
	}

	public function testThreeLineStrikeFirstThreeBarsReturnZero() {
		var t = new ThreeLineStrike();
		Assert.floatEquals(0.0, t.update(c(10.0, 11.1, 9.9, 11.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 12.1, 10.4, 12.0, 1)));
		Assert.floatEquals(0.0, t.update(c(11.5, 13.1, 11.4, 13.0, 2)));
	}

	public function testThreeLineStrikeBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 1.5, base - 0.2, base + 1.0, i);
		}];
		assertBatchEqualsStreaming(new ThreeLineStrike(), new ThreeLineStrike(), bars);
	}

	public function testThreeLineStrikeResetClearsState() {
		var t = new ThreeLineStrike();
		t.update(c(10.0, 11.1, 9.9, 11.0, 0));
		t.update(c(10.5, 12.1, 10.4, 12.0, 1));
		t.update(c(11.5, 13.1, 11.4, 13.0, 2));
		t.update(c(13.5, 13.6, 9.4, 9.5, 3));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(10.0, 11.1, 9.9, 11.0, 0)));
	}

	// ── ThreeOutside ─────────────────────────────────────────────────────────

	public function testThreeOutsideAccessorsAndMetadata() {
		var t = new ThreeOutside();
		Assert.equals("ThreeOutside", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testThreeOutsideUpIsPlusOne() {
		var t = new ThreeOutside();
		Assert.floatEquals(0.0, t.update(c(11.0, 11.2, 9.8, 10.0, 0)));
		Assert.floatEquals(0.0, t.update(c(9.5, 12.0, 9.5, 11.5, 1)));
		// Bar 3 green close 12.5 > b2.close 11.5.
		Assert.floatEquals(1.0, t.update(c(11.5, 13.0, 11.4, 12.5, 2)));
	}

	public function testThreeOutsideDownIsMinusOne() {
		var t = new ThreeOutside();
		Assert.floatEquals(0.0, t.update(c(10.0, 11.2, 9.8, 11.0, 0)));
		Assert.floatEquals(0.0, t.update(c(12.0, 12.0, 9.0, 9.0, 1)));
		// Bar 3 red close 8.0 < b2.close 9.0.
		Assert.floatEquals(-1.0, t.update(c(9.0, 9.1, 7.9, 8.0, 2)));
	}

	public function testThreeOutsideUnconfirmedThirdBarYieldsZero() {
		var t = new ThreeOutside();
		t.update(c(11.0, 11.2, 9.8, 10.0, 0));
		t.update(c(9.5, 12.0, 9.5, 11.5, 1));
		// Bar 3 green but does not exceed b2.close 11.5.
		Assert.floatEquals(0.0, t.update(c(11.0, 11.4, 10.9, 11.3, 2)));
	}

	public function testThreeOutsideFirstTwoBarsReturnZero() {
		var t = new ThreeOutside();
		Assert.floatEquals(0.0, t.update(c(11.0, 11.2, 9.8, 10.0, 0)));
		Assert.floatEquals(0.0, t.update(c(9.5, 12.0, 9.5, 11.5, 1)));
	}

	public function testThreeOutsideBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 1.5, base - 0.5, base + 1.0, i);
		}];
		assertBatchEqualsStreaming(new ThreeOutside(), new ThreeOutside(), bars);
	}

	public function testThreeOutsideResetClearsState() {
		var t = new ThreeOutside();
		t.update(c(11.0, 11.2, 9.8, 10.0, 0));
		t.update(c(9.5, 12.0, 9.5, 11.5, 1));
		t.update(c(11.5, 13.0, 11.4, 12.5, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(11.0, 11.2, 9.8, 10.0, 0)));
	}

	// ── ThreeSoldiersOrCrows ─────────────────────────────────────────────────

	public function testThreeSoldiersOrCrowsAccessorsAndMetadata() {
		var t = new ThreeSoldiersOrCrows();
		Assert.equals("ThreeSoldiersOrCrows", t.name());
		Assert.equals(3, t.warmupPeriod());
		Assert.isTrue(!t.isReady());
	}

	public function testThreeWhiteSoldiersIsPlusOne() {
		var t = new ThreeSoldiersOrCrows();
		Assert.floatEquals(0.0, t.update(c(10.0, 11.5, 9.9, 11.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 12.5, 10.4, 12.0, 1)));
		Assert.floatEquals(1.0, t.update(c(11.5, 13.5, 11.4, 13.0, 2)));
	}

	public function testThreeBlackCrowsIsMinusOne() {
		var t = new ThreeSoldiersOrCrows();
		// Bar1 13->12 (red), Bar2 opens inside [12,13] at 12.5, closes 11.
		// Bar3 opens inside [11,12.5] at 11.5, closes 10.
		Assert.floatEquals(0.0, t.update(c(13.0, 13.1, 11.9, 12.0, 0)));
		Assert.floatEquals(0.0, t.update(c(12.5, 12.6, 10.9, 11.0, 1)));
		Assert.floatEquals(-1.0, t.update(c(11.5, 11.6, 9.9, 10.0, 2)));
	}

	public function testThreeSoldiersMixedDirectionsYieldZero() {
		var t = new ThreeSoldiersOrCrows();
		t.update(c(10.0, 11.5, 9.9, 11.0, 0));
		t.update(c(11.0, 11.2, 10.0, 10.5, 1));
		Assert.floatEquals(0.0, t.update(c(10.5, 11.5, 10.4, 11.4, 2)));
	}

	public function testThreeSoldiersFirstTwoBarsReturnZero() {
		var t = new ThreeSoldiersOrCrows();
		Assert.floatEquals(0.0, t.update(c(10.0, 11.5, 9.9, 11.0, 0)));
		Assert.floatEquals(0.0, t.update(c(10.5, 12.5, 10.4, 12.0, 1)));
	}

	public function testThreeSoldiersOrCrowsBatchEqualsStreaming() {
		var bars = [for (i in 0...40) {
			var base = 100.0 + i;
			c(base, base + 1.5, base - 0.1, base + 1.0, i);
		}];
		assertBatchEqualsStreaming(new ThreeSoldiersOrCrows(), new ThreeSoldiersOrCrows(), bars);
	}

	public function testThreeSoldiersOrCrowsResetClearsState() {
		var t = new ThreeSoldiersOrCrows();
		t.update(c(10.0, 11.5, 9.9, 11.0, 0));
		t.update(c(10.5, 12.5, 10.4, 12.0, 1));
		t.update(c(11.5, 13.5, 11.4, 13.0, 2));
		Assert.isTrue(t.isReady());
		t.reset();
		Assert.isTrue(!t.isReady());
		Assert.floatEquals(0.0, t.update(c(10.0, 11.5, 9.9, 11.0, 0)));
	}
}

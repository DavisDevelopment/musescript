package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;
import musescript.harness.Bar;

/**
 * The 2026-08 analytical builtin batch: `slope` / `zscore_roll` / `percent_rank` (series-stat regime
 * gates), `highest_since_entry` / `lowest_since_entry` / `return_since_entry` (in-trade analytics),
 * and `asset_in` / `symbol_in` (variadic instrument membership). Correctness is pinned on a strictly
 * INCREASING feed, where the current bar is always the window max: slope>0, percent_rank==1, zscore>0.
 */
class TestMoreBuiltins extends Test {
	static function rising(n:Int):Array<Bar> {
		return [for (i in 0...n) { open: 100.0 + i, high: 100.5 + i, low: 99.5 + i, close: 100.0 + i, volume: 1.0, time: i, index: i }];
	}

	static function trades(entry:String, ?symbol:String = "", ?assetClass:String = ""):Int {
		var src = 'strategy B { onBar { when $entry: long() when !($entry): flat() } }';
		var h = new HarnessContext();
		h.symbol = symbol; h.assetClass = assetClass;
		return new MuseInterp(h).runBacktest(new MuseParser().parse(src), new BarFeed(rising(120))).trades;
	}

	public function testSlopeIsPositiveOnAnUptrend() {
		Assert.isTrue(trades("slope(close, 5) > 0") > 0, "slope of a rising series must be > 0");
		Assert.equals(0, trades("slope(close, 5) < 0"), "a rising series never has negative slope");
	}

	public function testPercentRankIsOneWhenCurrentIsTheWindowMax() {
		Assert.isTrue(trades("percent_rank(close, 8) >= 1.0") > 0, "on a strict uptrend the current value is the window max => rank 1.0");
		Assert.equals(0, trades("percent_rank(close, 8) > 1.0"), "percent_rank never exceeds 1.0");
	}

	public function testZscoreRollIsPositiveAboveTheRollingMean() {
		Assert.isTrue(trades("zscore_roll(close, 8) > 0") > 0, "rising series sits above its own rolling mean => z > 0");
	}

	public function testReturnSinceEntryTracksAnOpenWinner() {
		// return_since_entry() is a POSITION-management gate (0 while flat): enter simply, exit once the
		// open long is up >2%. On a series climbing ~1/bar from 100 that happens within a few bars, so
		// a completed round trip (trades > 0) proves the return went positive.
		var src = "strategy R { onBar { when close > sma(close, 3): long() when return_since_entry() > 0.02: flat() } }";
		var got = new MuseInterp(new HarnessContext()).runBacktest(new MuseParser().parse(src), new BarFeed(rising(120))).trades;
		Assert.isTrue(got > 0, "an open long on a rising series earns a positive return_since_entry");
	}

	public function testInTradeExtremesAreOrdered() {
		// highest_since_entry >= lowest_since_entry always holds while in a trade; encode it as a gate
		// that can only fire if the ordering is right (never exits spuriously => it keeps trading).
		Assert.isTrue(trades("highest_since_entry(\"high\") >= lowest_since_entry(\"low\")") > 0, "peak >= trough since entry");
	}

	public function testAssetInAndSymbolInMatchMembership() {
		Assert.isTrue(trades("asset_in(\"crypto\", \"forex\") && close > 0", "BTCUSD", "forex") > 0, "asset_in matches one of its args");
		Assert.equals(0, trades("asset_in(\"crypto\", \"equity\") && close > 0", "BTCUSD", "forex"), "asset_in false when class absent");
		Assert.isTrue(trades("symbol_in(\"AAA\", \"BTCUSD\") && close > 0", "BTCUSD", "crypto") > 0, "symbol_in matches one of its args");
		Assert.equals(0, trades("symbol_in(\"AAA\", \"BBB\") && close > 0", "BTCUSD", "crypto"), "symbol_in false when symbol absent");
	}
}

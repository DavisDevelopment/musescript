package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.interp.MuseInterp;
import musescript.harness.HarnessContext;
import musescript.harness.BarFeed;

/**
 * Per-instrument conditionality: `asset_is(class)` / `symbol_is(name)` read the run-CONSTANT tape
 * identity (`HarnessContext.symbol`/`assetClass`, set by the tape loader) so ONE uniform strategy
 * can self-specialize per instrument. These gate on metadata, not price, so the assertion is purely
 * "the same source + same feed trades under one identity and sits flat under another".
 */
class TestAssetConditionality extends Test {
	static function runTrades(src:String, symbol:String, assetClass:String):Int {
		var h = new HarnessContext();
		h.symbol = symbol;
		h.assetClass = assetClass;
		var res = new MuseInterp(h).runBacktest(new MuseParser().parse(src), BarFeed.synthetic(400, 11));
		return res.trades;
	}

	static inline var GATED = "
		strategy AssetGate {
			onBar {
				when asset_is(\"crypto\") && close > sma(close, 3): long()
				when close < sma(close, 3): flat()
			}
		}
	";

	public function testAssetIsGatesEntryOnAssetClass() {
		var crypto = runTrades(GATED, "BTCUSD", "crypto");
		var forex = runTrades(GATED, "EURUSD", "forex");
		Assert.isTrue(crypto > 0, 'crypto tape should trade under asset_is("crypto"), got $crypto');
		Assert.equals(0, forex, 'forex tape must not trade under an asset_is("crypto") gate');
	}

	public function testAssetIsIsCaseInsensitiveOnClass() {
		// The tape's casing must not trip a hand-written lower-case query.
		Assert.isTrue(runTrades(GATED, "BTCUSD", "CRYPTO") > 0, "asset_is should match case-insensitively");
		Assert.isTrue(runTrades(GATED, "BTCUSD", "Crypto") > 0, "asset_is should match mixed case");
	}

	public function testSymbolIsGatesEntryOnExactSymbol() {
		var src = "
			strategy OnlyBtc {
				onBar {
					when symbol_is(\"BTCUSD\") && close > sma(close, 3): long()
					when close < sma(close, 3): flat()
				}
			}
		";
		Assert.isTrue(runTrades(src, "BTCUSD", "crypto") > 0, "symbol_is should match the exact symbol");
		Assert.equals(0, runTrades(src, "ETHUSD", "crypto"), "symbol_is must be exact (ETHUSD != BTCUSD)");
	}

	public function testUnknownIdentityIsInertNotAnError() {
		// Default empty identity (a plain OHLCV tape with no symbol/asset columns): both builtins
		// simply return false, so a gated strategy sits flat rather than erroring.
		Assert.equals(0, runTrades(GATED, "", ""), "empty asset identity should be inert (no trades, no error)");
	}
}

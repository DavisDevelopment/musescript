package musescript.tests;

import utest.Test;
import utest.Assert;
import musescript.parse.MuseParser;
import musescript.compile.TemplateExpand;
import musescript.compile.ModuleExpand;
import musescript.evo.CorpusSeed;
import musescript.evo.Expand;
import musescript.evo.Fitness;
import musescript.evo.RegistryPalette;
import musescript.harness.BarFeed;

/**
 * First dedicated test coverage for CorpusSeed.hx -- previously exercised only via CorpusEvoRun's
 * own real-corpus runs, never as a unit under `node build/js/tests.js`. Covers the two NEW
 * translation capabilities added so evolution's growth-side vocabulary (risk-managed exits,
 * multi-output indicator fields -- see Variation.growRiskExit/growMultiOutputField) has a
 * matching reverse-compilation path: a hand-written strategy using either shape can now seed the
 * corpus population instead of evolution only ever discovering that shape from scratch.
 */
class TestCorpusSeed extends Test {
	function allowedIndicators():Map<String, Bool> {
		var m = new Map<String, Bool>();
		for (n in RegistryPalette.compatibleNames()) m.set(n, true);
		return m;
	}

	function translate(src:String) {
		var prog = new MuseParser().parse(src, "<test>");
		prog = TemplateExpand.expand(prog);
		prog = ModuleExpand.expand(prog);
		return CorpusSeed.translateProgram(prog, allowedIndicators());
	}

	// ── risk-managed exit translation ─────────────────────────────────────────────────────

	public function testTranslatesStopLossCondition() {
		var g = translate('
			strategy RiskTest {
				onBar {
					when crossover(close, sma(close, 8)): long()
					when unrealized_pnl_pct() < -0.02: flat()
				}
			}
		');
		Assert.notNull(g, "expected a stop-loss guard to translate, not skip");
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "unrealized_pnl_pct()"), 'expected the risk-exit feature in: $src');

		var bars = BarFeed.synthetic(300, 11).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok, 'translated risk-exit genome failed to evaluate: ${r.error}\n$src');
	}

	public function testTranslatesTimeStopCondition() {
		var g = translate('
			strategy TimeStopTest {
				onBar {
					when crossover(close, sma(close, 8)): long()
					when bars_in_trade() > 20: flat()
				}
			}
		');
		Assert.notNull(g);
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, "bars_in_trade()"), 'expected the time-stop feature in: $src');
		var bars = BarFeed.synthetic(300, 11).all();
		Assert.isTrue(Fitness.evaluate(g, bars, "js", false).ok);
	}

	// ── multi-output field translation ────────────────────────────────────────────────────

	public function testTranslatesMacdHistField() {
		var g = translate('
			strategy MacdTest {
				onBar {
					when macd(close).hist > 0: long()
					when macd(close).hist < 0: flat()
				}
			}
		');
		Assert.notNull(g, "expected macd(...).hist to translate, not skip");
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, 'macd("close").hist'), 'expected a rendered macd(...).hist call in: $src');
		var bars = BarFeed.synthetic(300, 13).all();
		var r = Fitness.evaluate(g, bars, "js", false);
		Assert.isTrue(r.ok, 'translated macd genome failed to evaluate: ${r.error}\n$src');
	}

	public function testTranslatesBbandsUpperFieldWithNumericArgs() {
		var g = translate('
			strategy BBandsTest {
				onBar {
					when close > bbands(close, 20, 2).upper: short()
					when close < bbands(close, 20, 2).lower: flat()
				}
			}
		');
		Assert.notNull(g, "expected bbands(...).upper/.lower to translate, not skip");
		var src = Expand.expand(g);
		Assert.isTrue(StringTools.contains(src, 'bbands("close", 20, 2).upper'), 'expected a rendered bbands call in: $src');
		var bars = BarFeed.synthetic(300, 17).all();
		Assert.isTrue(Fitness.evaluate(g, bars, "js", false).ok);
	}

	// ── fail-closed boundary ───────────────────────────────────────────────────────────────

	/** A multi-output call whose series arg is a bound variable holding something OTHER than a
	 * bare price field (here, an indicator output) isn't representable by the literal-args-only
	 * `renderLiteralCall` -- must return null (skip), never guess/silently misrepresent. */
	// ── fib_retracement seed genomes ──────────────────────────────────────────────────────

	public function testFibRetracementSeedsRenderAndExecute() {
		var genomes = CorpusSeed.seedFromFibRetracement([20]);
		Assert.equals(2, genomes.length, "expected one breakout + one reclaim genome per window");
		var bars = BarFeed.synthetic(300, 23).all();
		for (g in genomes) {
			var src = Expand.expand(g);
			Assert.isTrue(StringTools.contains(src, "fib_retracement(20)"), 'expected a rendered fib_retracement call in: $src');
			var r = Fitness.evaluate(g, bars, "js", false);
			Assert.isTrue(r.ok, 'fib_retracement seed genome "${g.name}" failed to evaluate: ${r.error}\n$src');
		}
	}

	public function testFibRetracementDefaultWindowsProduceDistinctGenomes() {
		var genomes = CorpusSeed.seedFromFibRetracement();
		Assert.equals(6, genomes.length); // 3 default windows x 2 shapes
		var names = [for (g in genomes) g.name];
		var uniq = new Map<String, Bool>();
		for (n in names) uniq.set(n, true);
		Assert.equals(genomes.length, [for (k in uniq.keys()) k].length, "expected every seed genome to have a distinct name");
	}

	/**
	 * Regression for the "first shake" catastrophe: level-COMPARISON seeds (price > level618)
	 * fired on every bar price merely sat on one side, generating hundreds to thousands of
	 * trades on a real tape. The redesigned seeds use edge-triggered crossings instead --
	 * confirm the rendered source actually contains a crossing shape (a lookback-based "was on
	 * the other side last bar" check), not a bare level comparison alone.
	 */
	public function testFibRetracementSeedsAreEdgeTriggeredNotLevelConditions() {
		var genomes = CorpusSeed.seedFromFibRetracement([20]);
		for (g in genomes) {
			var src = Expand.expand(g);
			Assert.isTrue(StringTools.contains(src, "close[1]") || StringTools.contains(src, "[1]"),
				'expected a lookback-based edge trigger (not a bare level condition) in: $src');
		}
	}

	public function testFourierProjectionSeedsRenderAndExecuteWithCustomParams() {
		var genomes = CorpusSeed.seedFromFourierProjection();
		Assert.equals(2, genomes.length);
		var bars = BarFeed.synthetic(400, 29).all();
		for (g in genomes) {
			var src = Expand.expand(g);
			Assert.isTrue(StringTools.contains(src, "fourier_projection("), 'expected a rendered fourier_projection call in: $src');
			// Confirms the CUSTOM k/horizon config actually made it into the rendered call
			// (not just the 2-arg SInd-default shape the original, catastrophic seed used).
			Assert.isTrue(StringTools.contains(src, "34, 3, 3") || StringTools.contains(src, "89, 2, 8"),
				'expected the custom (period, k, horizon) config in: $src');
			var r = Fitness.evaluate(g, bars, "js", false);
			Assert.isTrue(r.ok, 'fourier_projection seed genome "${g.name}" failed to evaluate: ${r.error}\n$src');
		}
	}

	public function testMultiOutputWithNonLiteralArgFailsOpenToOpaqueLeaf() {
		// Fail-OPEN (deliberately changed from the old fail-closed): a multi-output field on a
		// non-literal series arg can't be STRUCTURED (renderLiteralCall only accepts literal/price
		// args), so instead of skipping the whole strategy it is carried verbatim as an opaque
		// BFeature leaf -- faithful, not a guess (the emitted source runs exactly as written).
		var g = translate('
			strategy NonLiteralTest {
				smoothed = sma(close, 5)
				onBar {
					when macd(smoothed).hist > 0: long()
				}
			}
		');
		Assert.notNull(g, "fail-open: a non-literal macd() arg should translate to an opaque leaf, not skip");
		var src = Expand.expand(g);
		// The prelude binding MUST be fully inlined into the opaque leaf -- the genome carries no
		// prelude, so a leaf still mentioning the local `smoothed` would reference an undefined name.
		Assert.isTrue(StringTools.contains(src, "sma(close, 5)") || StringTools.contains(src, "sma(close,5)"),
			'expected the prelude binding inlined into the opaque leaf: $src');
		Assert.isFalse(StringTools.contains(src, "smoothed"),
			'opaque leaf must not reference the undefined prelude local: $src');
	}
}

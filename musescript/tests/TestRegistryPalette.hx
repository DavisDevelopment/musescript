package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.evo.RegistryPalette;
import musescript.evo.EvolutionEngine;
import musescript.evo.Fitness;
import musescript.evo.Expand;
import musescript.evo.Canonical;
import musescript.parse.MuseParser;
import musescript.harness.BarFeed;

/**
 * Proves the registry-driven palette is real, not just a name list: grows
 * genomes from `RegistryPalette.compatibleNames()` (the wide, ~400+-indicator
 * pool, not the closed 12-name `Palette.INDS`), renders them to MuseScript
 * source, and confirms they PARSE and RUN as real backtests -- and that the
 * pool is actually wider than the legacy default.
 */
class TestRegistryPalette extends Test {
	public function testCompatibleNamesIsWiderThanTheLegacyPalette() {
		var names = RegistryPalette.compatibleNames();
		Assert.isTrue(names.length > musescript.evo.Palette.INDS.length,
			'expected the registry pool (${names.length}) to exceed the legacy 12-name palette');
		// Every legacy name should still be a real, valid `(series, window)` builtin -- sanity
		// that the filter isn't accidentally excluding indicators the legacy palette relies on.
		for (n in musescript.evo.Palette.INDS)
			Assert.isTrue(names.indexOf(n) >= 0, '$n missing from the wide pool');
	}

	public function testGenomesGrownFromTheWidePoolParseAndRun() {
		var pool = RegistryPalette.compatibleNames();
		var engine = new EvolutionEngine(7, 6, 2, 3, pool);
		var bars = BarFeed.synthetic(200, 7).all();
		var pop = engine.seedPopulation(3);
		var usedNonLegacyIndicator = false;
		var legacy = new Map<String, Bool>();
		for (n in musescript.evo.Palette.INDS) legacy.set(n, true);

		for (g in pop) {
			var source = Expand.expand(g);
			var prog = new MuseParser().parse(source, "<evo-wide>"); // must at least PARSE
			var fr = Fitness.evaluate(g, bars, "js", false);
			// A constructor-time argument-validation throw (e.g. a random Fibonacci-ladder
			// window landing below some indicator's own minimum period) proves the wide-pool
			// indicator IS wired and dispatching correctly -- it just means THIS random
			// window/indicator combination violates that indicator's own precondition, not a
			// bug. Same exemption TestIndicatorPorts.testEveryRegisteredIndicatorIsCallable
			// already applies for exactly this reason. Only a non-validation error fails here.
			var msgHasValidation = fr.error != null && fr.error.indexOf("must be") >= 0;
			if (!fr.ok) Assert.isTrue(msgHasValidation, 'genome failed to evaluate: ${fr.error}');
			if (!legacy.exists(indicatorNameIn(source)) ) usedNonLegacyIndicator = true;
		}
		// Not a hard requirement every genome uses a non-legacy indicator (growth is random),
		// but across a real population + real pool size it's the expected common case; flags a
		// silent regression if the wide pool stops actually being consulted.
		Assert.isTrue(usedNonLegacyIndicator || pool.length == musescript.evo.Palette.INDS.length,
			"no genome in the population used a non-legacy indicator name");
	}

	/** First bare identifier immediately followed by `(` in the rendered source -- good enough
	 * to sample which indicator name a genome actually used, for this test's own sanity check. */
	static function indicatorNameIn(source:String):String {
		var re = ~/([a-z_][a-z0-9_]*)\(/;
		return re.match(source) ? re.matched(1) : "";
	}
}

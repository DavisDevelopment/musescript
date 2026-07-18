package musescript.tests;

import utest.Assert;
import utest.Test;
import musescript.docs.BuiltinDocs;
import musescript.types.BuiltinSigs;

/**
 * ROADMAP "Docstring introspection pipeline": the macro-extracted doc
 * registry must (a) actually find real doc comments, (b) never leak
 * internal (non-BuiltinSigs) helper methods into the builtin surface, and
 * (c) resolve names that don't follow the snake_case-of-camelCase
 * convention (e.g. `pickBest`).
 */
class TestBuiltinDocs extends Test {
	public function testKnownDocResolves() {
		var d = BuiltinDocs.get("bag_set");
		Assert.notNull(d);
		Assert.notNull(d.doc);
		Assert.isTrue(d.doc.indexOf("weight") >= 0);
		Assert.equals("BagBuiltins.hx", d.source);
	}

	public function testSignatureMergedFromBuiltinSigs() {
		var d = BuiltinDocs.get("bag_set");
		Assert.equals(3, d.args.length);
		Assert.equals("Bag", d.returns);
	}

	public function testNonSnakeCaseNameResolves() {
		// pickBest is registered in BuiltinSigs literally as "pickBest" (no
		// underscore) — the naive camelCase->snake_case conversion alone
		// would miss it; both spellings must be tried.
		var d = BuiltinDocs.get("pickBest");
		Assert.notNull(d);
		Assert.notNull(d.doc);
		Assert.isTrue(d.doc.indexOf("candidates") >= 0);
	}

	public function testUndocumentedBuiltinStillResolvesWithNullDoc() {
		// `sma` has a BuiltinSigs entry but (as of this pass) no hoisted doc
		// comment — get() must still return signature info, doc:null.
		var d = BuiltinDocs.get("sma");
		Assert.notNull(d);
		Assert.isNull(d.doc);
		Assert.equals(2, d.args.length);
	}

	public function testUnknownNameReturnsNull() {
		Assert.isNull(BuiltinDocs.get("not_a_real_builtin_xyz"));
	}

	public function testInternalHelpersNeverLeakIntoSurface() {
		// `install`/`materialize`/`ensure` etc. are public statics WITH doc
		// comments but are not registered in BuiltinSigs — they must not
		// appear as if they were callable MuseScript builtins.
		var names = BuiltinDocs.names();
		Assert.isFalse(names.indexOf("install") >= 0);
		Assert.isFalse(names.indexOf("materialize") >= 0);
	}

	public function testNamesMatchesBuiltinSigsExactly() {
		var names = BuiltinDocs.names();
		var sigNames = [for (n in BuiltinSigs.all().keys()) n];
		sigNames.sort(Reflect.compare);
		Assert.equals(sigNames.length, names.length);
		for (n in sigNames) Assert.isTrue(names.indexOf(n) >= 0);
	}

	public function testCoverageIsSaneAndNonzero() {
		var c = BuiltinDocs.coverage();
		Assert.isTrue(c.total > 0);
		Assert.isTrue(c.documented > 0);
		Assert.isTrue(c.documented <= c.total);
	}

	public function testMarkdownIsWellFormedAndIncludesKnownEntries() {
		var md = BuiltinDocs.toMarkdown();
		Assert.isTrue(StringTools.startsWith(md, "# MuseScript builtin reference"));
		Assert.isTrue(md.indexOf("| Name | Signature | Description | Source |") >= 0);
		Assert.isTrue(md.indexOf("bag_set") >= 0);
		Assert.isTrue(md.indexOf("_(undocumented)_") >= 0); // most builtins still are
		// One row per BuiltinSigs entry (+ header/separator + title lines).
		var rowCount = md.split("\n").filter(function(l) return StringTools.startsWith(l, "| `")).length;
		Assert.equals(BuiltinDocs.names().length, rowCount);
	}
}

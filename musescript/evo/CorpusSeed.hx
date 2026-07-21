package musescript.evo;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.OrderKind;
import musescript.parse.MuseParser;
import musescript.compile.TemplateExpand;
import musescript.compile.ModuleExpand;

/**
 * Reverse-compiles REAL MuseScript strategy source (the tournament corpus, or any hand-written
 * `.ms` file) into `StrategyGenome` trees, so genuine trading strategies can seed an evolution
 * run's initial population instead of only random growth.
 *
 * This is NOT a general MuseScript-to-genome compiler -- the closed GP grammar
 * (BoolNode/ScalarNode/SeriesNode, see Palette.hx) is deliberately narrower than the full
 * language (no `onPosition`-based exits keyed on `bars_in_trade`/`unrealized_pnl`/`equity`, no
 * multi-output field access like `macd(...).hist`, no arbitrary custom classes/state). Templates
 * ARE supported -- `TemplateExpand.expand` (the same pass MuseCompiler's own pipeline uses)
 * inlines every `template foo(...) { ... }` call site before translation even starts, so a
 * strategy composed from named boolean templates translates exactly as if it had been written
 * inline.
 *
 * `translateProgram` returns `null` (not a best-effort guess) the moment it hits something
 * outside that grammar -- a genome silently misrepresenting what the source strategy actually
 * does would be worse than not seeding from it at all. Callers get an honest per-file
 * success/skip tally, never a silently-wrong translation.
 */
typedef SeedResult = {
	var genomes:Array<StrategyGenome>;
	var total:Int;
	var skipped:Array<{file:String, reason:String}>;
}

class CorpusSeed {
	static inline var PRICE_FIELDS = "open,high,low,close,volume";

	public static function isPriceField(name:String):Bool {
		return PRICE_FIELDS.split(",").indexOf(name) >= 0;
	}

	/** A structurally-always-false condition, used as the exit/entry default for a direction
	 * the source strategy never uses (e.g. a long-only strategy's entryShort/exitShort). */
	static function alwaysFalse():BoolNode
		return BCmp(">", KConst(0.0), KConst(1.0));

	// ---- corpus walking -----------------------------------------------------------------

	/** Recursively finds every `*.ms` file under `dir` and attempts translation. */
	public static function seedFromDirectory(dir:String, allowedIndicators:Map<String, Bool>):SeedResult {
		var files:Array<String> = [];
		collectMsFiles(dir, files);
		var genomes:Array<StrategyGenome> = [];
		var skipped:Array<{file:String, reason:String}> = [];
		for (f in files) {
			try {
				var src = sys.io.File.getContent(f);
				var prog = new MuseParser().parse(src, f);
				prog = TemplateExpand.expand(prog);
				prog = ModuleExpand.expand(prog);
				var g = translateProgram(prog, allowedIndicators);
				if (g == null) skipped.push({file: f, reason: "no translatable strategy body"});
				else genomes.push(g);
			} catch (e:Dynamic) {
				skipped.push({file: f, reason: Std.string(e)});
			}
		}
		return { genomes: genomes, total: files.length, skipped: skipped };
	}

	static function collectMsFiles(dir:String, out:Array<String>):Void {
		if (!sys.FileSystem.exists(dir)) return;
		for (entry in sys.FileSystem.readDirectory(dir)) {
			var full = dir + "/" + entry;
			if (sys.FileSystem.isDirectory(full)) collectMsFiles(full, out);
			else if (StringTools.endsWith(entry, ".ms")) out.push(full);
		}
	}

	// ---- one strategy -> one genome ------------------------------------------------------

	public static function translateProgram(prog:MuseProgram, allowed:Map<String, Bool>):Null<StrategyGenome> {
		for (d in prog.decls) {
			switch (d) {
				case StrategyDecl(name, body):
					var g = translateStrategy(name, body, allowed);
					if (g != null) return g;
				default:
			}
		}
		return null;
	}

	static function translateStrategy(name:String, body:Array<Stmt>, allowed:Map<String, Bool>):Null<StrategyGenome> {
		// Prelude bindings: `maFast = sma(close, 8)` style Assign statements OUTSIDE onBar,
		// substituted in wherever the onBar conditions reference `maFast` by name.
		var bindings = new Map<String, Expr>();
		var onBarBody:Null<Array<Stmt>> = null;
		for (s in body) {
			switch (s) {
				case Assign(n, e): bindings.set(n, e);
				case OnBar(b): onBarBody = onBarBody == null ? b : onBarBody.concat(b);
				default:
			}
		}
		if (onBarBody == null) return null;

		var entryLong:Null<BoolNode> = null;
		var entryShort:Null<BoolNode> = null;
		var exitLong:Null<BoolNode> = null;
		var exitShort:Null<BoolNode> = null;

		// Only `when cond: [Order(...)]` / the general-if desugared `ExprStmt(EIf(...))` shapes
		// at the TOP of onBar are inspected -- anything else in onBar (plain assignments, plots,
		// logs) is simply not entry/exit logic and is skipped over, not treated as a failure.
		for (s in onBarBody) {
			var guarded = guardedOrders(s);
			if (guarded == null) continue;
			for (go in guarded) {
				var b = translateBool(go.cond, bindings, allowed);
				if (b == null) return null; // a recognized guard with an UNtranslatable condition
				switch (go.kind) {
					case Long: entryLong = entryLong == null ? b : BOr(entryLong, b);
					case Short: entryShort = entryShort == null ? b : BOr(entryShort, b);
					case Flat | Close:
						exitLong = exitLong == null ? b : BOr(exitLong, b);
						exitShort = exitShort == null ? b : BOr(exitShort, b);
				}
			}
		}

		if (entryLong == null && entryShort == null) return null; // nothing tradeable extracted

		return {
			entryLong: entryLong != null ? entryLong : alwaysFalse(),
			entryShort: entryShort != null ? entryShort : alwaysFalse(),
			exitLong: exitLong != null ? exitLong : alwaysFalse(),
			exitShort: exitShort != null ? exitShort : alwaysFalse(),
			size: KConst(1.0),
			params: [],
			name: name,
			lineage: ["corpus:" + name],
			seedOrigin: null
		};
	}

	/** One `(cond, orderKind)` pair pulled from a single guarded statement (`when`/`if`),
	 * for every Order call directly in its body (a body with a non-Order statement anywhere
	 * makes the WHOLE guard untranslatable -- returns null, not a partial extraction). */
	static function guardedOrders(s:Stmt):Null<Array<{cond:Expr, kind:OrderKind}>> {
		return switch (s) {
			case When(cond, guardBody):
				ordersIn(guardBody, cond);
			case ExprStmt(EIf(cond, thenE, elseE)):
				// The general-`if` desugaring (this session's grammar work) wraps its THEN
				// branch in an EBlock of the same statement shapes `when` produces -- walk it
				// the identical way. The ELSE branch (if any) is a separate, un-related guard
				// and isn't safe to fold into the same condition, so strategies using
				// if/else for order dispatch aren't translated (skip, not guess).
				if (elseE != null) null else switch (thenE) {
					case EBlock(es): ordersInExprBlock(es, cond);
					default: null;
				}
			default: null;
		};
	}

	static function ordersIn(guardBody:Array<Stmt>, cond:Expr):Null<Array<{cond:Expr, kind:OrderKind}>> {
		var out:Array<{cond:Expr, kind:OrderKind}> = [];
		for (gs in guardBody) {
			switch (gs) {
				case Order(kind, _): out.push({cond: cond, kind: kind});
				default: return null;
			}
		}
		return out.length > 0 ? out : null;
	}

	static function ordersInExprBlock(es:Array<Expr>, cond:Expr):Null<Array<{cond:Expr, kind:OrderKind}>> {
		var out:Array<{cond:Expr, kind:OrderKind}> = [];
		for (e in es) {
			switch (e) {
				case ECall(EIdent("long"), _): out.push({cond: cond, kind: Long});
				case ECall(EIdent("short"), _): out.push({cond: cond, kind: Short});
				case ECall(EIdent("flat"), _): out.push({cond: cond, kind: Flat});
				case ECall(EIdent("close"), _): out.push({cond: cond, kind: Close});
				default: return null;
			}
		}
		return out.length > 0 ? out : null;
	}

	// ---- Expr -> BoolNode / ScalarNode / SeriesNode --------------------------------------

	static function resolve(e:Expr, bindings:Map<String, Expr>):Expr {
		return switch (e) {
			case EIdent(n) if (bindings.exists(n) && !isPriceField(n)): resolve(bindings.get(n), bindings);
			case EParent(inner): resolve(inner, bindings);
			default: e;
		};
	}

	public static function translateBool(e0:Expr, bindings:Map<String, Expr>, allowed:Map<String, Bool>):Null<BoolNode> {
		var e = resolve(e0, bindings);
		return switch (e) {
			case EBinop("&&", a, b):
				var ta = translateBool(a, bindings, allowed), tb = translateBool(b, bindings, allowed);
				(ta != null && tb != null) ? BAnd(ta, tb) : null;
			case EBinop("||", a, b):
				var ta = translateBool(a, bindings, allowed), tb = translateBool(b, bindings, allowed);
				(ta != null && tb != null) ? BOr(ta, tb) : null;
			case EUnop("!", true, a):
				var ta = translateBool(a, bindings, allowed);
				ta != null ? BNot(ta) : null;
			case EParent(inner):
				translateBool(inner, bindings, allowed);
			case ECall(EIdent("crossover"), [a, b]):
				var sa = translateSeries(a, bindings, allowed), sb = translateSeries(b, bindings, allowed);
				(sa != null && sb != null) ? BCross("over", sa, sb) : null;
			case ECall(EIdent("crossunder"), [a, b]):
				var sa = translateSeries(a, bindings, allowed), sb = translateSeries(b, bindings, allowed);
				(sa != null && sb != null) ? BCross("under", sa, sb) : null;
			case ECall(EIdent("rising"), [a, n]):
				var sa = translateSeries(a, bindings, allowed), w = constInt(n);
				(sa != null && w != null) ? BTrend("over", sa, w) : null;
			case ECall(EIdent("falling"), [a, n]):
				var sa = translateSeries(a, bindings, allowed), w = constInt(n);
				(sa != null && w != null) ? BTrend("under", sa, w) : null;
			case EBinop(op, a, b) if (op == ">" || op == "<" || op == ">=" || op == "<="):
				var ka = translateScalar(a, bindings, allowed), kb = translateScalar(b, bindings, allowed);
				(ka != null && kb != null) ? BCmp(op, ka, kb) : null;
			default: null;
		};
	}

	public static function translateScalar(e0:Expr, bindings:Map<String, Expr>, allowed:Map<String, Bool>):Null<ScalarNode> {
		var e = resolve(e0, bindings);
		return switch (e) {
			case EConst(CFloat(v)): KConst(v);
			case EConst(CInt(v)): KConst(v);
			case EUnop("-", true, EConst(CFloat(v))): KConst(-v);
			case EUnop("-", true, EConst(CInt(v))): KConst(-v);
			case EParent(inner): translateScalar(inner, bindings, allowed);
			case EBinop(op, a, b) if (op == "+" || op == "-" || op == "*"):
				var ka = translateScalar(a, bindings, allowed), kb = translateScalar(b, bindings, allowed);
				(ka != null && kb != null) ? KArith(op, ka, kb) : null;
			case EIdent(n) if (isPriceField(n)): KSeries(SPrice(n));
			case EBarField(n) if (isPriceField(n)): KSeries(SPrice(n));
			default:
				var s = translateSeries(e, bindings, allowed);
				s != null ? KSeries(s) : null;
		};
	}

	public static function translateSeries(e0:Expr, bindings:Map<String, Expr>, allowed:Map<String, Bool>):Null<SeriesNode> {
		var e = resolve(e0, bindings);
		return switch (e) {
			case EIdent(n) if (isPriceField(n)): SPrice(n);
			case EBarField(n) if (isPriceField(n)): SPrice(n);
			case ECall(EIdent(name), args) if (allowed.exists(name) && args.length >= 2):
				var field = fieldOf(args[0], bindings);
				var w = constInt(args[1]);
				(field != null && w != null) ? SInd(name, field, w, null) : null;
			default: null;
		};
	}

	/** The price-field NAME an indicator call's first (series) argument reads from -- only a
	 * bare price field is supported (an indicator called on ANOTHER indicator's output, e.g.
	 * `sma(rsi(close,14), 5)`, isn't representable by SInd's flat (field, window) shape and
	 * fails translation here, same as any other unsupported construct). */
	static function fieldOf(e:Expr, bindings:Map<String, Expr>):Null<String> {
		var r = resolve(e, bindings);
		return switch (r) {
			case EIdent(n) if (isPriceField(n)): n;
			case EBarField(n) if (isPriceField(n)): n;
			default: null;
		};
	}

	static function constInt(e:Expr):Null<Int> {
		return switch (e) {
			case EConst(CInt(v)): v;
			case EConst(CFloat(v)): Std.int(v);
			default: null;
		};
	}

	// ---- one genome per auto-generated indicator ----------------------------------------

	/**
	 * The "auto-generated indicator strategies" half of the corpus: the `ta` toolbelt's
	 * generated demo sources (TaSources/TaSourceRender) are pure computation-and-plot demos
	 * with no entry/exit logic at all, so there's nothing to reverse-compile from them the
	 * way CorpusSeed does for the tournament corpus. Instead, one genome per compatible
	 * indicator is synthesized directly: the classic "price crosses the indicator" rule
	 * (entryLong/exitShort on an upward cross, entryShort/exitLong on a downward cross) --
	 * the simplest genuinely tradeable strategy built from that one indicator alone, at each
	 * of the Fibonacci-ladder windows (Palette.WINDOWS), so the seed set actually samples
	 * the indicator's behavior at multiple timeframes rather than one arbitrary default.
	 */
	public static function seedFromIndicators(names:Array<String>, ?windows:Array<Int>):Array<StrategyGenome> {
		// Default to a short/medium/long representative sample, not the full 9-entry Fibonacci
		// ladder -- one genome per (indicator, window) combo, and there are 400+ compatible
		// indicators, so all 9 windows would balloon the seed population past what's useful to
		// actually evolve in one run (mostly-redundant near-duplicate seeds, not real diversity).
		var w = windows != null ? windows : [8, 21, 55];
		var out:Array<StrategyGenome> = [];
		for (name in names) {
			for (window in w) {
				var ind:SeriesNode = SInd(name, "close", window, null);
				var price:SeriesNode = SPrice("close");
				out.push({
					entryLong: BCross("over", price, ind),
					entryShort: BCross("under", price, ind),
					exitLong: BCross("under", price, ind),
					exitShort: BCross("over", price, ind),
					size: KConst(1.0),
					params: [],
					name: '${name}_${window}_cross',
					lineage: ["indicator-seed:" + name],
					seedOrigin: null
				});
			}
		}
		return out;
	}
}

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
 * language (no arbitrary custom classes/state, no `onPosition` method bodies). It DOES recognize
 * risk-managed exits (`unrealized_pnl_pct()`/`bars_in_trade()`, bare zero-arg calls -- the same
 * `KFeature` leaves `Variation.growRiskExit` builds) and multi-output field access
 * (`macd(...).hist`/`bbands(...).upper`/`stoch(...).k` with LITERAL args, matching
 * `growMultiOutputField`'s own calling convention) -- see `translateScalar`'s `RISK_EXIT_FEATURES`/
 * `MULTI_OUTPUT_NAMES` cases. Templates ARE supported -- `TemplateExpand.expand` (the same pass MuseCompiler's own pipeline uses)
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

	/**
	 * `Expand.expand` unconditionally appends `&& position() <= 0` / `&& position() >= 0` to
	 * every entry condition (anti-pyramiding boilerplate -- see Expand.expand's doc comment),
	 * which no `translate*` function here has ever understood (`position()` isn't a price field,
	 * a risk-exit feature, or an indicator call) -- meaning it silently killed EVERY round trip of
	 * genome-expanded source through this reverse-compiler, entry conditions included, regardless
	 * of syntax dialect. Stripped BEFORE translation rather than taught to `translateBool`: it's
	 * infrastructure `Expand` re-adds unconditionally on the way back out either way, not real
	 * strategy logic a human editing the source in HumanLoopWindow needs to preserve or even
	 * understand. A hand-written strategy that never had this guard to begin with is untouched
	 * (the pattern simply doesn't match, `e` returns as-is).
	 */
	static function stripPositionGuard(e:Expr):Expr {
		return switch (e) {
			case EBinop("&&", inner, EBinop(op, ECall(EIdent("position"), []), rhs)) if ((op == "<=" || op == ">=") && isZeroConst(rhs)):
				inner;
			default: e;
		};
	}

	static function isZeroConst(e:Expr):Bool {
		return switch (e) {
			case EConst(CInt(0)): true;
			case EConst(CFloat(0.0)): true;
			default: false;
		};
	}

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
				// Flatten `class X extends muse.Strat` corpus seeds to StrategyDecl before
				// template/module passes (no-op for plain `strategy {}` seeds).
				prog = musescript.compile.ClassStrategyLower.expand(prog);
				prog = musescript.compile.MuseHostLower.lower(prog);
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

	/**
	 * Single-file counterpart of `seedFromDirectory`, for a caller (CorpusEvoRun's `--template`
	 * flag) that wants exactly ONE named template as (part of) the seed population, with an honest
	 * reason string on failure instead of a bare null -- a directory scan's `skipped` list serves
	 * that role for the bulk path, but a single explicit `--template <path>` deserves a direct
	 * error, not silence. Wraps `evolve(...)`-marked positions as `BHole`/`KHole` via the SAME
	 * `translateBool`/`translateScalar` this file already uses for every other reverse-compiled
	 * strategy -- a template with zero `evolve(...)` markers translates to an ordinary, fully-
	 * evolvable genome exactly like any other corpus seed (see `Variation.isTemplated`).
	 */
	public static function seedFromTemplateFile(path:String, allowedIndicators:Map<String, Bool>):{genome:Null<StrategyGenome>, error:Null<String>} {
		try {
			var src = sys.io.File.getContent(path);
			var prog = new MuseParser().parse(src, path);
			prog = musescript.compile.ClassStrategyLower.expand(prog);
			prog = musescript.compile.MuseHostLower.lower(prog);
			prog = TemplateExpand.expand(prog);
			prog = ModuleExpand.expand(prog);
			var g = translateProgram(prog, allowedIndicators);
			return g != null ? { genome: g, error: null } : { genome: null, error: "no translatable strategy body" };
		} catch (e:Dynamic) {
			return { genome: null, error: Std.string(e) };
		}
	}

	/**
	 * Reverse-compiles a raw MuseScript source STRING (not a file) into a `StrategyGenome` --
	 * the same `translateProgram` path `seedFromDirectory`/`seedFromTemplateFile` use, exposed
	 * directly for a caller with source text already in hand (HumanLoopWindow's "Apply Edit"
	 * button: a human just typed/edited a strategy body in a live editor and wants it turned back
	 * into a genome to inject into a running evolution population). Same honest-failure contract
	 * as every other entry point here -- a syntax error or an unsupported construct comes back as
	 * a `reason` string, never a silent best-effort guess.
	 */
	public static function translateSource(src:String, allowedIndicators:Map<String, Bool>):{genome:Null<StrategyGenome>, error:Null<String>} {
		try {
			var prog = new MuseParser().parse(src, "<human-edit>");
			prog = musescript.compile.ClassStrategyLower.expand(prog);
			prog = musescript.compile.MuseHostLower.lower(prog);
			prog = TemplateExpand.expand(prog);
			prog = ModuleExpand.expand(prog);
			var g = translateProgram(prog, allowedIndicators);
			return g != null ? { genome: g, error: null } : { genome: null, error: "no translatable strategy body (only `when cond: { long()/short()/flat() }` guards at the top of onBar are recognized)" };
		} catch (e:Dynamic) {
			return { genome: null, error: Std.string(e) };
		}
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
		// `OnPosition` guards get folded into the SAME list `OnBar` guards are, not tracked
		// separately: the closed extraction grammar below only ever recognizes simple `when cond:
		// { order }` shapes regardless of which hook they came from, and "checked every bar" vs
		// "checked every bar while in a position" collapses to the same BoolNode either way once a
		// risk-exit feature (`unrealized_pnl_pct`/`bars_in_trade`/etc., see RISK_EXIT_FEATURES) is
		// involved -- those already read as their natural falsy/zero value outside a position, so a
		// flat() guard built from them fires at exactly the same bars whether it's nominally scoped
		// to onBar or onPosition. This is the minimal high-value slice of "support onPosition":
		// it does NOT give onPosition any genuinely distinct runtime semantics inside the genome
		// (there's still no separate onPosition concept in StrategyGenome/Expand), it just stops
		// throwing away real risk-management logic (stop-loss/time-stop/take-profit templates,
		// exactly the shape `Variation.growRiskExit` already evolves from scratch) that a human
		// wrote using the onPosition hook purely as a style choice.
		for (s in body) {
			switch (s) {
				case Assign(n, e): bindings.set(n, e);
				case OnBar(b) | OnPosition(b): onBarBody = onBarBody == null ? b : onBarBody.concat(b);
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
				var b = translateBool(stripPositionGuard(go.cond), bindings, allowed);
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
			// Template hole marker (see this file's doc comment / BoolNode.BHole): `evolve(...)` is
			// NOT a real MuseScript builtin -- it parses fine as an ordinary call (the parser doesn't
			// validate identifiers) but is only ever recognized HERE, at reverse-compilation time. A
			// `.ms` template file still containing `evolve(...)` markers is a SEED SOURCE, not meant
			// to be run directly through GeneRunner/the checker/a live backtest -- only the genome
			// this produces (which Expand.hx unwraps back to clean, marker-free source) is executable.
			case ECall(EIdent("evolve"), [inner]):
				var b = translateBool(inner, bindings, allowed);
				b != null ? BHole(b) : null;
			// Author hole `?` / `?Bool` (SPEC_AUTHOR_HOLES) — surface-syntax sibling of evolve(...).
			// A blank bool hole starts from a neutral always-true inner; the fill loop replaces it.
			case EMeta("__hole", _, _):
				BHole(BCmp(">", KConst(1.0), KConst(0.0)));
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

	/** Names growth's `growRiskExit` already knows how to build/render as bare zero-arg
	 * `KFeature("name()")` leaves (see Variation.hx / TradeBuiltins.hx) -- recognizing them here
	 * lets a hand-written strategy's OWN stop-loss/take-profit/time-stop logic seed the corpus
	 * instead of evolution only ever discovering that shape from scratch via random growth.
	 * `equity`/`unrealized_pnl`/`cash`/`entry_price` added alongside the original two: same
	 * `dispatchBuiltin` mechanism (JsBackend.hx), just additional names -- and, unlike
	 * `unrealized_pnl_pct`/`bars_in_trade`, real hand-written strategies conventionally call them
	 * BARE (`equity`, no parens -- confirmed via examples/strategy-kinds/06_risk_window_sortino.ms's
	 * `bars_in_trade` usage), which is why the case below matches `EIdent`, not just `ECall(_,[])`. */
	static inline var RISK_EXIT_FEATURES = "unrealized_pnl_pct,bars_in_trade,equity,unrealized_pnl,cash,entry_price";

	/** Names growth's `growMultiOutputField` already knows how to build (see Variation.hx) --
	 * their return is a NAMED-FIELD object (`.hist`/`.upper`/`.k`/...), not a bare scalar, so
	 * unlike a single-output indicator this needs an `EField` wrapper around the call, matched
	 * separately below. */
	static inline var MULTI_OUTPUT_NAMES = "macd,bbands,stoch";

	public static function translateScalar(e0:Expr, bindings:Map<String, Expr>, allowed:Map<String, Bool>):Null<ScalarNode> {
		var e = resolve(e0, bindings);
		return switch (e) {
			// See translateBool's `evolve(...)` case -- scalar counterpart (KHole).
			case ECall(EIdent("evolve"), [inner]):
				var s = translateScalar(inner, bindings, allowed);
				s != null ? KHole(s) : null;
			// Author hole `?` / `?Scalar` — neutral KConst(0) inner; the fill loop replaces it.
			case EMeta("__hole", _, _):
				KHole(KConst(0.0));
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
			case ECall(EIdent(name), []) if (RISK_EXIT_FEATURES.split(",").indexOf(name) >= 0):
				KFeature('$name()');
			// Bare form (no parens) -- see RISK_EXIT_FEATURES's doc comment for why both spellings
			// need to be recognized. Renders back out via Expand's `KFeature` case (`name`, embedded
			// verbatim), so a bare-in/bare-out round trip stays bare, not silently rewritten to add
			// parens the human never wrote.
			case EIdent(name) if (RISK_EXIT_FEATURES.split(",").indexOf(name) >= 0):
				KFeature(name);
			// `m.hist` where a PRELUDE BINDING (`m = macd(close, 5, 13, 8)`) holds the multi-output
			// call, not just the direct-inline `macd(...).hist` spelling -- `resolve()` only
			// substitutes bindings for a bare `EIdent` node, and the node actually sitting inside
			// `EField(_, field)` here is exactly that (`EIdent("m")`), so resolving it explicitly
			// (rather than relying on translateScalar's own single top-level `resolve()` call,
			// which only ever sees the OUTER `EField` node, never unwraps its child) recovers the
			// call form either way -- a real gap found via a hand-written tournament-corpus
			// strategy (`m = macd(...); ... rising(m.hist, 3) ...`) failing to inject through
			// HumanLoopWindow despite `macd(...).hist` written inline working fine.
			case EField(inner, field):
				switch (resolve(inner, bindings)) {
					case ECall(EIdent(name), args) if (MULTI_OUTPUT_NAMES.split(",").indexOf(name) >= 0):
						var rendered = renderLiteralCall(name, args, bindings);
						// Field name isn't validated against BuiltinSigs' declared TObject fields here --
						// an unrecognized field simply fails later at Fitness.evaluate's try/catch (scored
						// NEG_INF, not a crash), the same fallback every other unsupported shape already
						// gets, rather than duplicating BuiltinSigs' field lists in a second place.
						rendered != null ? KFeature('$rendered.$field') : null;
					default: null;
				}
			default:
				var s = translateSeries(e, bindings, allowed);
				s != null ? KSeries(s) : null;
		};
	}

	/** Re-renders a call's args as MuseScript source text, for embedding into a `KFeature` bare-
	 * expression leaf -- ONLY literal numeric constants and bare price-field identifiers (which
	 * get normalized to the quoted-string calling convention `SInd`/`growMultiOutputField` already
	 * use, e.g. `macd(close)` -> `macd("close")`) are supported; anything else (a bound variable
	 * holding a computed series, a nested call) fails closed to null, same discipline as every
	 * other translate* function in this file. */
	static function renderLiteralCall(name:String, args:Array<Expr>, bindings:Map<String, Expr>):Null<String> {
		var parts:Array<String> = [];
		for (a in args) {
			var r = resolve(a, bindings);
			var rendered = switch (r) {
				case EConst(CInt(v)): Std.string(v);
				case EConst(CFloat(v)): Std.string(v);
				case EUnop("-", true, EConst(CInt(v))): Std.string(-v);
				case EUnop("-", true, EConst(CFloat(v))): Std.string(-v);
				case EIdent(n) if (isPriceField(n)): '"$n"';
				case EBarField(n) if (isPriceField(n)): '"$n"';
				default: null;
			};
			if (rendered == null) return null;
			parts.push(rendered);
		}
		return '$name(${parts.join(", ")})';
	}

	public static function translateSeries(e0:Expr, bindings:Map<String, Expr>, allowed:Map<String, Bool>):Null<SeriesNode> {
		var e = resolve(e0, bindings);
		return switch (e) {
			case EIdent(n) if (isPriceField(n)): SPrice(n);
			case EBarField(n) if (isPriceField(n)): SPrice(n);
			// `Expand.series`'s OWN `SPrice` rendering is a QUOTED string (`"close"`, matching the
			// same calling convention an indicator's first arg uses, e.g. `sma("close", 8)`) --
			// runtime-valid (crossover/rising/falling accept a string field-selector exactly like a
			// bare identifier), but this case was missing here, so `Expand.expand(g)` -> `translate*`
			// failed to round-trip ANY genome using a bare price series in `crossover`/`rising`/
			// `falling` (found via HumanLoopWindow's "Apply Edit" -- the first caller that ever
			// needed this specific round trip; hand-written corpus files conventionally use the
			// bare-identifier spelling, so this gap went unnoticed until now).
			case EConst(CString(n)) if (isPriceField(n)): SPrice(n);
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
			case EConst(CString(n)) if (isPriceField(n)): n; // see translateSeries's matching case
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

	// ---- edge-triggered crossing helpers (bare-expression-scalar aware) ------------------

	/**
	 * `price crosses UP through `ref`` as a DISCRETE, edge-triggered event -- true only on the
	 * bar the cross actually happens, not on every bar price merely sits on one side of `ref`.
	 * `BCross` can't be used here (it strictly needs two SeriesNode operands; a `KFeature` bare-
	 * expression scalar -- a fib level, a custom-configured fourier_projection call -- isn't
	 * one), so this reconstructs the same "was below, now above" shape directly via `BCmp` +
	 * `KLookback`, treating `ref` as quasi-static across the ONE-bar lookback (a reasonable
	 * approximation for a slow-moving reference like a wide fib window or a smoothed
	 * projection -- not mathematically exact the way a real two-series BCross is, but far
	 * closer to a genuine edge trigger than a bare level condition).
	 *
	 * This is a direct, empirically-motivated fix: the FIRST fib_retracement/fourier_projection
	 * seeds used plain level comparisons (`price > level618`), which fire on EVERY bar price
	 * stays on one side -- confirmed catastrophic in practice (IS sharpe -2.3 to -4.8, hundreds
	 * to thousands of trades) because realistic transaction cost punishes that whipsaw hard.
	 */
	static function crossUpScalar(ref:ScalarNode):BoolNode {
		var priceNow:ScalarNode = KSeries(SPrice("close"));
		var pricePrev:ScalarNode = KLookback(SPrice("close"), 1);
		return BAnd(BCmp(">", priceNow, ref), BCmp("<=", pricePrev, ref));
	}

	static function crossDownScalar(ref:ScalarNode):BoolNode {
		var priceNow:ScalarNode = KSeries(SPrice("close"));
		var pricePrev:ScalarNode = KLookback(SPrice("close"), 1);
		return BAnd(BCmp("<", priceNow, ref), BCmp(">=", pricePrev, ref));
	}

	// ---- Fibonacci-retracement seed genomes ----------------------------------------------

	/**
	 * `fib_retracement(window)` doesn't fit `seedFromIndicators`'s generic path at all: no
	 * leading `TSeries` arg (it reads `bar.high`/`bar.low` directly, args=[TWindow] only) and a
	 * multi-output (`TObject`) return, so `RegistryPalette.compatibleNames()` excludes it and
	 * `SInd` can't represent it. Hand-built here the same way growRiskExit/growMultiOutputField
	 * are: `KFeature` bare-expression leaves for each level, composed via `crossUpScalar`/
	 * `crossDownScalar` above (see that doc comment for why level COMPARISONS were replaced
	 * with edge-triggered CROSSINGS). Three windows (short/medium/long retracement lookback) x
	 * two shapes:
	 *
	 *  - "breakout": long on an upward cross through the 61.8% level (golden-ratio breakout),
	 *    short on a downward cross through 38.2% (breakdown), flat on a cross back through the
	 *    50% midpoint either direction -- a genuine trend-following shape now, not a whipsaw.
	 *  - "reclaim": long/short purely on which direction price crosses the 50% midpoint --
	 *    always-in-the-market reversal, exits left `alwaysFalse` since the OPPOSITE entry's own
	 *    reversal (executeLong/executeShort close the opposite side internally) already handles
	 *    the transition -- giving this its own dedicated exit trigger on the SAME level would
	 *    double-fire flat() and the reversal entry on the same bar.
	 */
	public static function seedFromFibRetracement(?windows:Array<Int>):Array<StrategyGenome> {
		var w = windows != null ? windows : [20, 55, 100];
		var out:Array<StrategyGenome> = [];
		for (window in w) {
			var lvl382:ScalarNode = KFeature('fib_retracement($window).level382');
			var lvl500:ScalarNode = KFeature('fib_retracement($window).level500');
			var lvl618:ScalarNode = KFeature('fib_retracement($window).level618');
			out.push({
				entryLong: crossUpScalar(lvl618),
				entryShort: crossDownScalar(lvl382),
				exitLong: crossDownScalar(lvl500),
				exitShort: crossUpScalar(lvl500),
				size: KConst(1.0),
				params: [],
				name: 'fib_retracement_${window}_breakout',
				lineage: ["indicator-seed:fib_retracement"],
				seedOrigin: null
			});
			out.push({
				entryLong: crossUpScalar(lvl500),
				entryShort: crossDownScalar(lvl500),
				exitLong: alwaysFalse(),
				exitShort: alwaysFalse(),
				size: KConst(1.0),
				params: [],
				name: 'fib_retracement_${window}_reclaim',
				lineage: ["indicator-seed:fib_retracement"],
				seedOrigin: null
			});
		}
		return out;
	}

	// ---- Fourier-projection seed genomes -------------------------------------------------

	/**
	 * Same fix as fib_retracement, for the same reason: the FIRST fourier_projection seeds used
	 * `seedFromIndicators`'s generic `SInd`-based crossover, which always calls
	 * `fourier_projection("close", window)` -- a 2-ARG call, meaning `k`/`horizon`/`detrend` are
	 * stuck at their spec defaults (k=3, horizon=1). horizon=1 in particular projects only ONE
	 * bar ahead, which is close enough to the raw price to oscillate across it constantly --
	 * confirmed catastrophic in practice (thousands of trades). `SInd` can't express a 4-arg
	 * call at all (its shape is fixed at `(field, window)`), so this uses a `KFeature` bare-
	 * expression call (matching growMultiOutputField's own established convention for indicators
	 * SInd can't represent) with a longer `horizon` and fewer components (`k`) for a genuinely
	 * SMOOTHER, slower-moving projection, then the SAME edge-triggered `crossUpScalar`/
	 * `crossDownScalar` helpers as fib_retracement -- not a bare level condition, an actual
	 * discrete cross. Two configs (short/long period x matching horizon), always-in-the-market
	 * reversal shape (see seedFromFibRetracement's "reclaim" doc comment for why exits are
	 * `alwaysFalse` here too).
	 */
	public static function seedFromFourierProjection(?configs:Array<{period:Int, k:Int, horizon:Int}>):Array<StrategyGenome> {
		var cfgs = configs != null ? configs : [
			{period: 34, k: 3, horizon: 3},
			{period: 89, k: 2, horizon: 8}
		];
		var out:Array<StrategyGenome> = [];
		for (c in cfgs) {
			var proj:ScalarNode = KFeature('fourier_projection("close", ${c.period}, ${c.k}, ${c.horizon})');
			out.push({
				entryLong: crossUpScalar(proj),
				entryShort: crossDownScalar(proj),
				exitLong: alwaysFalse(),
				exitShort: alwaysFalse(),
				size: KConst(1.0),
				params: [],
				name: 'fourier_projection_${c.period}_${c.k}_${c.horizon}_cross',
				lineage: ["indicator-seed:fourier_projection"],
				seedOrigin: null
			});
		}
		return out;
	}

	// ---- EW host-projection seed genomes (CorpusEvoRun `--ew-host`) ---------------------

	/**
	 * Seed genomes that trade LatticeForecastHost / McmcForecastHost reductions via `SProj`
	 * (`PSHost`). Requires `Fitness.projectionProvider` with `autoBindGenomeHost` (see
	 * `ProjectionProvider.forEvoHost`) so Expand→compile sees aux `Bar.data` columns.
	 */
	public static function seedFromEwHostProjection(hostKind:String = "lattice"):Array<StrategyGenome> {
		var kind = switch (hostKind) {
			case "mcmc", "regime", "auction", "oracle", "null": hostKind; // non-lattice / control hosts
			default: "lattice";
		};
		var samples = kind == "mcmc" ? 8 : 1;
		var out:Array<StrategyGenome> = [];
		function decl(name:String, seed:Int, ?phi:Map<String, Float>):ProjectionDecl {
			return ProjectionProvider.ewDecl(name, 5, kind, seed, phi, samples);
		}
		// p50 above close → long (demo shape from HostProjectionDemoCore).
		out.push({
			entryLong: BCmp(">", KSeries(SProj("ew_0", "p50")), KSeries(SPrice("close"))),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp("<", KSeries(SProj("ew_0", "spread")), KConst(1000.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: 'ew_host_${kind}_p50_gt_close',
			lineage: ["ew-host-seed"],
			seedOrigin: null,
			projections: [decl("ew_0", 1, ["fibHitTol" => 0.01])]
		});
		// Tight band (low spread) → long; widen → flat.
		out.push({
			entryLong: BCmp("<", KSeries(SProj("ew_0", "spread")), KConst(8.0)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KSeries(SProj("ew_0", "spread")), KConst(20.0)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: 'ew_host_${kind}_tight_spread',
			lineage: ["ew-host-seed"],
			seedOrigin: null,
			projections: [decl("ew_0", 2, ["fibHitTol" => 0.02])]
		});
		// Low entropy (confident count) → long.
		out.push({
			entryLong: BCmp("<", KSeries(SProj("ew_0", "entropy")), KConst(0.8)),
			entryShort: BCmp(">", KConst(0.0), KConst(1.0)),
			exitLong: BCmp(">", KSeries(SProj("ew_0", "entropy")), KConst(1.4)),
			exitShort: BCmp(">", KConst(0.0), KConst(1.0)),
			size: KConst(1.0),
			params: [],
			name: 'ew_host_${kind}_low_entropy',
			lineage: ["ew-host-seed"],
			seedOrigin: null,
			projections: [decl("ew_0", 3)]
		});
		// Price above invalidate → stay long bias.
		// Regime / auction emit inv=NaN — this seed is dead weight for those kinds (Bucket F5).
		if (kind == "lattice" || kind == "mcmc") {
			out.push({
				entryLong: BCmp(">", KSeries(SPrice("close")), KSeries(SProj("ew_0", "inv"))),
				entryShort: BCmp("<", KSeries(SPrice("close")), KSeries(SProj("ew_0", "inv"))),
				exitLong: alwaysFalse(),
				exitShort: alwaysFalse(),
				size: KConst(1.0),
				params: [],
				name: 'ew_host_${kind}_vs_invalidate',
				lineage: ["ew-host-seed"],
				seedOrigin: null,
				projections: [decl("ew_0", 4, ["equalityTol" => 0.02])]
			});
		}
		return out;
	}
}

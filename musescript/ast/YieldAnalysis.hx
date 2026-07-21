package musescript.ast;

/**
 * Shared `containsYield` walk — used by MuseParser (FnKind classification),
 * GeneratorLower (lowering eligibility + shape guards), and MuseChecker
 * (yield-usage warnings). Previously copy-pasted three times; all three
 * copies independently had the same bug (descending into nested EFunction
 * bodies, misclassifying a factory that returns a generator lambda as a
 * generator itself) — kept here once so a future fix can't drift out of sync.
 */
class YieldAnalysis {
	public static function containsYield(e:Expr):Bool {
		if (e == null) return false;
		return switch (e) {
			case EYield(_) | EYieldStar(_): true;
			// `yield` binds to the nearest enclosing function — a nested
			// function owns its own yields, so don't descend into it.
			case EFunction(_, _, _, _): false;
			case EBlock(es): for (x in es) if (containsYield(x)) return true; false;
			case EIf(_, a, b): containsYield(a) || (b != null && containsYield(b));
			case EWhile(_, a) | EFor(_, _, a) | EReturn(a) | EVar(_, a)
				| EParent(a) | EMeta(_, _, a):
				a != null && containsYield(a);
			case EBinop(_, a, b): containsYield(a) || containsYield(b);
			case EUnop(_, _, a) | EArray(a, _) | EField(a, _) | ELookback(a, _): containsYield(a);
			case ECall(a, args):
				if (containsYield(a)) return true;
				for (x in args) if (containsYield(x)) return true;
				false;
			case EArrayDecl(vs): for (v in vs) if (containsYield(v)) return true; false;
			case EObject(fs): for (f in fs) if (containsYield(f.e)) return true; false;
			case ETernary(c, a, b): containsYield(c) || containsYield(a) || containsYield(b);
			case EMatch(_, arms): for (arm in arms) if (containsYield(arm.body)) return true; false;
			default: false;
		};
	}
}

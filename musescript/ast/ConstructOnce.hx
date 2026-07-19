package musescript.ast;

/**
 * Shared classification for the strategy-body persistence fix: an ordinary
 * top-level `Assign` (`fast = ema(close, 5)`) is intentionally a PER-BAR
 * prelude — it must re-evaluate every bar (see MuseInterp.registerStrategyBody's
 * doc comment) — but `c = new Counter()` is fundamentally different: `ENew`
 * ALLOCATES new state, and re-running it every bar silently discards
 * whatever a stateful class instance accumulated via its methods, defeating
 * the entire point of a streaming-indicator-as-a-class. Both MuseInterp
 * (registerStrategyBody), JsEmitter/JsBackend, and StrategyWasmEmitter need
 * the SAME classification so a construct-once binding is treated
 * consistently (executed/instantiated exactly once) across every tier —
 * this is that one shared rule, not reimplemented three times.
 */
class ConstructOnce {
	public static function isConstructOnceAssign(s:Stmt):Bool {
		return switch (s) {
			case Assign(_, e): isConstructOnceExpr(e);
			default: false;
		};
	}

	static function isConstructOnceExpr(e:Expr):Bool {
		return switch (e) {
			case ENew(_, _): true;
			case EParent(inner): isConstructOnceExpr(inner);
			default: false;
		};
	}
}

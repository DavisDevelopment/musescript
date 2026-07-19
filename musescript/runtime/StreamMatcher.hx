package musescript.runtime;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.MatchArm;
import musescript.ast.FnKind;
import musescript.ast.OrderKind;
import musescript.ast.ParamOpts;

class StreamMatcher {
	var matcher:PatternMatcher;
	public function new(?matcher:PatternMatcher) {
		this.matcher = matcher != null ? matcher : new PatternMatcher();
	}

	public function matchFor(
		iter:MuseIter,
		arms:Array<MatchArm>,
		onMatch:Map<String, Dynamic>->Expr->Void,
		?onGuard:Map<String, Dynamic>->Expr->Bool
	):Void {
		IterDriver.each(iter, function(item) {
			var r = matcher.match(item, arms);
			if (!r.matched) 
				return;
			if (r.guard != null) {
				if (onGuard == null) 
					return;
				if (!onGuard(r.bindings, r.guard)) 
					return;
			}
			
			onMatch(r.bindings, r.body);
		});
	}
}

package musescript.plan;

import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.Stmt;
import musescript.ast.Expr;
import musescript.ast.Const;
import musescript.ast.ParamOpts;

/**
 * Walk MuseAST for @macro blocks / tune/sample/optimize calls → ExecutionPlan.
 * Reads call shapes from the AST; does not depend on MacroBuiltins runtime markers.
 */
class MusePlanner {
	var stepId:Int;
	var bindings:Map<String, String>;

	public function new() {
		stepId = 0;
		bindings = new Map();
	}

	public function plan(prog:MuseProgram):ExecutionPlan {
		stepId = 0;
		bindings = new Map();
		var plan = MuseIR.empty();
		for (d in prog.decls) {
			switch (d) {
				case MacroDecl(name, body):
					plan.steps = plan.steps.concat(planStmts(body, name));
				case StrategyDecl(name, _):
					plan.steps.push(StrategyStep(nextId('strat_$name'), name));
				case ParamDecl(name, _, opts):
					if (opts != null && opts.tune != null) {
						plan.steps.push(OptimizeStep(nextId('tune_$name'), "sharpe", [name], opts.tune));
					}
				default:
			}
		}
		for (s in prog.stmts) {
			plan.steps = plan.steps.concat(planStmts([s], null));
		}
		return plan;
	}

	function planStmts(stmts:Array<Stmt>, ?macroName:String):Array<PlanStep> {
		var out:Array<PlanStep> = [];
		for (s in stmts) {
			switch (s) {
				case ExprStmt(e):
					out = out.concat(planExpr(e));
				case Assign(name, e):
					var steps = planExpr(e);
					out = out.concat(steps);
					if (steps.length > 0)
						bindings.set(name, planStepId(steps[steps.length - 1]));
				case Block(ss):
					out = out.concat(planStmts(ss, macroName));
				case OnBar(ss) | OnTick(ss) | OnEvent(_, ss):
					out = out.concat(planStmts(ss, macroName));
				default:
			}
		}
		return out;
	}

	function planExpr(e:Expr):Array<PlanStep> {
		var out:Array<PlanStep> = [];
		switch (e) {
			case ECall(EIdent("sample"), args):
				var n = args.length > 1 ? intOf(args[1]) : 22;
				var seed = args.length > 2 ? intOf(args[2]) : null;
				out.push(SymbolSetStep(nextId("sample"), n, seed));
			case ECall(EIdent("tune"), args):
				var names = identsOfArgs(args);
				out.push(OptimizeStep(nextId("tune"), "sharpe", names, "grid"));
			case ECall(EIdent("optimize"), args):
				var metric = args.length > 0 ? identOf(args[0]) : "sharpe";
				var over = args.length > 1 ? identsOf(args[1]) : [];
				out.push(OptimizeStep(nextId("optimize"), metric, over, "grid"));
			case ECall(EIdent("pickBest"), args):
				var candRef = args.length > 0 ? identOf(args[0]) : "_";
				var candidates:Array<Dynamic> = candRef != "_"
					? [{ source: candRef, idents: identsOf(args[0]) }]
					: [];
				var scorer = args.length > 1 ? scorerFromExpr(args[1]) : "sharpe";
				out.push(FeatureSearchStep(nextId("pickBest"), candidates, scorer));
				if (args.length > 1)
					out = out.concat(planExpr(args[1]));
			case ECall(EIdent("plan"), args):
				if (args.length > 0)
					out = out.concat(planExpr(args[0]));
			case ECall(EField(EIdent("llm"), "suggestEncodings"), args):
				var feats = args.length > 0 ? identOf(args[0]) : "_";
				var n = args.length > 1 ? intOf(args[1]) : 5;
				out.push(FeatureSearchStep(nextId("llm_enc"), [{ features: feats, n: n }], "sharpe"));
			case ECall(EIdent("ensemble") | EIdent("DecisionTreeEnsemble"), args):
				var features = args.length > 0 ? featureRef(args[0]) : null;
				var trees = args.length > 1 ? intOf(args[1]) : 100;
				out.push(TrainStep(nextId("ensemble"), "DecisionTreeEnsemble", features, trees));
			case ECall(EIdent("distill"), args):
				var fromId = args.length > 0 ? resolveRef(identOf(args[0])) : "model";
				var into = args.length > 1 ? identOf(args[1]) : "perTickPosition";
				var params = args.length > 2 ? identsOf(args[2]) : [];
				out.push(DistillStep(nextId("distill"), fromId, into, params));
			case EBlock(es):
				for (x in es)
					out = out.concat(planExpr(x));
			case ECall(callee, args):
				out = out.concat(planExpr(callee));
				for (a in args)
					out = out.concat(planExpr(a));
			case EFunction(_, body, _, _):
				out = out.concat(planExpr(body));
			case EReturn(e):
				if (e != null)
					out = out.concat(planExpr(e));
			case ETernary(_, _, _):
			default:
		}
		return out;
	}

	function planStepId(s:PlanStep):String {
		return switch (s) {
			case SymbolSetStep(id, _, _): id;
			case FeatureSearchStep(id, _, _): id;
			case OptimizeStep(id, _, _, _): id;
			case TrainStep(id, _, _, _): id;
			case DistillStep(id, _, _, _): id;
			case StrategyStep(id, _): id;
		};
	}

	function resolveRef(name:String):String {
		if (name == "_")
			return name;
		return bindings.exists(name) ? bindings.get(name) : name;
	}

	function identsOfArgs(args:Array<Expr>):Array<String> {
		var out:Array<String> = [];
		for (a in args) {
			var ids = identsOf(a);
			for (id in ids)
				if (id != "_")
					out.push(id);
		}
		return out;
	}

	function identsOf(e:Expr):Array<String> {
		return switch (e) {
			case EArrayDecl(vals):
				var out:Array<String> = [];
				for (v in vals) {
					var id = identOf(v);
					if (id != "_")
						out.push(id);
				}
				out;
			case EIdent(id): [id];
			case EConst(CString(s)): [s];
			default:
				var id = identOf(e);
				id == "_" ? [] : [id];
		};
	}

	function featureRef(e:Expr):Dynamic {
		var id = identOf(e);
		return id == "_" ? null : id;
	}

	function scorerFromExpr(e:Expr):String {
		return switch (e) {
			case EFunction(_, body, _, _): findMetricInExpr(body);
			default: "sharpe";
		};
	}

	function findMetricInExpr(e:Expr):String {
		switch (e) {
			case ECall(EIdent("optimize"), args):
				return args.length > 0 ? identOf(args[0]) : "sharpe";
			case EBlock(es):
				for (x in es) {
					var m = findMetricInExpr(x);
					if (m != "sharpe")
						return m;
				}
			case ECall(_, args):
				for (a in args) {
					var m = findMetricInExpr(a);
					if (m != "sharpe")
						return m;
				}
			case EFunction(_, body, _, _):
				return findMetricInExpr(body);
			default:
		}
		return "sharpe";
	}

	function hasUnderscore(parts:Array<String>):Bool {
		for (p in parts)
			if (p == "_")
				return true;
		return false;
	}

	function nextId(prefix:String):String {
		return '${prefix}_${stepId++}';
	}

	function identOf(e:Expr):String {
		return switch (e) {
			case EIdent(id): id;
			case EConst(CString(s)): s;
			case EField(inner, f):
				var base = identOf(inner);
				base == "_" ? f : '$base.$f';
			case EArrayDecl(vals):
				var parts = [for (v in vals) identOf(v)];
				parts.length > 0 && !hasUnderscore(parts) ? parts.join(",") : "_";
			case EParent(inner): identOf(inner);
			default: "_";
		};
	}

	function intOf(e:Expr):Int {
		return switch (e) {
			case EConst(CInt(i)): i;
			case EConst(CFloat(f)): Std.int(f);
			case EParent(inner): intOf(inner);
			default: 0;
		};
	}
}

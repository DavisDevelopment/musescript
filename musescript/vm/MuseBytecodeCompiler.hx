package musescript.vm;

import musescript.ast.Expr;
import musescript.ast.Stmt;
import musescript.ast.Const;
import musescript.ast.OrderKind;

/**
 * Thrown when a program (or subtree) falls outside the P0 VM subset. The subset
 * boundary is DETERMINISTIC (SPEC_BYTECODE_VM.md §8): a program either compiles
 * whole or throws, so the oracle/fitness caller can cleanly fall back to the
 * tree-walking `MuseInterp` for the tail without any half-compiled ambiguity.
 */
class VmUnsupported {
	public var reason:String;
	public function new(reason:String) this.reason = reason;
	public function toString():String return "VmUnsupported: " + reason;
}

/**
 * AST → stack-bytecode compiler for the P0 subset: strategy `onBar` bodies made
 * of consts, bar fields, arithmetic/compare/logic (`MuseVmOps` semantics),
 * unary `!`/`-`, local assignment (`Assign`/`var`/`=`), `if`/ternary, `when`,
 * and `long`/`short`/`flat` orders — NO indicators, lookback, calls, match,
 * generators, objects, classes, loops (those throw `VmUnsupported` → interp
 * fallback).
 *
 * Lowers the SAME post-`CallsiteIds` AST the interp executes (§8): P0's parity
 * guarantee is tightest when both tiers consume one AST; the `ConstFold`/CSE
 * optimizer passes are upstream and shared, so lowering here composes with them.
 */
class MuseBytecodeCompiler {
	var code:Array<Int> = [];
	var consts:Array<Dynamic> = [];
	var localSlots:Map<String, Int> = new Map();
	var localNames:Array<String> = [];

	static final BAR_FIELDS:Map<String, Int> = [
		"open" => Op.FIELD_OPEN, "high" => Op.FIELD_HIGH, "low" => Op.FIELD_LOW,
		"close" => Op.FIELD_CLOSE, "volume" => Op.FIELD_VOLUME, "time" => Op.FIELD_TIME,
		"bar_index" => Op.FIELD_BAR_INDEX
	];

	function new() {}

	/**
	 * Compile the concatenation of a strategy's `onBar` handler bodies into one
	 * chunk. Throws `VmUnsupported` if any statement is outside the subset.
	 */
	public static function compileOnBar(bodies:Array<Array<Stmt>>):MuseChunk {
		var c = new MuseBytecodeCompiler();
		for (body in bodies) c.prescanLocals(body);
		for (body in bodies) for (s in body) c.stmt(s);
		c.emit(Op.HALT);
		return new MuseChunk(c.code, c.consts, c.localNames);
	}

	// ---- local-slot pre-scan (assignment discovery order = slot order) ----

	function slotFor(name:String):Int {
		if (BAR_FIELDS.exists(name))
			throw new VmUnsupported('local shadows bar field "$name"');
		if (localSlots.exists(name)) return localSlots.get(name);
		var slot = localNames.length;
		localSlots.set(name, slot);
		localNames.push(name);
		return slot;
	}

	function prescanLocals(stmts:Array<Stmt>):Void {
		for (s in stmts) switch (s) {
			case Assign(name, e): slotFor(name); prescanLocalsExpr(e);
			case ExprStmt(e): prescanLocalsExpr(e);
			case When(cond, body): prescanLocalsExpr(cond); prescanLocals(body);
			case Block(inner): prescanLocals(inner);
			case Order(_, args): for (a in args) prescanLocalsExpr(a);
			default: // leave for stmt() to reject with a precise reason
		}
	}

	function prescanLocalsExpr(e:Expr):Void {
		if (e == null) return;
		switch (e) {
			case EVar(name, init): slotFor(name); if (init != null) prescanLocalsExpr(init);
			case EBinop("=", EIdent(name), b): slotFor(name); prescanLocalsExpr(b);
			case EBinop(_, a, b): prescanLocalsExpr(a); prescanLocalsExpr(b);
			case EUnop(_, _, x): prescanLocalsExpr(x);
			case EParent(x): prescanLocalsExpr(x);
			case EIf(c, t, el): prescanLocalsExpr(c); prescanLocalsExpr(t); if (el != null) prescanLocalsExpr(el);
			case ETernary(c, t, el): prescanLocalsExpr(c); prescanLocalsExpr(t); prescanLocalsExpr(el);
			case EBlock(es): for (x in es) prescanLocalsExpr(x);
			default:
		}
	}

	// ---- emit helpers ----

	inline function emit(op:Int):Void code.push(op);

	function constIndex(v:Dynamic):Int {
		var i = consts.length;
		consts.push(v);
		return i;
	}

	// ---- statements ----

	function stmt(s:Stmt):Void {
		switch (s) {
			case ExprStmt(e):
				expr(e);
				emit(Op.POP);
			case Assign(name, e):
				expr(e);
				emit(Op.STORE_LOCAL_S);
				emit(slotFor(name));
			case Order(kind, args):
				if (args.length > 1) throw new VmUnsupported("multi-arg order");
				var hasArg = args.length > 0;
				if (hasArg) expr(args[0]);
				emit(Op.ORDER);
				emit(switch (kind) {
					case Long: Op.VERB_LONG;
					case Short: Op.VERB_SHORT;
					case Flat | Close: Op.VERB_FLAT;
				});
				emit(hasArg ? 1 : 0);
			case When(cond, body):
				expr(cond);
				emit(Op.JZ);
				var patch = code.length; emit(0);
				for (st in body) stmt(st);
				code[patch] = code.length;
			case Block(inner):
				for (st in inner) stmt(st);
			default:
				throw new VmUnsupported("statement " + stmtName(s));
		}
	}

	// ---- expressions ----

	function expr(e:Expr):Void {
		if (e == null) { emit(Op.CONST); emit(constIndex(null)); return; }
		switch (e) {
			case EConst(c):
				emit(Op.CONST);
				emit(constIndex(constValue(c)));
			case EBarField(name):
				emit(Op.BAR_FIELD);
				emit(barFieldCode(name));
			case EIdent(name):
				if (BAR_FIELDS.exists(name)) { emit(Op.BAR_FIELD); emit(BAR_FIELDS.get(name)); }
				else if (localSlots.exists(name)) { emit(Op.LOAD_LOCAL); emit(localSlots.get(name)); }
				else throw new VmUnsupported('identifier "$name" (not a bar field or local)');
			case EVar(name, init):
				if (init != null) expr(init) else { emit(Op.CONST); emit(constIndex(null)); }
				var slot = slotFor(name);
				emit(Op.STORE_LOCAL); emit(slot);
				emit(Op.LOAD_LOCAL); emit(slot); // EVar is an expression: leaves its value
			case EParent(x):
				expr(x);
			case EBinop("=", EIdent(name), b):
				expr(b);
				var slot = slotFor(name);
				emit(Op.STORE_LOCAL_S); emit(slot);
				emit(Op.LOAD_LOCAL); emit(slot);
			case EBinop("&&", a, b):
				expr(a); expr(b); emit(Op.AND);
			case EBinop("||", a, b):
				expr(a); expr(b); emit(Op.OR);
			case EBinop(op, a, b):
				expr(a); expr(b); emit(binopCode(op));
			case EUnop("!", _, x):
				expr(x); emit(Op.NOT);
			case EUnop("-", _, x):
				expr(x); emit(Op.NEG);
			case EUnop(op, _, _):
				throw new VmUnsupported('unary "$op"');
			case EIf(cond, eif, eelse):
				expr(cond);
				emit(Op.JZ); var toElse = code.length; emit(0);
				expr(eif);
				emit(Op.JMP); var toEnd = code.length; emit(0);
				code[toElse] = code.length;
				if (eelse != null) expr(eelse) else { emit(Op.CONST); emit(constIndex(null)); }
				code[toEnd] = code.length;
			case ETernary(cond, eif, eelse):
				expr(cond);
				emit(Op.JZ); var toElse = code.length; emit(0);
				expr(eif);
				emit(Op.JMP); var toEnd = code.length; emit(0);
				code[toElse] = code.length;
				expr(eelse);
				code[toEnd] = code.length;
			case EBlock(es):
				if (es.length == 0) { emit(Op.CONST); emit(constIndex(null)); return; }
				for (i in 0...es.length) {
					expr(es[i]);
					if (i < es.length - 1) emit(Op.POP);
				}
			default:
				throw new VmUnsupported("expression " + exprName(e));
		}
	}

	// ---- small mappers ----

	static function constValue(c:Const):Dynamic {
		return switch (c) {
			case CInt(i): i;
			case CFloat(f): f;
			case CString(s): s;
			case CBool(b): b;
			case CNull: null;
		}
	}

	static function barFieldCode(name:String):Int {
		if (!BAR_FIELDS.exists(name)) throw new VmUnsupported('bar field "$name"');
		return BAR_FIELDS.get(name);
	}

	static function binopCode(op:String):Int {
		return switch (op) {
			case "+": Op.ADD; case "-": Op.SUB; case "*": Op.MUL; case "/": Op.DIV; case "%": Op.MOD;
			case "<": Op.LT; case "<=": Op.LE; case ">": Op.GT; case ">=": Op.GE;
			case "==": Op.EQ; case "!=": Op.NE;
			default: throw new VmUnsupported('binop "$op"');
		}
	}

	static function stmtName(s:Stmt):String {
		return switch (s) {
			case OnBar(_): "OnBar"; case OnPosition(_): "OnPosition"; case OnTick(_): "OnTick";
			case OnEvent(_, _): "OnEvent"; case ForIn(_, _, _): "ForIn"; case MatchFor(_, _, _): "MatchFor";
			case Return(_): "Return"; case Yield(_): "Yield"; case YieldStar(_): "YieldStar";
			case Use(_, _): "Use"; default: "?";
		}
	}

	static function exprName(e:Expr):String {
		return switch (e) {
			case ECall(_, _): "ECall"; case ELookback(_, _): "ELookback"; case EMeta(n, _, _): 'EMeta($n)';
			case EMatch(_, _): "EMatch"; case EField(_, _): "EField"; case EArray(_, _): "EArray";
			case ENew(_, _): "ENew"; case EWhile(_, _): "EWhile"; case EFor(_, _, _): "EFor";
			case EFunction(_, _, _, _): "EFunction"; case EObject(_): "EObject"; case EArrayDecl(_): "EArrayDecl";
			case EYield(_): "EYield"; case EYieldStar(_): "EYieldStar"; case EReturn(_): "EReturn";
			case EThis: "EThis"; case ESuper(_, _): "ESuper"; default: "?";
		}
	}
}

package musescript.compile;

import musescript.ast.Expr;
import musescript.ast.Stmt;
import musescript.ast.Const;
import musescript.ast.MuseProgram;
import musescript.ast.Decl;
import musescript.ast.OrderKind;
import musescript.ast.ConstructOnce;
import musescript.builtins.MlBuiltins;
import musescript.builtins.StatsBuiltins;

/**
 * Emit on-bar strategies as WAT with exported linear memory.
 *
 * Dual ABI (same module):
 *   reset(capacity) / push_bar(o,h,l,c,v,t,i) — streaming / live
 *   configure_tape(bases..., len) / on_bar(index) — preloaded tape
 *
 * Host ABI retained for side effects only:
 *   get_param(i32)->f64, long/short(f64), flat(), plot/plotshape/hline/bgcolor
 *
 * Indicators, OHLCV lookbacks, and cross/rising/falling state are internalized.
 */
class StrategyWasmEmitter {
	var locals:Map<String, String> = new Map();
	var localOrder:Array<String> = [];
	var imports:Map<String, String> = new Map();
	var strings:Array<String> = [];
	var featureKeys:Array<String> = [];
	var nextTmp:Int = 0;
	var nextCrossSlot:Int = 0;
	var nextRiseSlot:Int = 0;
	var scratchCursor:Int = 0;
	var vectorLocals:Map<String, {baseLocal:String, lenLocal:String, maxLen:Null<Int>}> = new Map();
	var usedIndicators:Map<String, Bool> = new Map();
	/**
	 * Hybrid compilation (F1): statements the native emitter can't lower are
	 * escape regions run by the host's `host_eval` import instead of aborting
	 * the whole module (StrategyWasmBackend.compile's old all-or-nothing
	 * fallback). Index in this array == the region id passed to `host_eval`.
	 */
	var escapeRegions:Array<Stmt> = [];
	/**
	 * F2: names that cross the native/escape boundary (read/written by BOTH a
	 * native-classified and an escape-classified statement, anywhere across
	 * prelude/onBar/onPosition) get a shared linear-memory slot instead of
	 * forcing the producing/consuming statement to escalate — see
	 * `computeFramedNames` and `StrategyWasmRuntimeWat`'s FRAME region.
	 */
	var framedNames:Map<String, Int> = new Map();
	var nextFrameSlot:Int = 0;
	/**
	 * BUG FIX (found while scoping P4): a bare enum variant identifier
	 * (`Bullish`) has no case of its own in `emitValue`'s `EIdent`, so it fell
	 * through to the "unknown identifier -> get_param lookup" fallback —
	 * silently compiling to a HOST PARAM READ (garbage, since no such param
	 * exists) instead of throwing EmitUnsupported and correctly escaping to
	 * the interp (P1's enums predate F1; nothing before this ever routed a
	 * bare-tag construction through emitValue at all, so the gap was never
	 * exercised until a class-WASM/P4 diagnostic surfaced it: hybrid gave 0
	 * trades against interp's real signal on the SAME tape). No enum-tag
	 * native lowering exists yet — that would need a representation the
	 * interp/JS tiers also understand, not just a WASM-side int constant —
	 * so the fix here is purely to make the emitter recognize and REFUSE
	 * (escape) known variant names instead of silently mis-emitting them.
	 */
	var enumVariantNames:Map<String, Bool> = new Map();

	/**
	 * P4 (class-WASM struct lowering — the real version, scoped after the
	 * cross-bar-persistence fix made clear that lowering `ENew` inside
	 * on-bar alone wouldn't help the case that matters). ONLY construct-once
	 * instances (ast/ConstructOnce.hx) are eligible — their memory layout is
	 * knowable entirely at COMPILE TIME (no runtime allocator needed): each
	 * gets a FIXED byte offset, exactly like `framedNames`. A class is only
	 * a candidate when it has no parent (no inheritance in this MVP) and
	 * every field default / ctor body / method body is independently
	 * natively emittable in "method mode" (self-relative field access) —
	 * checked via a dry run (`canLowerClassBody`) that never keeps its
	 * emission, mirroring the F1/F2 classification discipline. Any class
	 * that fails stays exactly as safe as before this feature existed:
	 * fully interp-only via the existing escape-region path.
	 */
	var loweredClasses:Map<String, {fieldOffsets:Map<String, Int>, fieldOrder:Array<String>,
		fieldDefs:Array<Null<Expr>>, ctor:Null<{args:Array<String>, body:Expr}>,
		methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>}> = new Map();
	/** Construct-once VARIABLE name -> {className, fixed compile-time instance pointer}. */
	var loweredInstances:Map<String, {className:String, offset:Int}> = new Map();
	/**
	 * Non-null while emitting a METHOD or CTOR body: the field-offset table
	 * for the class being compiled + the `self` param's local name. Null
	 * while emitting on-bar/on-position (normal mode) — `EIdent`/`Assign`/
	 * `EVar`/`EBinop("=",...)` all branch on this to route bare identifiers
	 * to self-relative field load/store instead of locals/framedNames
	 * (methods have their OWN fully separate local scope — no access to
	 * on-bar locals, framed names, or series at all in this MVP).
	 */
	var methodCtx:Null<{fieldOffsets:Map<String, Int>, selfWat:String}> = null;
	/** Standalone `(func $Class_method ...)` WAT bodies collected while lowering. */
	var methodFuncs:Array<String> = [];
	/** Run-once field-init + ctor WAT, one block per lowered instance, joined into `$construct_once_init`. */
	var initBlocks:Array<String> = [];

	public function new() {}

	public function emitOnBar(prog:MuseProgram):Null<{wat:String, strings:Array<String>, escapeRegions:Array<Stmt>, framedNames:Map<String, Int>}> {
		var hooks = collectStrategyHooks(prog);
		if (hooks.onBar.length == 0 && hooks.onPosition.length == 0) return null;
		try {
			locals = new Map();
			localOrder = [];
			imports = new Map();
			strings = [];
			featureKeys = [];
			nextTmp = 0;
			nextCrossSlot = 0;
			nextRiseSlot = 0;
			scratchCursor = StrategyWasmRuntimeWat.VEC_SCRATCH_BASE;
			vectorLocals = new Map();
			usedIndicators = new Map();
			escapeRegions = [];
			framedNames = new Map();
			nextFrameSlot = 0;
			enumVariantNames = new Map();
			for (d in prog.decls) switch (d) {
				case EnumDecl(_, variants):
					for (v in variants) enumVariantNames.set(v.name, true);
				default:
			}
			// Softmax/sigmoid helpers call host exp; always provide the import.
			needImport("exp", "(param f64) (result f64)");
			if (hooks.onPosition.length > 0) needPositionImports();

			// P4: BEFORE framing analysis — computeFramedNames excludes
			// lowered-instance names from framing eligibility, so it needs
			// loweredInstances already populated.
			computeLoweredClasses(prog);

			computeFramedNames(hooks.prelude.concat(hooks.onBar).concat(hooks.onPosition));

			var bodyParts:Array<String> = [];
			if (hooks.prelude.length > 0)
				bodyParts.push(emitStmtListWithEscapes(hooks.prelude));
			if (hooks.onBar.length > 0)
				bodyParts.push(emitStmtListWithEscapes(hooks.onBar));
			if (hooks.onPosition.length > 0) {
				var posBody = emitStmtListWithEscapes(hooks.onPosition, "      ");
				bodyParts.push('call $$get_position\n    f64.const 0\n    f64.ne\n    if\n      '
					+ posBody + '\n    end');
			}
			var body = bodyParts.join("\n    ");
			var localDecls = [for (n in localOrder)
				"(local $" + n + " " + locals.get(n) + ")"
			].join("\n    ");

			var importLines = [for (nm in imports.keys())
				'(import "env" "' + nm + '" (func $' + nm + ' ' + imports.get(nm) + '))'
			];

			var helpers = StrategyWasmRuntimeWat.helpers(nextCrossSlot, nextRiseSlot);

			// P4: run-once field-init + ctor for every natively-lowered
			// construct-once instance, called by the host EXACTLY ONCE before
			// the bar loop starts (StrategyWasmBackend, mirroring how the
			// interp/JS tiers already construct these once via
			// registerStrategyBody / installUserFns's StrategyDecl bridging —
			// see ast/ConstructOnce.hx). Class methods compile as their own
			// standalone functions (methodFuncs), called directly (no
			// host_eval) from method-call sites inside on-bar.
			var initFunc = initBlocks.length > 0
				? '
  (func $$construct_once_init
    ' + initBlocks.join("\n    ") + '
  )
  (export "construct_once_init" (func $$construct_once_init))
'
				: "";
			var methodFuncsWat = methodFuncs.length > 0 ? methodFuncs.join("\n\n") + "\n" : "";

			var strategyFunc = '
  (func $$run_strategy
    ' + localDecls + '
    ' + body + '
  )

  (func $$push_bar
      (param $$o f64) (param $$h f64) (param $$l f64) (param $$c f64)
      (param $$v f64) (param $$t f64) (param $$i f64)
    (local $$idx i32)
    (local.set $$idx (global.get $$bar_count))
    (if (i32.ge_s (local.get $$idx) (global.get $$capacity))
      (then
        (call $$layout_streaming
          (i32.add (i32.mul (global.get $$capacity) (i32.const 2)) (i32.const 1)))))
    (call $$store_bar (local.get $$idx)
      (local.get $$o) (local.get $$h) (local.get $$l) (local.get $$c)
      (local.get $$v) (local.get $$t) (local.get $$i))
    (call $$set_curs
      (local.get $$o) (local.get $$h) (local.get $$l) (local.get $$c)
      (local.get $$v) (local.get $$t) (local.get $$i))
    (global.set $$bar_count (i32.add (local.get $$idx) (i32.const 1)))
    (call $$run_strategy)
  )
  (export "push_bar" (func $$push_bar))

  (func $$on_bar (param $$idx i32)
    (local $$o f64) (local $$h f64) (local $$l f64) (local $$c f64)
    (local $$v f64) (local $$t f64) (local $$iv f64)
    (if (i32.or (i32.lt_s (local.get $$idx) (i32.const 0))
          (i32.ge_s (local.get $$idx) (global.get $$capacity)))
      (then (return)))
    (local.set $$o (f64.load (i32.add (global.get $$open_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$h (f64.load (i32.add (global.get $$high_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$l (f64.load (i32.add (global.get $$low_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$c (f64.load (i32.add (global.get $$close_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$v (f64.load (i32.add (global.get $$volume_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$t (f64.load (i32.add (global.get $$time_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (local.set $$iv (f64.load (i32.add (global.get $$index_base) (i32.shl (local.get $$idx) (i32.const 3)))))
    (call $$set_curs (local.get $$o) (local.get $$h) (local.get $$l) (local.get $$c)
      (local.get $$v) (local.get $$t) (local.get $$iv))
    (global.set $$bar_count (i32.add (local.get $$idx) (i32.const 1)))
    (call $$run_strategy)
  )
  (export "on_bar" (func $$on_bar))
';


			var wat = "(module\n"
				+ importLines.join("\n") + (importLines.length > 0 ? "\n" : "")
				+ "  (memory (export \"memory\") 1)\n"
				+ helpers
				+ methodFuncsWat
				+ initFunc
				+ strategyFunc
				+ ")\n";
			return { wat: wat, strings: strings.copy(), escapeRegions: escapeRegions.copy(), framedNames: framedNames.copy() };
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	function collectStrategyHooks(prog:MuseProgram):{prelude:Array<Stmt>, onBar:Array<Stmt>, onPosition:Array<Stmt>} {
		var prelude:Array<Stmt> = [];
		var onBarBody:Array<Stmt> = [];
		var onPositionBody:Array<Stmt> = [];
		function walk(ss:Array<Stmt>) {
			for (s in ss) switch (s) {
				case OnBar(body): onBarBody = onBarBody.concat(body);
				case OnPosition(body): onPositionBody = onPositionBody.concat(body);
				case Block(body): walk(body);
				default:
			}
		}
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body):
				for (s in body) switch (s) {
					// Construct-once bindings never enter the per-bar
					// $run_strategy body at all (native or escape) — the
					// escape interp (StrategyWasmBackend.makeEnv's
					// ensureEscapeInterp) instantiates them exactly once
					// via registerDeclPublic, same as the plain-interp path.
					case Assign(_, _) if (ConstructOnce.isConstructOnceAssign(s)):
					case Assign(_, _):
						prelude.push(s);
					case OnBar(onBody):
						onBarBody = onBarBody.concat(onBody);
					case OnPosition(onBody):
						onPositionBody = onPositionBody.concat(onBody);
					case Block(block):
						for (nested in block) switch (nested) {
							case Assign(_, _) if (ConstructOnce.isConstructOnceAssign(nested)):
							case Assign(_, _): prelude.push(nested);
							case OnBar(onBody): onBarBody = onBarBody.concat(onBody);
							case OnPosition(onBody): onPositionBody = onPositionBody.concat(onBody);
							default:
						}
					default:
				}
			default:
		}
		walk(prog.stmts);
		return { prelude: prelude, onBar: onBarBody, onPosition: onPositionBody };
	}

	function needPositionImports():Void {
		needImport("get_position", "(result f64)");
		needImport("get_entry_price", "(result f64)");
		needImport("get_bars_in_trade", "(result f64)");
		needImport("get_cash", "(result f64)");
		needImport("get_equity", "(result f64)");
		needImport("get_unrealized_pnl", "(result f64)");
	}

	function ensureLocal(name:String, ty:String = "f64"):Void {
		if (!locals.exists(name)) {
			locals.set(name, ty);
			localOrder.push(name);
		}
	}

	function strId(s:String):Int {
		var i = strings.indexOf(s);
		if (i >= 0) return i;
		strings.push(s);
		return strings.length - 1;
	}

	function needImport(name:String, sig:String):Void {
		if (!imports.exists(name)) imports.set(name, sig);
	}

	function seriesSid(name:String):Null<Int> {
		return switch (name) {
			case "open": 0;
			case "high": 1;
			case "low": 2;
			case "close": 3;
			case "volume": 4;
			case "time": 5;
			case "index" | "bar_index": 6;
			default: null;
		};
	}

	/**
	 * F2 pre-pass: classify the COMBINED prelude+onBar+onPosition statement
	 * list — combined (not per-section, unlike the real emission below)
	 * because a boundary crossing can span sections (e.g. a name written in
	 * the prelude and read by an escaped onBar statement), and `locals`/
	 * `vectorLocals` already accumulate across all 3 sections in the real
	 * emission (emitOnBar resets them once, not between sections), so this
	 * pre-pass's combined view matches what the real passes will actually see.
	 *
	 * Finds every name touched by BOTH a native-classified and an escape-
	 * classified statement and assigns each a FRAME_SLOTS-bounded memory slot
	 * (`StrategyWasmRuntimeWat`'s FRAME region) — see `emitStmtListWithEscapes`
	 * for how that lets the boundary crossing skip escalation entirely once a
	 * name is framed. Fully self-contained: snapshots emitter state, classifies
	 * via the SAME sequential-accumulate discipline `emitStmtListWithEscapes`
	 * uses (a later statement can depend on an earlier one's REAL registration
	 * — see that function's doc comment), then restores, so none of this dry
	 * run's side effects leak into the 3 real per-section calls that follow.
	 */
	function computeFramedNames(allStmts:Array<Stmt>):Void {
		var n = allStmts.length;
		var reads = [for (s in allStmts) readNames(s)];
		var writes = [for (s in allStmts) writeNames(s)];

		var localsStart = locals.copy();
		var localOrderStart = localOrder.copy();
		var vectorLocalsStart = vectorLocals.copy();
		var nextTmpStart = nextTmp;
		var nextCrossSlotStart = nextCrossSlot;
		var nextRiseSlotStart = nextRiseSlot;
		var scratchCursorStart = scratchCursor;

		var isEscape = [for (s in allStmts) tryEmitStmt(s) == null];

		locals = localsStart;
		localOrder = localOrderStart;
		vectorLocals = vectorLocalsStart;
		nextTmp = nextTmpStart;
		nextCrossSlot = nextCrossSlotStart;
		nextRiseSlot = nextRiseSlotStart;
		scratchCursor = scratchCursorStart;

		var nativeTouched = new Map<String, Bool>();
		var escapeTouched = new Map<String, Bool>();
		for (i in 0...n) {
			var target = isEscape[i] ? escapeTouched : nativeTouched;
			for (nm in reads[i]) target.set(nm, true);
			for (nm in writes[i]) target.set(nm, true);
		}
		for (nm in nativeTouched.keys()) {
			// Lowered-instance names (P4) never correspond to a framedNames f64
			// slot at all — they're only ever referenced via the specific
			// `instance.method(...)` call-site pattern, which bypasses generic
			// EIdent evaluation entirely (see emitCall). Excluding them here
			// just avoids wasting a slot nothing would read/write; nothing
			// depends on the exclusion for correctness, but it's free and clean.
			if (escapeTouched.exists(nm) && !framedNames.exists(nm) && !loweredInstances.exists(nm)) {
				if (nextFrameSlot < StrategyWasmRuntimeWat.FRAME_SLOTS) {
					framedNames.set(nm, StrategyWasmRuntimeWat.FRAME_BASE + nextFrameSlot * 8);
					nextFrameSlot++;
				}
				// else: slot budget exhausted — this name falls back to F1's
				// escalation fixpoint in emitStmtListWithEscapes (still safe,
				// just not framed).
			}
		}
	}

	/**
	 * P4: find every construct-once instance (ast/ConstructOnce.hx) in the
	 * strategy body and try to lower it — no runtime allocator needed, each
	 * gets a FIXED compile-time offset into StrategyWasmRuntimeWat's HEAP
	 * region (the set of construct-once instances is fully known statically).
	 * A class is only eligible when: no parent (no inheritance in this MVP),
	 * every method + the ctor independently compiles in "method mode" (self-
	 * relative field access via `methodCtx`), and — for THIS SPECIFIC
	 * instance — every ctor-call argument is a constant literal (ctor args
	 * come from the `new X(...)` call site, which for a construct-once
	 * binding runs before any bar is bound, so there's no meaningful runtime
	 * value to evaluate them against; non-constant args just aren't
	 * supported here, not unsafe — the instance stays interp-only). Any
	 * class/instance that fails ANY of this is untouched — exactly as
	 * correct and safe as before this feature existed.
	 */
	function computeLoweredClasses(prog:MuseProgram):Void {
		loweredClasses = new Map();
		loweredInstances = new Map();
		methodFuncs = [];
		initBlocks = [];

		var classDecls = new Map<String, {parent:Null<String>, fields:Array<{name:String, def:Null<Expr>}>,
			methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>,
			ctor:Null<{args:Array<String>, body:Expr}>}>();
		for (d in prog.decls) switch (d) {
			case ClassDecl(name, parent, fields, methods, ctor):
				classDecls.set(name, {parent: parent, fields: fields, methods: methods, ctor: ctor});
			default:
		}

		for (className => cls in classDecls) {
			if (cls.parent != null) continue;
			if (cls.fields.length == 0) continue;
			var methodOk = true;
			for (m in cls.methods) if (m.isStatic) methodOk = false;
			if (!methodOk) continue;

			var fieldOrder = [for (f in cls.fields) f.name];
			var fieldOffsets = new Map<String, Int>();
			for (i in 0...fieldOrder.length) fieldOffsets.set(fieldOrder[i], i * 8);

			var compiled:Array<String> = [];
			var ok = true;
			if (cls.ctor != null) {
				var w = tryCompileMethod(className, "new", cls.ctor.args, cls.ctor.body, fieldOffsets);
				if (w == null) ok = false; else compiled.push(w);
			}
			if (ok) for (m in cls.methods) {
				var w = tryCompileMethod(className, m.name, m.args, m.body, fieldOffsets);
				if (w == null) { ok = false; break; }
				compiled.push(w);
			}
			if (!ok) continue;

			for (w in compiled) methodFuncs.push(w);
			loweredClasses.set(className, {
				fieldOffsets: fieldOffsets, fieldOrder: fieldOrder,
				fieldDefs: [for (f in cls.fields) f.def], ctor: cls.ctor, methods: cls.methods
			});
		}

		// Find construct-once instances of NOW-LOWERABLE classes and assign
		// each its fixed heap offset + generate its run-once init block.
		heapBytesUsed = 0;
		for (d in prog.decls) switch (d) {
			case StrategyDecl(_, body):
				lowerConstructOnceInstances(body, loweredClasses);
			default:
		}
	}

	/** Running allocator for the P4 fixed-offset instance heap — advances only
	 * during `computeLoweredClasses`, never during per-bar execution. */
	var heapBytesUsed:Int = 0;

	function lowerConstructOnceInstances(body:Array<Stmt>,
			classes:Map<String, {fieldOffsets:Map<String, Int>, fieldOrder:Array<String>, fieldDefs:Array<Null<Expr>>,
				ctor:Null<{args:Array<String>, body:Expr}>, methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>}>):Void {
		for (s in body) switch (s) {
			case Assign(varName, e) if (ConstructOnce.isConstructOnceAssign(s)):
				var call = switch (e) {
					case ENew(cn, args): {cn: cn, args: args};
					case EParent(ENew(cn, args)): {cn: cn, args: args};
					default: null;
				};
				if (call == null) continue;
				var cls = classes.get(call.cn);
				if (cls == null) continue; // class itself wasn't lowerable
				var argVals:Array<Float> = [];
				var argsOk = true;
				for (a in call.args) {
					var v = constFloat(a);
					if (v == null) { argsOk = false; break; }
					argVals.push(v);
				}
				if (!argsOk) continue;
				var instBytes = cls.fieldOrder.length * 8;
				if (heapBytesUsed + instBytes > StrategyWasmRuntimeWat.HEAP_BYTES) continue;
				var offset = StrategyWasmRuntimeWat.HEAP_BASE + heapBytesUsed;
				var initWat = tryCompileInstanceInit(call.cn, cls, offset, call.args, argVals);
				if (initWat == null) continue;
				heapBytesUsed += instBytes;
				initBlocks.push(initWat);
				loweredInstances.set(varName, {className: call.cn, offset: offset});
			case Block(inner):
				lowerConstructOnceInstances(inner, classes);
			default:
		}
	}

	function findLoweredMethod(cls:{fieldOffsets:Map<String, Int>, fieldOrder:Array<String>, fieldDefs:Array<Null<Expr>>,
			ctor:Null<{args:Array<String>, body:Expr}>, methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>},
			name:String):Null<{name:String, args:Array<String>, body:Expr, isStatic:Bool}> {
		for (m in cls.methods) if (m.name == name) return m;
		return null;
	}

	/** A constant-literal expr's Float value, or null if it isn't one (P4 ctor-arg restriction). */
	function constFloat(e:Expr):Null<Float> {
		return switch (e) {
			case EConst(CInt(i)): i;
			case EConst(CFloat(f)): f;
			case EUnop("-", true, inner):
				var v = constFloat(inner);
				v != null ? -v : null;
			case EParent(inner): constFloat(inner);
			default: null;
		};
	}

	/**
	 * Dry-compiles one method/ctor body as a standalone `(func $Class_method
	 * (param $self i32) (param $arg f64)... (result f64) ...)`, using a FRESH
	 * isolated local scope (methods never share on-bar's `locals`) and
	 * `methodCtx` so bare identifiers matching a field route to self-relative
	 * `f64.load`/`f64.store` instead of locals/framedNames/series (methods
	 * have NO access to on-bar state in this MVP — only their own args/locals
	 * and the class's own fields). Returns null (rather than throwing) on any
	 * unsupported construct, snapshotting/restoring ALL emitter-wide counters
	 * around the attempt (same discipline as `tryEmitStmt`) so a rejected
	 * method never leaks partial state into the rest of compilation.
	 */
	function tryCompileMethod(className:String, methodName:String, args:Array<String>, body:Expr, fieldOffsets:Map<String, Int>):Null<String> {
		var savedLocals = locals, savedOrder = localOrder, savedVec = vectorLocals;
		var savedTmp = nextTmp, savedCross = nextCrossSlot, savedRise = nextRiseSlot, savedScratch = scratchCursor;
		var savedImports = imports.copy(), savedStrings = strings.copy();
		var savedCtx = methodCtx;

		locals = new Map();
		localOrder = [];
		vectorLocals = new Map();
		nextTmp = 0;
		for (a in args) locals.set(a, "f64"); // known as a param — NOT added to localOrder (params are declared separately, not `(local)`s)
		methodCtx = {fieldOffsets: fieldOffsets, selfWat: "local.get $self"};

		var result:Null<String> = null;
		try {
			var bodyWat = emitValue(body); // body is always EBlock (parser always wraps method/ctor bodies)
			var declaredLocals = [for (n in localOrder) "(local $" + n + " " + locals.get(n) + ")"].join("\n    ");
			var paramDecls = [for (a in args) "(param $" + a + " f64)"].join(" ");
			result = "(func $" + className + "_" + methodName + " (param $self i32)"
				+ (paramDecls.length > 0 ? " " + paramDecls : "") + " (result f64)\n    "
				+ (declaredLocals.length > 0 ? declaredLocals + "\n    " : "")
				+ bodyWat + "\n  )";
		} catch (_:EmitUnsupported) {
			result = null;
		}

		locals = savedLocals;
		localOrder = savedOrder;
		vectorLocals = savedVec;
		nextTmp = savedTmp;
		nextCrossSlot = savedCross;
		nextRiseSlot = savedRise;
		scratchCursor = savedScratch;
		imports = savedImports;
		strings = savedStrings;
		methodCtx = savedCtx;
		return result;
	}

	/**
	 * Dry-compiles the run-once field-init + ctor sequence for ONE instance
	 * at a FIXED heap `offset` — field defaults write in declared order
	 * (mirrors MuseInterp.initFieldsChain, minus the parent walk since P4
	 * excludes inheritance), then the ctor body runs with `self` baked in as
	 * a literal `i32.const offset` (not a param — there is exactly one
	 * instance at this offset, known at compile time) and its args bound as
	 * plain locals initialized from the already-validated constant `argVals`.
	 */
	function tryCompileInstanceInit(className:String,
			cls:{fieldOffsets:Map<String, Int>, fieldOrder:Array<String>, fieldDefs:Array<Null<Expr>>,
				ctor:Null<{args:Array<String>, body:Expr}>, methods:Array<{name:String, args:Array<String>, body:Expr, isStatic:Bool}>},
			offset:Int, ctorArgExprs:Array<Expr>, ctorArgVals:Array<Float>):Null<String> {
		var savedLocals = locals, savedOrder = localOrder, savedVec = vectorLocals;
		var savedTmp = nextTmp, savedCross = nextCrossSlot, savedRise = nextRiseSlot, savedScratch = scratchCursor;
		var savedImports = imports.copy(), savedStrings = strings.copy();
		var savedCtx = methodCtx;

		locals = new Map();
		localOrder = [];
		vectorLocals = new Map();
		nextTmp = 0;
		var selfWat = "i32.const " + offset;
		methodCtx = {fieldOffsets: cls.fieldOffsets, selfWat: selfWat};

		var result:Null<String> = null;
		try {
			var parts:Array<String> = [];
			for (i in 0...cls.fieldOrder.length) {
				var fname = cls.fieldOrder[i];
				var off = cls.fieldOffsets.get(fname);
				var def = cls.fieldDefs[i];
				var valueWat = def != null ? coerceF64(def) : "f64.const 0";
				parts.push(selfWat + "\n    i32.const " + off + "\n    i32.add\n    " + valueWat + "\n    f64.store");
			}
			if (cls.ctor != null) {
				for (i in 0...cls.ctor.args.length) {
					var an = cls.ctor.args[i];
					ensureLocal(an);
					parts.push("f64.const " + ctorArgVals[i] + "\n    local.set $" + an);
				}
				parts.push(emitValue(cls.ctor.body) + "\n    drop");
			}
			var declaredLocals = [for (n in localOrder) "(local $" + n + " " + locals.get(n) + ")"].join("\n    ");
			result = (declaredLocals.length > 0 ? declaredLocals + "\n    " : "") + parts.join("\n    ");
		} catch (_:EmitUnsupported) {
			result = null;
		}

		locals = savedLocals;
		localOrder = savedOrder;
		vectorLocals = savedVec;
		nextTmp = savedTmp;
		nextCrossSlot = savedCross;
		nextRiseSlot = savedRise;
		scratchCursor = savedScratch;
		imports = savedImports;
		strings = savedStrings;
		methodCtx = savedCtx;
		return result;
	}

	/**
	 * F1 hybrid compilation: emit a statement LIST with per-statement escape
	 * regions instead of the old all-or-nothing `EmitUnsupported` abort.
	 *
	 * `emitStmt`'s `ensureLocal`-declared locals are plain WASM `(local)`s
	 * (reset to 0 every call to `$run_strategy` — one call == one bar, no
	 * cross-bar persistence), so all data-flow hazards live WITHIN one
	 * statement list. There are TWO directions, both requiring escalation to
	 * a full fixpoint (a single top-to-bottom pass only catches the first):
	 *
	 *  1. A statement READS a name only an escape region WRITES — native
	 *     code has no way to see that value UNLESS the name is FRAMED (F2),
	 *     so an un-framed one must escape too.
	 *  2. A statement WRITES a name an escape region READS — the escape's
	 *     interp thunk can only see values that reached it via the SAME
	 *     shared harness/interp (i.e., were themselves set by a PRIOR escape
	 *     in this bar) OR the F2 shared frame; a value that only ever existed
	 *     as a native WASM local (and isn't framed) is invisible to it. So an
	 *     un-framed writer must escape too, so the value becomes visible
	 *     through the shared interp's globals instead.
	 *
	 * Escaping is always the safe direction to move (never the reverse) —
	 * same "over-X is always safe" principle PreludeVars.hx documents for
	 * its own hoist-eligibility analysis, just pointed the other way.
	 */
	function emitStmtListWithEscapes(stmts:Array<Stmt>, indent:String = "    "):String {
		var n = stmts.length;
		var reads = [for (s in stmts) readNames(s)];
		var writes = [for (s in stmts) writeNames(s)];

		// Snapshot emitter state before classification so the real pass below
		// can replay from the same starting point.
		var localsStart = locals.copy();
		var localOrderStart = localOrder.copy();
		var vectorLocalsStart = vectorLocals.copy();
		var nextTmpStart = nextTmp;
		var nextCrossSlotStart = nextCrossSlot;
		var nextRiseSlotStart = nextRiseSlot;
		var scratchCursorStart = scratchCursor;

		// Seed classification SEQUENTIALLY, carrying real emitter state
		// forward between statements — NOT dry-running each statement in
		// isolation and rolling back afterward. A later statement (e.g.
		// `zs = stat_zscore(xs)`) can depend on registrations (`xs` becoming
		// a vectorLocal) that only a PRIOR native statement's real emission
		// makes; classifying each statement against a reset/rolled-back
		// state falsely marks dependent native chains as escapes.
		// `tryEmitStmt` rolls back only on ITS OWN failure, so state from
		// preceding successful statements stays intact for the next call.
		var isEscape = [for (s in stmts) tryEmitStmt(s) == null];

		var changed = true;
		while (changed) {
			changed = false;
			var escapedWrites = new Map<String, Bool>();
			var escapedReads = new Map<String, Bool>();
			for (i in 0...n) if (isEscape[i]) {
				for (nm in writes[i]) escapedWrites.set(nm, true);
				for (nm in reads[i]) escapedReads.set(nm, true);
			}
			for (i in 0...n) {
				if (isEscape[i]) continue;
				var mustEscape = false;
				// F2: a FRAMED name's boundary is already bridged via shared
				// linear memory (both sides read/write the same slot), so it
				// no longer forces escalation — only an un-framed crossing
				// (e.g. the FRAME_SLOTS budget was exhausted) still does.
				for (nm in reads[i]) if (escapedWrites.exists(nm) && !framedNames.exists(nm)) mustEscape = true;
				for (nm in writes[i]) if (escapedReads.exists(nm) && !framedNames.exists(nm)) mustEscape = true;
				if (mustEscape) { isEscape[i] = true; changed = true; }
			}
		}

		// Replay for real from the pre-classification snapshot. Any statement
		// ending up escaped never needs its classification-time emission
		// kept (the fixpoint guarantees every remaining-native statement's
		// reads only depend on names written by OTHER remaining-native
		// statements before it), so resetting here and re-emitting only the
		// still-native statements in order reproduces exactly the state a
		// from-scratch native-only pass would have.
		locals = localsStart;
		localOrder = localOrderStart;
		vectorLocals = vectorLocalsStart;
		nextTmp = nextTmpStart;
		nextCrossSlot = nextCrossSlotStart;
		nextRiseSlot = nextRiseSlotStart;
		scratchCursor = scratchCursorStart;

		var parts:Array<String> = [];
		for (i in 0...n) {
			if (isEscape[i]) {
				var regionId = escapeRegions.length;
				escapeRegions.push(stmts[i]);
				needImport("host_eval", "(param i32)");
				parts.push("i32.const " + regionId + "\n" + indent + "call $host_eval");
			} else {
				// Guaranteed to succeed: the sequential classification pass
				// already proved it against equivalent preceding state, and
				// no already-native statement is ever escalated BACK to escape.
				var wat = tryEmitStmt(stmts[i]);
				parts.push(wat != null ? wat : "");
			}
		}
		return parts.join("\n" + indent);
	}

	/** Attempt `emitStmt`, rolling back any partially-registered local/vector/counter state on failure. */
	function tryEmitStmt(s:Stmt):Null<String> {
		var localsSnap = locals.copy();
		var localOrderSnap = localOrder.copy();
		var vectorLocalsSnap = vectorLocals.copy();
		var nextTmpSnap = nextTmp;
		var nextCrossSlotSnap = nextCrossSlot;
		var nextRiseSlotSnap = nextRiseSlot;
		var scratchCursorSnap = scratchCursor;
		try {
			return emitStmt(s);
		} catch (_:EmitUnsupported) {
			locals = localsSnap;
			localOrder = localOrderSnap;
			vectorLocals = vectorLocalsSnap;
			nextTmp = nextTmpSnap;
			nextCrossSlot = nextCrossSlotSnap;
			nextRiseSlot = nextRiseSlotSnap;
			scratchCursor = scratchCursorSnap;
			return null;
		}
	}

	/** Names this statement READS (not the target of its own Assign, if any). Over-inclusive is safe. */
	function readNames(s:Stmt):Array<String> {
		var out:Array<String> = [];
		function e(x:Null<Expr>):Void if (x != null) collectIdents(x, out);
		switch (s) {
			case ExprStmt(x): e(x);
			case Assign(_, x): e(x);
			case Order(_, args): for (a in args) e(a);
			case Return(x): e(x);
			case When(cond, body):
				e(cond);
				for (b in body) for (n in readNames(b)) out.push(n);
			case Block(ss):
				for (b in ss) for (n in readNames(b)) out.push(n);
			case OnBar(_) | OnPosition(_) | OnTick(_) | OnEvent(_, _) | MatchFor(_, _, _)
				| ForIn(_, _, _) | Yield(_) | YieldStar(_) | Use(_, _):
				// Already unconditionally unsupported (emitStmt throws) — no
				// need to resolve their reads for taint purposes.
		}
		return out;
	}

	/** Names this statement (or one nested inside it) ASSIGNS. */
	function writeNames(s:Stmt):Array<String> {
		var out:Array<String> = [];
		switch (s) {
			case Assign(n, _): out.push(n);
			case When(_, body): for (b in body) for (n in writeNames(b)) out.push(n);
			case Block(ss): for (b in ss) for (n in writeNames(b)) out.push(n);
			default:
		}
		return out;
	}

	/** Best-effort free-identifier collector over an Expr subtree (read positions only). */
	function collectIdents(x:Expr, out:Array<String>):Void {
		switch (x) {
			case EIdent(n): out.push(n);
			case EBarField(_) | EConst(_):
			case EVar(_, init): if (init != null) collectIdents(init, out);
			case EBlock(es): for (e in es) collectIdents(e, out);
			case EField(o, _): collectIdents(o, out);
			case EBinop(_, a, b): collectIdents(a, out); collectIdents(b, out);
			case EUnop(_, _, e): collectIdents(e, out);
			case ECall(callee, args): collectIdents(callee, out); for (a in args) collectIdents(a, out);
			case EIf(c, a, b): collectIdents(c, out); collectIdents(a, out); if (b != null) collectIdents(b, out);
			case EWhile(c, b): collectIdents(c, out); collectIdents(b, out);
			case EFor(_, it, b): collectIdents(it, out); collectIdents(b, out);
			case EFunction(_, body, _, _): collectIdents(body, out);
			case EReturn(e): if (e != null) collectIdents(e, out);
			case EArray(o, i): collectIdents(o, out); collectIdents(i, out);
			case EArrayDecl(vs): for (v in vs) collectIdents(v, out);
			case EObject(fs): for (f in fs) collectIdents(f.e, out);
			case ETernary(c, a, b): collectIdents(c, out); collectIdents(a, out); collectIdents(b, out);
			case EParent(e): collectIdents(e, out);
			case EMeta(_, args, e): for (a in args) collectIdents(a, out); collectIdents(e, out);
			case ELookback(s, n): collectIdents(s, out); collectIdents(n, out);
			case EMatch(scrut, arms):
				collectIdents(scrut, out);
				for (arm in arms) {
					if (arm.guard != null) collectIdents(arm.guard, out);
					collectIdents(arm.body, out);
				}
			case EYield(e) | EYieldStar(e): collectIdents(e, out);
			case ENew(_, args): for (a in args) collectIdents(a, out);
			case EThis:
			case ESuper(_, args): for (a in args) collectIdents(a, out);
		}
	}

	function emitStmt(s:Stmt):String {
		return switch (s) {
			case ExprStmt(e):
				emitValue(e) + "\n    drop";
			// P4 (checked FIRST — methods have their own isolated scope and
			// must never fall through to on-bar's framedNames/vector logic,
			// even if a method-local name happens to collide with an on-bar
			// framed name string): a bare `field = ...` inside a method body
			// (optional-this write, no `!locals.exists` shadow) is a
			// self-relative field store; anything else in method mode is an
			// ordinary method-local var.
			case Assign(name, e) if (methodCtx != null && !locals.exists(name) && methodCtx.fieldOffsets.exists(name)):
				methodCtx.selfWat + "\n    i32.const " + methodCtx.fieldOffsets.get(name)
					+ "\n    i32.add\n    " + coerceF64(e) + "\n    f64.store";
			case Assign(name, e) if (methodCtx != null):
				ensureLocal(name);
				coerceF64(e) + "\n    local.set $" + name;
			case Assign(name, e) if (framedNames.exists(name)):
				// F2: a boundary-crossing name stores to its shared frame slot
				// instead of a WASM local — the escape side's interp thunk
				// reads/writes the SAME memory offset (see MuseInterp's frame
				// binding), so this crossing never needs the whole statement
				// escalated to interp.
				"i32.const " + framedNames.get(name) + "\n    " + coerceF64(e) + "\n    f64.store";
			case Assign(name, e):
				var vec = tryAssignVector(name, e);
				if (vec != null) return vec;
				forgetVectorLocal(name);
				ensureLocal(name);
				coerceF64(e) + "\n    local.set $" + name;
			case Block(ss):
				[for (x in ss) emitStmt(x)].join("\n    ");
			case Return(e):
				e != null ? emitValue(e) + "\n    drop" : "";
			case Order(kind, args):
				switch (kind) {
					case Long:
						needImport("long", "(param f64)");
						(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $long";
					case Short:
						needImport("short", "(param f64)");
						(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $short";
					case Flat | Close:
						needImport("flat", "");
						"call $flat";
				}
			case OnBar(_) | OnPosition(_) | OnTick(_) | OnEvent(_, _) | MatchFor(_, _, _) | ForIn(_, _, _) | Yield(_) | YieldStar(_) | Use(_, _):
				throw new EmitUnsupported();
			case When(cond, body):
				asI32Cond(cond) + "\n    if\n      " + [for (x in body) emitStmt(x)].join("\n      ") + "\n    end";
		};
	}

	function emitValue(e:Expr):String {
		return switch (e) {
			case EConst(c):
				switch (c) {
					case CInt(i): "f64.const " + i;
					case CFloat(f): "f64.const " + f;
					case CBool(b): b ? "i32.const 1" : "i32.const 0";
					case CNull: "f64.const 0";
					case CString(_): throw new EmitUnsupported();
				}
			case EIdent(n):
				// P4 (checked FIRST, same reasoning as the Assign case above):
				// a method's own local/param wins over its class's fields
				// (shadowing); a bare identifier matching a field name is a
				// self-relative read. Methods have NO other name source in
				// this MVP — no framedNames, no series, no get_param.
				if (methodCtx != null) {
					if (locals.exists(n)) return "local.get $" + n;
					if (methodCtx.fieldOffsets.exists(n))
						return methodCtx.selfWat + "\n    i32.const " + methodCtx.fieldOffsets.get(n) + "\n    i32.add\n    f64.load";
					throw new EmitUnsupported();
				}
				if (framedNames.exists(n)) return "i32.const " + framedNames.get(n) + "\n    f64.load";
				if (vectorLocals.exists(n)) throw new EmitUnsupported();
				// A nullary enum variant construction — not a local/series/param
				// read. No native representation exists (see field doc comment);
				// throwing here is what lets F1/F2 correctly escape/frame it
				// instead of silently misreading it as a get_param lookup.
				//
				// P4 exploration note: a bare `f64.const <tagId>` encoding was
				// tried and DELIBERATELY REVERTED — it's only safe for a value
				// that stays native end-to-end. The moment such a name gets
				// FRAMED (F2, e.g. because a LATER statement needs it for an
				// unrelated escape) or aliased into another variable that
				// itself escapes, the interp thunk reads a bare float where it
				// expects the canonical `{__tag,args}` record — silent
				// corruption, not a crash. Closing that fully needs real
				// taint tracking through arbitrary aliasing (`t = s` where `s`
				// was tag-typed), which native EMatch lowering ALONE doesn't
				// solve either. Left for a future pass that builds proper
				// enum-value taint tracking alongside native match dispatch,
				// not attempted piecemeal.
				if (enumVariantNames.exists(n)) throw new EmitUnsupported();
				if (locals.exists(n)) {
					"local.get $" + n;
				} else {
					var sid = seriesSid(n);
					if (sid != null) {
						"global.get $" + "cur_" + seriesCurName(sid);
					} else {
						needImport("get_param", "(param i32) (result f64)");
						"i32.const " + strId(n) + "\n    call $get_param";
					}
				}
			case EBarField(n):
				var sid = seriesSid(n);
				if (sid == null) throw new EmitUnsupported();
				"global.get $" + "cur_" + seriesCurName(sid);
			case EVar(n, init) if (methodCtx != null && !locals.exists(n) && methodCtx.fieldOffsets.exists(n)):
				var off = methodCtx.fieldOffsets.get(n);
				var valueWat = init != null ? coerceF64(init) : "f64.const 0";
				methodCtx.selfWat + "\n    i32.const " + off + "\n    i32.add\n    " + valueWat
					+ "\n    f64.store\n    " + methodCtx.selfWat + "\n    i32.const " + off + "\n    i32.add\n    f64.load";
			case EVar(n, init) if (methodCtx != null):
				ensureLocal(n);
				var valueWat = init != null ? coerceF64(init) : "f64.const 0";
				valueWat + "\n    local.set $" + n + "\n    local.get $" + n;
			case EVar(n, init) if (framedNames.exists(n)):
				var off = framedNames.get(n);
				var valueWat = init != null ? coerceF64(init) : "f64.const 0";
				"i32.const " + off + "\n    " + valueWat + "\n    f64.store\n    i32.const " + off + "\n    f64.load";
			case EVar(n, init):
				if (init != null) {
					var vec = tryAssignVector(n, init);
					if (vec != null) return vec + "\n    f64.const 0";
				}
				forgetVectorLocal(n);
				ensureLocal(n);
				if (init == null) return "f64.const 0\n    local.set $" + n + "\n    local.get $" + n;
				coerceF64(init) + "\n    local.set $" + n + "\n    local.get $" + n;
			case EBinop("=", EIdent(n), v) if (methodCtx != null && !locals.exists(n) && methodCtx.fieldOffsets.exists(n)):
				var off = methodCtx.fieldOffsets.get(n);
				methodCtx.selfWat + "\n    i32.const " + off + "\n    i32.add\n    " + coerceF64(v)
					+ "\n    f64.store\n    " + methodCtx.selfWat + "\n    i32.const " + off + "\n    i32.add\n    f64.load";
			case EBinop("=", EIdent(n), v) if (methodCtx != null):
				ensureLocal(n);
				coerceF64(v) + "\n    local.set $" + n + "\n    local.get $" + n;
			case EBinop("=", EIdent(n), v) if (framedNames.exists(n)):
				var off = framedNames.get(n);
				"i32.const " + off + "\n    " + coerceF64(v) + "\n    f64.store\n    i32.const " + off + "\n    f64.load";
			case EBinop("=", EIdent(n), v):
				var vec = tryAssignVector(n, v);
				if (vec != null) return vec + "\n    f64.const 0";
				forgetVectorLocal(n);
				ensureLocal(n);
				coerceF64(v) + "\n    local.set $" + n + "\n    local.get $" + n;
			case EBinop(op, a, b):
				emitBinop(op, a, b);
			case EUnop("-", true, x):
				"f64.const 0\n    " + coerceF64(x) + "\n    f64.sub";
			case EUnop("!", true, x):
				asI32Cond(x) + "\n    i32.eqz";
			case EIf(c, a, b):
				asI32Cond(c) + "\n    if (result f64)\n      " + coerceF64(a)
					+ "\n    else\n      " + (b != null ? coerceF64(b) : "f64.const 0") + "\n    end";
			case ETernary(c, a, b):
				emitValue(EIf(c, a, b));
			case EWhile(c, body):
				var br = "br_" + (nextTmp++);
				var ct = "ct_" + (nextTmp++);
				"block $" + br + "\n      loop $" + ct + "\n        " + asI32Cond(c)
					+ "\n        i32.eqz\n        br_if $" + br + "\n        " + emitValue(body)
					+ "\n        drop\n        br $" + ct + "\n      end\n    end\n    f64.const 0";
			case ECall(EField(EIdent(instanceName), methodName), args) if (loweredInstances.exists(instanceName)):
				// P4: a method call on a natively-lowered construct-once
				// instance — `self` is the instance's FIXED compile-time heap
				// offset (a literal, not loaded from anywhere: there's exactly
				// one instance at that address, known at compile time), args
				// evaluated normally, dispatched via a direct `call` to the
				// method's own standalone function (never a `host_eval`).
				var inst = loweredInstances.get(instanceName);
				var cls = loweredClasses.get(inst.className);
				var m = cls != null ? findLoweredMethod(cls, methodName) : null;
				if (cls == null || m == null) throw new EmitUnsupported();
				"i32.const " + inst.offset + "\n    "
					+ [for (a in args) coerceF64(a)].join("\n    ")
					+ (args.length > 0 ? "\n    " : "") + "call $" + inst.className + "_" + methodName;
			case ECall(callee, args):
				emitCall(callee, args);
			case EParent(x): emitValue(x);
			case EBlock(es):
				if (es.length == 0) return "f64.const 0";
				var parts = [for (i in 0...es.length - 1) emitValue(es[i]) + "\n    drop"];
				parts.push(emitValue(es[es.length - 1]));
				parts.join("\n    ");
			case EReturn(v):
				// Only valid in method-mode: methods compile as their own
				// `(func ... (result f64))`, where a real WASM `return`
				// instruction is well-typed and exits immediately — unlike
				// on-bar's `$run_strategy` (no result type), where
				// `emitStmt`'s `Return` case can only drop the value. Code
				// textually after `return` is WASM-valid unreachable (the
				// validator accepts anything after an unconditional exit), so
				// an early `return` followed by more statements in the same
				// EBlock — e.g. inside a `when` guard — is fine.
				if (methodCtx == null) throw new EmitUnsupported();
				(v != null ? emitValue(v) : "f64.const 0") + "\n    return";
			case EMeta(_, _, x): emitValue(x);
			case ELookback(series, n):
				emitLookback(series, n);
			case EArray(EIdent(name), idx) if (vectorLocals.exists(name)):
				emitVectorIndex(name, idx);
			case EArray(_, _):
				throw new EmitUnsupported();
			default:
				throw new EmitUnsupported();
		};
	}

	function seriesCurName(sid:Int):String {
		return switch (sid) {
			case 0: "open";
			case 1: "high";
			case 2: "low";
			case 3: "close";
			case 4: "volume";
			case 5: "time";
			default: "index";
		};
	}

	function emitLookback(series:Expr, n:Expr):String {
		return switch (series) {
			case EParent(inner):
				emitLookback(inner, n);
			case EBarField(name) | EIdent(name):
				var sid = seriesSid(name);
				if (sid == null) throw new EmitUnsupported();
				"i32.const " + sid + "\n    " + asI32(n) + "\n    call $lookback_ohlcv";
			case EConst(CString(s)):
				var sid = seriesSid(s);
				if (sid == null) throw new EmitUnsupported();
				"i32.const " + sid + "\n    " + asI32(n) + "\n    call $lookback_ohlcv";
			default:
				throw new EmitUnsupported();
		};
	}

	function seriesArgSid(e:Expr):Int {
		return switch (e) {
			case EConst(CString(s)):
				var sid = seriesSid(s);
				if (sid == null) throw new EmitUnsupported();
				sid;
			case EBarField(n) | EIdent(n):
				var sid = seriesSid(n);
				if (sid == null) throw new EmitUnsupported();
				sid;
			default: throw new EmitUnsupported();
		};
	}

	function emitCall(callee:Expr, args:Array<Expr>):String {
		var name = switch (callee) {
			case EIdent(n): n;
			case EField(EIdent("Math"), f): f;
			default: throw new EmitUnsupported();
		};
		return switch (name) {
			case "long":
				needImport("long", "(param f64)");
				(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $long\n    f64.const 0";
			case "short":
				needImport("short", "(param f64)");
				(args.length > 0 ? coerceF64(args[0]) : "f64.const nan") + "\n    call $short\n    f64.const 0";
			case "flat" | "close":
				needImport("flat", "");
				"call $flat\n    f64.const 0";
			case "position":
				needPositionImports();
				"call $get_position";
			case "entry_price":
				needPositionImports();
				"call $get_entry_price";
			case "bars_in_trade":
				needPositionImports();
				"call $get_bars_in_trade";
			case "cash":
				needPositionImports();
				"call $get_cash";
			case "equity":
				needPositionImports();
				"call $get_equity";
			case "unrealized_pnl":
				needPositionImports();
				"call $get_unrealized_pnl";
			case "sma" | "ema" | "rsi" | "atr" | "highest" | "lowest" | "change" | "pct_change"
			   | "mom" | "roc" | "stdev" | "wma" | "rma":
				usedIndicators.set(name, true);
				var series = args.length > 0 ? seriesArgSid(args[0]) : 3;
				var len = args.length > 1 ? asI32(args[1]) : "i32.const 14";
				"i32.const " + series + "\n    " + len + "\n    call $" + name;
			case "vwap":
				usedIndicators.set(name, true);
				"call $vwap";
			case "feature" | "model_score":
				if (args.length < 1) throw new EmitUnsupported();
				"i32.const " + featureSlot(stringKey(args[0])) + "\n    call $feature_at";
			case "tree_value":
				if (args.length < 1) throw new EmitUnsupported();
				"i32.const " + featureSlot("tree:" + stringKey(args[0]) + ":value") + "\n    call $feature_at";
			case "tree_bit":
				if (args.length < 2) throw new EmitUnsupported();
				"i32.const " + featureSlot("tree:" + stringKey(args[0]) + ":" + constIntKey(args[1])) + "\n    call $feature_at";
			case "graph_metric":
				if (args.length < 2) throw new EmitUnsupported();
				"i32.const " + featureSlot("graph:" + stringKey(args[0]) + ":" + stringKey(args[1])) + "\n    call $feature_at";
			case "hl2":
				"global.get $" + "cur_high\n    global.get $" + "cur_low\n    f64.add\n    f64.const 2\n    f64.div";
			case "hlc3":
				"global.get $" + "cur_high\n    global.get $" + "cur_low\n    f64.add\n    global.get $" + "cur_close\n    f64.add"
					+ "\n    f64.const 3\n    f64.div";
			case "ohlc4":
				"global.get $" + "cur_open\n    global.get $" + "cur_high\n    f64.add\n    global.get $" + "cur_low\n    f64.add"
					+ "\n    global.get $" + "cur_close\n    f64.add\n    f64.const 4\n    f64.div";
			case "clamp":
				if (args.length < 3) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[2]) + "\n    f64.min\n    "
					+ coerceF64(args[1]) + "\n    f64.max";
			case "abs":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.abs";
			case "sqrt":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.sqrt";
			case "floor":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.floor";
			case "ceil":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.ceil";
			case "round":
				if (args.length < 1) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    f64.nearest";
			case "min":
				if (args.length < 2) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.min";
			case "max":
				if (args.length < 2) throw new EmitUnsupported();
				coerceF64(args[0]) + "\n    " + coerceF64(args[1]) + "\n    f64.max";
			case "nz":
				if (args.length < 1) throw new EmitUnsupported();
				var tx = "_nz_" + (nextTmp++);
				ensureLocal(tx);
				var repl = args.length > 1 ? coerceF64(args[1]) : "f64.const 0";
				coerceF64(args[0]) + "\n    local.set $" + tx
					+ "\n    local.get $" + tx
					+ "\n    " + repl
					+ "\n    local.get $" + tx + "\n    local.get $" + tx
					+ "\n    f64.eq\n    select";
			case "na":
				if (args.length < 1) throw new EmitUnsupported();
				var tx = "_na_" + (nextTmp++);
				ensureLocal(tx);
				coerceF64(args[0]) + "\n    local.set $" + tx
					+ "\n    f64.const 1\n    f64.const 0"
					+ "\n    local.get $" + tx + "\n    local.get $" + tx
					+ "\n    f64.ne\n    select";
			case "crossover" | "crossunder":
				var slot = nextCrossSlot++;
				"i32.const " + slot + "\n    " + coerceF64(args[0]) + "\n    " + coerceF64(args[1])
					+ "\n    call $" + name + "\n    f64.convert_i32_s";
			case "plot":
				needImport("plot", "(param f64 i32)");
				var label = args.length > 1 ? seriesStrId(args[1]) : strId("plot");
				coerceF64(args[0]) + "\n    i32.const " + label + "\n    call $plot\n    f64.const 0";
			case "plotshape":
				needImport("plotshape", "(param i32)");
				var shape = args.length > 0 ? seriesStrId(args[0]) : strId("shape");
				"i32.const " + shape + "\n    call $plotshape\n    f64.const 0";
			case "hline":
				needImport("hline", "(param f64 i32)");
				var hlab = args.length > 1 ? seriesStrId(args[1]) : strId("hline");
				coerceF64(args[0]) + "\n    i32.const " + hlab + "\n    call $hline\n    f64.const 0";
			case "bgcolor":
				needImport("bgcolor", "(param i32)");
				var col = args.length > 0 ? seriesStrId(args[0]) : strId("bg");
				"i32.const " + col + "\n    call $bgcolor\n    f64.const 0";
			case "rising" | "falling":
				var rslot = nextRiseSlot++;
				var xn = args.length > 1 ? asI32(args[1]) : "i32.const 1";
				var call = "i32.const " + rslot + "\n    " + coerceF64(args[0]) + "\n    " + xn
					+ "\n    call $" + name + "\n    f64.convert_i32_s";
				// `rising(x, n, minBars)` gates on bars-in-trade < minBars → false,
				// matching TradeBuiltins.rising/falling exactly (was silently
				// dropped here — a real interp/wasm divergence for any strategy
				// using the 3-arg form, e.g. `rising(close, 1, minHold)`).
				if (args.length > 2) {
					needImport("get_bars_in_trade", "(result f64)");
					"call $get_bars_in_trade\n    i32.trunc_f64_s\n    " + asI32(args[2])
						+ "\n    i32.lt_s\n    if (result f64)\n      f64.const 0\n    else\n      "
						+ call + "\n    end";
				} else call;
			case "ml_dot":
				emitMlPairOrFold(args, "vec_dot", function(xs, ys) return MlBuiltins.dot(xs, ys));
			case "ml_mse":
				emitMlPairOrFold(args, "vec_mse", function(xs, ys) return MlBuiltins.mse(xs, ys));
			case "ml_mae":
				emitMlPairOrFold(args, "vec_mae", function(xs, ys) return MlBuiltins.mae(xs, ys));
			case "ml_linear_predict":
				emitMlLinearPredict(args);
			case "ml_sigmoid":
				if (args.length < 1) throw new EmitUnsupported();
				try {
					"f64.const " + watFloat(MlBuiltins.sigmoid(constNumber(args[0])));
				} catch (_:EmitUnsupported) {
					coerceF64(args[0]) + "\n    call $ml_sigmoid";
				}
			case "stat_mean":
				emitStatWindowOrLiteral(args, "stat_window_mean", "vec_mean", null, function(xs) return StatsBuiltins.mean(xs));
			case "stat_median":
				if (args.length < 1) throw new EmitUnsupported();
				"f64.const " + watFloat(StatsBuiltins.median(constVector(args[0])));
			case "stat_variance":
				emitStatWindowOrLiteral(args, "stat_window_var", "vec_var", 0, function(xs) return StatsBuiltins.variance(xs));
			case "stat_sample_variance":
				emitStatWindowOrLiteral(args, "stat_window_var", "vec_var", 1, function(xs) return StatsBuiltins.sampleVariance(xs));
			case "stat_stddev":
				emitStatWindowOrLiteral(args, "stat_window_stdev", "vec_stdev", 0, function(xs) return StatsBuiltins.standardDeviation(xs));
			case "stat_sample_stddev":
				emitStatWindowOrLiteral(args, "stat_window_stdev", "vec_stdev", 1, function(xs) return StatsBuiltins.sampleStandardDeviation(xs));
			case "stat_quantile":
				if (args.length < 2) throw new EmitUnsupported();
				"f64.const " + watFloat(StatsBuiltins.quantile(constVector(args[0]), constNumber(args[1])));
			case "stat_covariance":
				emitStatWindowPairOrLiteral(args, "stat_window_cov", "vec_cov", function(xs, ys) return StatsBuiltins.covariance(xs, ys));
			case "stat_correlation":
				emitStatWindowPairOrLiteral(args, "stat_window_corr", "vec_corr", function(xs, ys) return StatsBuiltins.pearson(xs, ys));
			case "stat_skewness":
				if (args.length < 1) throw new EmitUnsupported();
				"f64.const " + watFloat(StatsBuiltins.skewness(constVector(args[0])));
			case "stat_zscore" | "sci_cumsum" | "sci_diff" | "sci_normalize" | "ml_softmax":
				// Vector-producing: only via lowerVecOperand / vector assignment.
				throw new EmitUnsupported();
			case "ml_matrix" | "ml_matrix_rows" | "ml_matrix_cols" | "ml_matrix_data" | "ml_matrix_get"
			   | "ml_ridge_fit" | "ml_ridge_fit_matrix":
				throw new EmitUnsupported();
			// Dynamic graph objects/results have no Strategy-WASM ABI yet. Refuse
			// emission explicitly so MuseCompiler selects its documented host fallback.
			case "graph_neighbors" | "graph_degree" | "graph_has_edge" | "graph_bfs"
			   | "graph_reachable" | "graph_shortest_path" | "graph_pagerank":
				throw new EmitUnsupported();
			default:
				throw new EmitUnsupported();
		};
	}

	function seriesStrId(e:Expr):Int {
		return switch (e) {
			case EConst(CString(s)): strId(s);
			case EBarField(n) | EIdent(n): strId(n);
			default: strId("close");
		};
	}

	function featureSlot(key:String):Int {
		var i = featureKeys.indexOf(key);
		if (i >= 0) return i;
		featureKeys.push(key);
		strId("kestrel:" + key); // sidecar metadata only; not the dense feature id
		return featureKeys.length - 1;
	}

	function stringKey(e:Expr):String {
		return switch (e) {
			case EConst(CString(s)): s;
			case EIdent(n) | EBarField(n): n;
			case EParent(inner): stringKey(inner);
			default: throw new EmitUnsupported();
		};
	}

	function constIntKey(e:Expr):Int {
		return switch (e) {
			case EConst(CInt(i)): i;
			case EConst(CFloat(f)): Std.int(f);
			case EParent(inner): constIntKey(inner);
			default: throw new EmitUnsupported();
		};
	}

	function constVector(e:Expr):Array<Float> {
		return switch (e) {
			case EParent(inner):
				constVector(inner);
			case EArrayDecl(values):
				[for (value in values) constNumber(value)];
			default:
				throw new EmitUnsupported();
		};
	}

	function constNumber(e:Expr):Float {
		return switch (e) {
			case EConst(CInt(i)): i;
			case EConst(CFloat(f)): f;
			case EUnop("-", true, inner): -constNumber(inner);
			case EParent(inner): constNumber(inner);
			default: throw new EmitUnsupported();
		};
	}

	static function watFloat(v:Float):String {
		if (Math.isNaN(v)) return "nan";
		if (v == Math.POSITIVE_INFINITY) return "inf";
		if (v == Math.NEGATIVE_INFINITY) return "-inf";
		return Std.string(v);
	}

	/**
	 * Pattern-match `window(series, n)` so scalar stats can run over series tapes
	 * without materializing dynamic vectors.
	 */
	function asWindowArg(e:Expr):Null<{sid:Int, lenExpr:String, lenConst:Null<Int>}> {
		return switch (e) {
			case EParent(inner):
				asWindowArg(inner);
			case ECall(EIdent("window"), wargs) if (wargs.length >= 2):
				var lenConst:Null<Int> = null;
				try lenConst = constIntKey(wargs[1]) catch (_:EmitUnsupported) {}
				{
					sid: seriesArgSid(wargs[0]),
					lenExpr: asI32(wargs[1]),
					lenConst: lenConst
				};
			default:
				null;
		};
	}

	function allocScratch(len:Int):Int {
		if (len <= 0) throw new EmitUnsupported();
		var bytes = len * 8;
		var limit = StrategyWasmRuntimeWat.VEC_SCRATCH_BASE + StrategyWasmRuntimeWat.VEC_SCRATCH_BYTES;
		if (scratchCursor + bytes > limit) throw new EmitUnsupported();
		var base = scratchCursor;
		scratchCursor += bytes;
		return base;
	}

	function tryConstVector(e:Expr):Null<Array<Float>> {
		try {
			return constVector(e);
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	/** Spill an array literal (const or scalar runtime elems) into scratch. */
	function spillArrayDecl(values:Array<Expr>):{prelude:String, baseExpr:String, lenExpr:String, maxLen:Null<Int>} {
		var base = allocScratch(values.length);
		var parts:Array<String> = [];
		for (i in 0...values.length) {
			parts.push("i32.const " + (base + i * 8) + "\n    " + coerceF64(values[i]) + "\n    f64.store");
		}
		return {
			prelude: parts.join("\n    "),
			baseExpr: "i32.const " + base,
			lenExpr: "i32.const " + values.length,
			maxLen: values.length
		};
	}

	function spillConstFloats(values:Array<Float>):{prelude:String, baseExpr:String, lenExpr:String, maxLen:Null<Int>} {
		if (values.length == 0)
			return {prelude: "", baseExpr: "i32.const 0", lenExpr: "i32.const 0", maxLen: 0};
		var base = allocScratch(values.length);
		var parts:Array<String> = [];
		for (i in 0...values.length) {
			parts.push("i32.const " + (base + i * 8) + "\n    f64.const " + watFloat(values[i]) + "\n    f64.store");
		}
		return {
			prelude: parts.join("\n    "),
			baseExpr: "i32.const " + base,
			lenExpr: "i32.const " + values.length,
			maxLen: values.length
		};
	}

	/** Copy a fixed-length window into scratch; length may shrink when history is short. */
	function spillWindow(window:{sid:Int, lenExpr:String, lenConst:Null<Int>}):{prelude:String, baseExpr:String, lenExpr:String, maxLen:Null<Int>} {
		if (window.lenConst == null) throw new EmitUnsupported();
		var base = allocScratch(window.lenConst);
		var lenLocal = "_vlen_" + (nextTmp++);
		ensureLocal(lenLocal, "i32");
		var prelude = "i32.const " + window.sid + "\n    " + window.lenExpr
			+ "\n    i32.const " + base + "\n    call $window_to_scratch\n    local.set $" + lenLocal;
		return {
			prelude: prelude,
			baseExpr: "i32.const " + base,
			lenExpr: "local.get $" + lenLocal,
			maxLen: window.lenConst
		};
	}

	function forgetVectorLocal(name:String):Void {
		vectorLocals.remove(name);
	}

	function bindVectorLocal(name:String, vec:{prelude:String, baseExpr:String, lenExpr:String, maxLen:Null<Int>}):String {
		var baseLocal = name + "__base";
		var lenLocal = name + "__len";
		ensureLocal(baseLocal, "i32");
		ensureLocal(lenLocal, "i32");
		vectorLocals.set(name, {baseLocal: baseLocal, lenLocal: lenLocal, maxLen: vec.maxLen});
		var parts:Array<String> = [];
		if (vec.prelude.length > 0) parts.push(vec.prelude);
		parts.push(vec.baseExpr + "\n    local.set $" + baseLocal);
		parts.push(vec.lenExpr + "\n    local.set $" + lenLocal);
		return parts.join("\n    ");
	}

	function tryAssignVector(name:String, e:Expr):Null<String> {
		try {
			return bindVectorLocal(name, lowerVecOperand(e));
		} catch (_:EmitUnsupported) {
			return null;
		}
	}

	function emitVectorIndex(name:String, idx:Expr):String {
		var info = vectorLocals.get(name);
		var addr = "_vaddr_" + (nextTmp++);
		ensureLocal(addr, "i32");
		return "local.get $" + info.baseLocal
			+ "\n    " + asI32(idx)
			+ "\n    i32.const 3\n    i32.shl\n    i32.add\n    local.set $" + addr
			+ "\n    local.get $" + addr + "\n    f64.load";
	}

	function vecTransformHelper(name:String):Null<String> {
		return switch (name) {
			case "stat_zscore": "vec_zscore";
			case "sci_cumsum": "vec_cumsum";
			case "sci_diff": "vec_diff";
			case "sci_normalize": "vec_normalize";
			case "ml_softmax": "vec_softmax";
			default: null;
		};
	}

	function foldVecTransform(name:String, xs:Array<Float>):Null<Array<Float>> {
		return switch (name) {
			case "stat_zscore": StatsBuiltins.zScores(xs);
			case "sci_cumsum": StatsBuiltins.cumulativeSum(xs);
			case "sci_diff": StatsBuiltins.difference(xs);
			case "sci_normalize": StatsBuiltins.normalize(xs);
			case "ml_softmax": MlBuiltins.softmax(xs);
			default: null;
		};
	}

	function lowerVecTransform(name:String, args:Array<Expr>):{prelude:String, baseExpr:String, lenExpr:String, maxLen:Null<Int>} {
		if (args.length < 1) throw new EmitUnsupported();
		var consts = tryConstVector(args[0]);
		if (consts != null) {
			var folded = foldVecTransform(name, consts);
			if (folded == null) throw new EmitUnsupported();
			return spillConstFloats(folded);
		}
		var helper = vecTransformHelper(name);
		if (helper == null) throw new EmitUnsupported();
		var src = lowerVecOperand(args[0]);
		if (src.maxLen == null) throw new EmitUnsupported();
		var allocLen = name == "sci_diff" ? (src.maxLen < 1 ? 1 : src.maxLen) : src.maxLen;
		if (allocLen <= 0)
			return {prelude: src.prelude, baseExpr: "i32.const 0", lenExpr: "i32.const 0", maxLen: 0};
		var dst = allocScratch(allocLen);
		var lenLocal = "_vlen_" + (nextTmp++);
		ensureLocal(lenLocal, "i32");
		var parts:Array<String> = [];
		if (src.prelude.length > 0) parts.push(src.prelude);
		parts.push(src.baseExpr);
		parts.push(src.lenExpr);
		parts.push("i32.const " + dst);
		parts.push("call $" + helper);
		parts.push("local.set $" + lenLocal);
		var outMax:Null<Int> = name == "sci_diff"
			? (src.maxLen < 1 ? 0 : src.maxLen - 1)
			: src.maxLen;
		return {
			prelude: parts.join("\n    "),
			baseExpr: "i32.const " + dst,
			lenExpr: "local.get $" + lenLocal,
			maxLen: outMax
		};
	}

	function lowerVecOperand(e:Expr):{prelude:String, baseExpr:String, lenExpr:String, maxLen:Null<Int>} {
		return switch (e) {
			case EParent(inner):
				lowerVecOperand(inner);
			case EArrayDecl(values):
				spillArrayDecl(values);
			case EIdent(n) if (vectorLocals.exists(n)):
				var info = vectorLocals.get(n);
				{
					prelude: "",
					baseExpr: "local.get $" + info.baseLocal,
					lenExpr: "local.get $" + info.lenLocal,
					maxLen: info.maxLen
				};
			case ECall(EIdent(name), args)
				if (name == "stat_zscore" || name == "sci_cumsum" || name == "sci_diff"
					|| name == "sci_normalize" || name == "ml_softmax"):
				lowerVecTransform(name, args);
			default:
				var window = asWindowArg(e);
				if (window == null) throw new EmitUnsupported();
				spillWindow(window);
		};
	}

	function emitMlPairOrFold(
		args:Array<Expr>,
		helper:String,
		fold:Array<Float>->Array<Float>->Float
	):String {
		if (args.length < 2) throw new EmitUnsupported();
		var leftConst = tryConstVector(args[0]);
		var rightConst = tryConstVector(args[1]);
		if (leftConst != null && rightConst != null)
			return "f64.const " + watFloat(fold(leftConst, rightConst));
		var left = lowerVecOperand(args[0]);
		var right = lowerVecOperand(args[1]);
		var parts:Array<String> = [];
		if (left.prelude.length > 0) parts.push(left.prelude);
		if (right.prelude.length > 0) parts.push(right.prelude);
		parts.push(left.baseExpr);
		parts.push(left.lenExpr);
		parts.push(right.baseExpr);
		parts.push(right.lenExpr);
		parts.push("call $" + helper);
		return parts.join("\n    ");
	}

	function emitMlLinearPredict(args:Array<Expr>):String {
		if (args.length < 2) throw new EmitUnsupported();
		var leftConst = tryConstVector(args[0]);
		var rightConst = tryConstVector(args[1]);
		var bias = args.length > 2 ? coerceF64(args[2]) : "f64.const 0";
		if (leftConst != null && rightConst != null) {
			var weighted = MlBuiltins.dot(leftConst, rightConst);
			return "f64.const " + watFloat(weighted) + "\n    " + bias + "\n    f64.add";
		}
		var left = lowerVecOperand(args[0]);
		var right = lowerVecOperand(args[1]);
		var parts:Array<String> = [];
		if (left.prelude.length > 0) parts.push(left.prelude);
		if (right.prelude.length > 0) parts.push(right.prelude);
		parts.push(left.baseExpr);
		parts.push(left.lenExpr);
		parts.push(right.baseExpr);
		parts.push(right.lenExpr);
		parts.push("call $vec_dot");
		parts.push(bias);
		parts.push("f64.add");
		return parts.join("\n    ");
	}

	function emitStatWindowOrLiteral(
		args:Array<Expr>,
		windowHelper:String,
		vecHelper:String,
		sampleFlag:Null<Int>,
		fold:Array<Float>->Float
	):String {
		if (args.length < 1) throw new EmitUnsupported();
		var window = asWindowArg(args[0]);
		if (window != null) {
			var out = "i32.const " + window.sid + "\n    " + window.lenExpr + "\n    ";
			if (sampleFlag != null) out += "i32.const " + sampleFlag + "\n    ";
			return out + "call $" + windowHelper;
		}
		var consts = tryConstVector(args[0]);
		if (consts != null) return "f64.const " + watFloat(fold(consts));
		var vec = lowerVecOperand(args[0]);
		var parts:Array<String> = [];
		if (vec.prelude.length > 0) parts.push(vec.prelude);
		parts.push(vec.baseExpr);
		parts.push(vec.lenExpr);
		if (sampleFlag != null) parts.push("i32.const " + sampleFlag);
		parts.push("call $" + vecHelper);
		return parts.join("\n    ");
	}

	function emitStatWindowPairOrLiteral(
		args:Array<Expr>,
		windowHelper:String,
		vecHelper:String,
		fold:Array<Float>->Array<Float>->Float
	):String {
		if (args.length < 2) throw new EmitUnsupported();
		var left = asWindowArg(args[0]);
		var right = asWindowArg(args[1]);
		if (left != null && right != null) {
			if (left.lenConst != null && right.lenConst != null && left.lenConst != right.lenConst)
				throw new EmitUnsupported();
			return "i32.const " + left.sid + "\n    i32.const " + right.sid + "\n    "
				+ left.lenExpr + "\n    call $" + windowHelper;
		}
		var leftConst = tryConstVector(args[0]);
		var rightConst = tryConstVector(args[1]);
		if (leftConst != null && rightConst != null)
			return "f64.const " + watFloat(fold(leftConst, rightConst));
		var leftVec = lowerVecOperand(args[0]);
		var rightVec = lowerVecOperand(args[1]);
		var parts:Array<String> = [];
		if (leftVec.prelude.length > 0) parts.push(leftVec.prelude);
		if (rightVec.prelude.length > 0) parts.push(rightVec.prelude);
		parts.push(leftVec.baseExpr);
		parts.push(leftVec.lenExpr);
		parts.push(rightVec.baseExpr);
		parts.push(rightVec.lenExpr);
		parts.push("call $" + vecHelper);
		return parts.join("\n    ");
	}

	function emitBinop(op:String, a:Expr, b:Expr):String {
		var cmp = ["<", ">", "<=", ">=", "==", "!="].indexOf(op) >= 0;
		if (cmp) {
			var instr = switch (op) {
				case "<": "f64.lt"; case ">": "f64.gt"; case "<=": "f64.le";
				case ">=": "f64.ge"; case "==": "f64.eq"; case "!=": "f64.ne";
				default: throw op;
			};
			return coerceF64(a) + "\n    " + coerceF64(b) + "\n    " + instr;
		}
		if (op == "&&" || op == "||") {
			var bit = op == "&&" ? "i32.and" : "i32.or";
			return asI32Cond(a) + "\n    " + asI32Cond(b) + "\n    " + bit;
		}
		if (op == "%") {
			var ta = "_mod_a_" + nextTmp;
			var tb = "_mod_b_" + (nextTmp++);
			ensureLocal(ta);
			ensureLocal(tb);
			return coerceF64(a) + "\n    local.set $" + ta
				+ "\n    " + coerceF64(b) + "\n    local.set $" + tb
				+ "\n    local.get $" + ta
				+ "\n    local.get $" + ta + "\n    local.get $" + tb
				+ "\n    f64.div\n    f64.trunc\n    local.get $" + tb
				+ "\n    f64.mul\n    f64.sub";
		}
		var instr = switch (op) {
			case "+": "f64.add"; case "-": "f64.sub"; case "*": "f64.mul"; case "/": "f64.div";
			default: throw new EmitUnsupported();
		};
		return coerceF64(a) + "\n    " + coerceF64(b) + "\n    " + instr;
	}

	/**
	 * Emit `e` as a value guaranteed to leave f64 on the stack. WASM's compare
	 * instructions (f64.lt/gt/le/ge/eq/ne) and i32.and/or/eqz ALWAYS produce
	 * i32, never f64 — every other emitValue case already produces f64, so a
	 * bare `emitValue(e)` (the historical body of this function) is only
	 * wrong for boolean-shaped expressions. Concretely: `var ok = a > b;` (an
	 * EVar init, which local.sets straight into an f64 local) or any boolean
	 * subexpression reused as an ordinary scalar. Was a real, silent
	 * WASM-validation failure — asI32Cond's own boolean contexts (if/&&/||)
	 * are unaffected, they want the raw i32 and already bypass this function.
	 */
	function coerceF64(e:Expr):String {
		return switch (e) {
			case EParent(x): coerceF64(x);
			case EBinop(op, _, _) if (["<", ">", "<=", ">=", "==", "!=", "&&", "||"].indexOf(op) >= 0):
				emitValue(e) + "\n    f64.convert_i32_s";
			case EUnop("!", true, _):
				emitValue(e) + "\n    f64.convert_i32_s";
			default:
				emitValue(e);
		};
	}

	function asI32(e:Expr):String {
		return coerceF64(e) + "\n    i32.trunc_f64_s";
	}

	function asI32Cond(e:Expr):String {
		return switch (e) {
			case EParent(x): asI32Cond(x);
			case EMeta(_, _, x): asI32Cond(x);
			case EBinop(op, _, _) if (["<", ">", "<=", ">=", "==", "!=", "&&", "||"].indexOf(op) >= 0):
				emitValue(e);
			case EUnop("!", _, _):
				emitValue(e);
			case ECall(EIdent("crossover"), _) | ECall(EIdent("crossunder"), _)
				| ECall(EIdent("rising"), _) | ECall(EIdent("falling"), _):
				emitValue(e) + "\n    i32.trunc_f64_s";
			default:
				coerceF64(e) + "\n    f64.const 0\n    f64.ne";
		};
	}
}

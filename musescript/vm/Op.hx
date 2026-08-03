package musescript.vm;

/**
 * Stack-VM opcodes (SPEC_BYTECODE_VM.md §2), grounded in `MuseInterp.evalExpr`/
 * `execStmt`. P0 subset only — enough for the strategy `onBar`/`when`/`order`
 * hot path with NO indicators/lookback/generators (those are P3 / interp
 * fallback). Encoded as plain `Int`s in `MuseChunk.code`; opcodes that carry an
 * operand read the next Int(s) inline (documented per op).
 *
 * NOTE on `AND`/`OR`: these are NOT short-circuit jumps. `MuseInterp.binop`
 * deliberately evaluates BOTH operands of `&&`/`||` every bar so stateful
 * builtins (crossover/rising/…) tick regardless of the other operand's value
 * (see the short-circuit-parity-fix). The compiler therefore emits both operand
 * subtrees, then a single `AND`/`OR` that combines the two already-computed
 * booleans — matching the interp and the WASM `i32.and`/`i32.or` lowering.
 */
enum abstract Op(Int) from Int to Int {
	var CONST;        // + Int constIndex   -> push consts[k]
	var LOAD_LOCAL;   // + Int slot         -> push locals[slot]
	var STORE_LOCAL;  // + Int slot         -> locals[slot] = pop (EVar; no series push)
	var STORE_LOCAL_S;// + Int slot         -> locals[slot] = pop, pushSeries(name) if numeric (Assign stmt)
	var BAR_FIELD;    // + Int fieldCode    -> push current bar field (see FIELD_* below)
	var ADD; var SUB; var MUL; var DIV; var MOD;   // pop b, pop a -> push a·b (MuseVmOps numeric; ADD is + with string concat)
	var LT; var LE; var GT; var GE;                // pop b, pop a -> push Bool (numeric compare)
	var EQ; var NE;                                // pop b, pop a -> push Bool (Dynamic == / !=)
	var AND; var OR;                               // pop b, pop a -> push truthy(a)&&truthy(b) / ||  (both pre-evaluated)
	var NOT;                                       // pop a -> push !truthy(a)
	var NEG;                                       // pop a -> push -toNum(a)
	var JZ;           // + Int addr         -> pop v; if !truthy(v) pc = addr
	var JMP;          // + Int addr         -> pc = addr
	var CMP_JZ;       // + Int cmpOp + Int addr -> pop b,a; if !(a <cmp> b) pc = addr  (fused cmp;JZ)
	var ORDER;        // + Int verb + Int hasArg -> submit(verb, hasArg?pop():null, close, index)
	var CALL_BUILTIN; // + Int nameConst + Int argc -> push preserveNum(Reflect.callMethod(globals[name], argv))
	var IND;          // + Int indCode + Int nameConst + Int nParams (+ Int param…) -> push preserveNum(TradeBuiltins.<ind>(harness, name, …))
	                  //   TB0 (TIER_B_BUILD_PLAN.md): statically-dispatched indicator callsite. Only emitted when the
	                  //   series arg resolves to a compile-time NAME and every param is an Int literal, so the exact
	                  //   values the generic CALL_BUILTIN would pass are baked as immediates — the same TradeBuiltins
	                  //   static runs, minus Reflect/argv boxing (no math duplicated ⇒ parity by construction).
	var CROSS;        // + Int csId + Int fnCode + Int argc -> push TradeBuiltins.<fn>CS(harness, csId, ...)
	var LOOKBACK;     // + Int nameConst -> pop n; push harness.seriesLookback(name, Std.int(n))  (series[n])
	var WITH_OFFSET;  // + Int endAddr -> pop n; run [pc,end) under harness.withSeriesOffset(n); push result; pc=end
	                  //   P1.1+broaden: ELookback of ECall/non-series (interp's withSeriesOffset re-entrancy).
	var GET_FIELD;    // + Int fieldConst -> pop o; push o==null ? null : Reflect.getProperty(o, field)  (obj.field)
	var SERIES;       // + Int scrId + Int fnCode + Int argc -> multi-output indicator -> push scratch object
	var POP;                                       // discard top
	var HALT;

	// BAR_FIELD field codes (parity with MuseInterp.refreshBarGlobals).
	public static inline var FIELD_OPEN = 0;
	public static inline var FIELD_HIGH = 1;
	public static inline var FIELD_LOW = 2;
	public static inline var FIELD_CLOSE = 3;
	public static inline var FIELD_VOLUME = 4;
	public static inline var FIELD_TIME = 5;
	public static inline var FIELD_BAR_INDEX = 6;

	// ORDER verb codes.
	public static inline var VERB_LONG = 0;
	public static inline var VERB_SHORT = 1;
	public static inline var VERB_FLAT = 2;

	// CROSS fn codes (the four __cs stateful-callsite builtins).
	public static inline var CS_CROSSOVER = 0;
	public static inline var CS_CROSSUNDER = 1;
	public static inline var CS_RISING = 2;
	public static inline var CS_FALLING = 3;

	// SERIES fn codes (the three __scr multi-output indicators).
	public static inline var SCR_MACD = 0;
	public static inline var SCR_BBANDS = 1;
	public static inline var SCR_STOCH = 2;

	// IND indicator codes (TB0 + widen) — each maps 1:1 to a `TradeBuiltins` static
	// registered under the same name in `TradeBuiltins.install`.
	public static inline var IND_SMA = 0;
	public static inline var IND_EMA = 1;
	public static inline var IND_RSI = 2;
	public static inline var IND_ATR = 3;
	public static inline var IND_HIGHEST = 4;
	public static inline var IND_LOWEST = 5;
	public static inline var IND_STDEV = 6;
	public static inline var IND_WMA = 7;
	public static inline var IND_RMA = 8;
	public static inline var IND_ROC = 9;
	public static inline var IND_MOM = 10;
	public static inline var IND_CHANGE = 11;
	public static inline var IND_PCT_CHANGE = 12;
	// Uniform (src,len) / 0-arg TradeBuiltins already on `install` — same shape as TB0 (BYTECODE_VM_TODO / TB0 residual).
	public static inline var IND_SLOPE = 13;
	public static inline var IND_ZSCORE_ROLL = 14;
	public static inline var IND_PERCENT_RANK = 15;
	public static inline var IND_EWM_VAR = 16;
	public static inline var IND_EWM_STDEV = 17;
	public static inline var IND_HL2 = 18;   // 0-arg
	public static inline var IND_HLC3 = 19;  // 0-arg
	public static inline var IND_OHLC4 = 20; // 0-arg
	public static inline var IND_VWAP = 21;  // 0-arg
}

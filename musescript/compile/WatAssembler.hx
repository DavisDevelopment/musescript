package musescript.compile;

import haxe.io.Bytes;
import haxe.io.BytesBuffer;

/**
 * WAT → binary WebAssembly assembler — ROADMAP.md "In-browser WASM tier".
 *
 * Covers exactly the module shape StrategyWasmEmitter/StrategyWasmRuntimeWat
 * produce (and WasmEmitter's math kernels, which use a subset of it):
 * func imports from "env", one exported memory, mutable i32/f64 globals with
 * const initializers, funcs with named params/results/locals, folded AND flat
 * instruction forms, if/then/else (with optional result type), named
 * block/loop labels, br/br_if, call, return, unreachable, memory.size/grow,
 * plain (offset-less) loads/stores, the i32/f64 ALU ops the emitters use, and the
 * i64 reinterpret/bit ops DetMath.exp/log (`$$det_pow2i` / `$$det_log`) need.
 *
 * NOT a general-purpose assembler: unknown constructs throw with a clear
 * message instead of guessing — the parity gate (wasm tier vs js tier) is
 * only meaningful if nothing silently mis-assembles.
 */
class WatAssembler {
	// ── s-expression parsing ─────────────────────────────────────────────────

	// Sexpr: either an atom (String) or a list (Array<Dynamic> of Sexpr)
	var src:String;
	var pos:Int;

	function new(src:String) {
		this.src = src;
		this.pos = 0;
	}

	/**
	 * Assemble a full `(module ...)` WAT string into binary wasm bytes.
	 * Returns a Bytes tightly sized to its content: BytesBuffer's underlying
	 * storage over-allocates capacity as it grows, and on JS targets
	 * `.getData()` hands back that raw backing buffer — a naive caller doing
	 * `new WebAssembly.Module(bytes.getData())` gets a buffer padded with
	 * trailing garbage past the real module end, which the WASM parser reads
	 * as (invalid) additional sections and rejects. `sub()` copies into a
	 * freshly, exactly sized buffer so `.getData()` is always safe to hand
	 * straight to WebAssembly.Module / any other exact-length-sensitive API.
	 */
	public static function assemble(wat:String):Bytes {
		var p = new WatAssembler(wat);
		var mod = p.parseSexpr();
		if (mod == null || !isList(mod) || atomAt(mod, 0) != "module")
			throw "WatAssembler: expected (module ...)";
		var raw = new ModuleEncoder(cast mod).encode();
		return raw.sub(0, raw.length);
	}

	function parseSexpr():Dynamic {
		skipWs();
		if (pos >= src.length) return null;
		var c = src.charCodeAt(pos);
		if (c == "(".code) {
			pos++;
			var items:Array<Dynamic> = [];
			while (true) {
				skipWs();
				if (pos >= src.length) throw "WatAssembler: unterminated list";
				if (src.charCodeAt(pos) == ")".code) {
					pos++;
					break;
				}
				items.push(parseSexpr());
			}
			return items;
		}
		if (c == '"'.code) {
			pos++;
			var b = new StringBuf();
			while (true) {
				if (pos >= src.length) throw "WatAssembler: unterminated string";
				var ch = src.charCodeAt(pos++);
				if (ch == '"'.code) break;
				if (ch == "\\".code) {
					var e = src.charCodeAt(pos++);
					switch (e) {
						case "n".code: b.addChar("\n".code);
						case "t".code: b.addChar("\t".code);
						case "\\".code, '"'.code: b.addChar(e);
						default: throw "WatAssembler: unsupported string escape";
					}
				} else b.addChar(ch);
			}
			return '"' + b.toString(); // keep a marker so atoms vs strings are distinguishable
		}
		var start = pos;
		while (pos < src.length) {
			var ch = src.charCodeAt(pos);
			if (ch == "(".code || ch == ")".code || ch == '"'.code || isWs(ch)) break;
			pos++;
		}
		return src.substr(start, pos - start);
	}

	function skipWs():Void {
		while (pos < src.length) {
			var c = src.charCodeAt(pos);
			if (isWs(c)) {
				pos++;
			} else if (c == ";".code && pos + 1 < src.length && src.charCodeAt(pos + 1) == ";".code) {
				while (pos < src.length && src.charCodeAt(pos) != "\n".code) pos++;
			} else break;
		}
	}

	static inline function isWs(c:Int):Bool {
		return c == 32 || c == 9 || c == 10 || c == 13;
	}

	public static inline function isList(x:Dynamic):Bool {
		return Std.isOfType(x, Array);
	}

	public static function atomAt(x:Dynamic, i:Int):Null<String> {
		if (!isList(x)) return null;
		var arr:Array<Dynamic> = cast x;
		if (i >= arr.length || isList(arr[i])) return null;
		return cast arr[i];
	}

	public static function strVal(x:Dynamic):String {
		var s:String = cast x;
		return s.substr(1); // strip the '"' marker
	}

	public static inline function isStr(x:Dynamic):Bool {
		return !isList(x) && (cast x : String).charCodeAt(0) == '"'.code;
	}
}

private typedef FuncDecl = {
	var name:String;
	var params:Array<{name:Null<String>, ty:Int}>;
	var results:Array<Int>;
	var locals:Array<{name:Null<String>, ty:Int}>;
	var body:Array<Dynamic>;
}

private class ModuleEncoder {
	static inline var I32 = 0x7F;
	static inline var I64 = 0x7E;
	static inline var F64 = 0x7C;

	var mod:Array<Dynamic>;
	var types:Array<{params:Array<Int>, results:Array<Int>}> = [];
	var imports:Array<{name:String, typeIdx:Int}> = [];
	var funcs:Array<FuncDecl> = [];
	var funcTypeIdx:Array<Int> = []; // parallel to funcs — computed during collect(), BEFORE encodeTypes()
	var funcIndex:Map<String, Int> = new Map();
	var globals:Array<{name:String, ty:Int, mut:Bool, init:Dynamic}> = [];
	var globalIndex:Map<String, Int> = new Map();
	var exports:Array<{name:String, kind:Int, idx:Int, ?funcName:String}> = [];
	var memMin:Int = -1;

	public function new(mod:Array<Dynamic>) {
		this.mod = mod;
	}

	public function encode():Bytes {
		collect();
		var out = new BytesBuffer();
		out.addInt32(0x6D736100); // \0asm (little-endian)
		out.addInt32(1);
		section(out, 1, encodeTypes());
		if (imports.length > 0) section(out, 2, encodeImports());
		section(out, 3, encodeFuncSection());
		if (memMin >= 0) section(out, 5, encodeMemory());
		if (globals.length > 0) section(out, 6, encodeGlobals());
		if (exports.length > 0) section(out, 7, encodeExports());
		section(out, 10, encodeCode());
		return out.getBytes();
	}

	// ── collection pass ─────────────────────────────────────────────────────

	function collect():Void {
		// imports first: they own the low function indices
		for (i in 1...mod.length) {
			var it = mod[i];
			switch (WatAssembler.atomAt(it, 0)) {
				case "import":
					var fdesc:Array<Dynamic> = cast it[3];
					if (WatAssembler.atomAt(fdesc, 0) != "func")
						throw "WatAssembler: only func imports supported";
					var name:String = cast fdesc[1];
					var params:Array<Int> = [];
					var results:Array<Int> = [];
					for (j in 2...fdesc.length) {
						var d = fdesc[j];
						switch (WatAssembler.atomAt(d, 0)) {
							case "param":
								for (k in 1...(cast d : Array<Dynamic>).length) params.push(valType(cast d[k]));
							case "result":
								for (k in 1...(cast d : Array<Dynamic>).length) results.push(valType(cast d[k]));
							default:
								throw "WatAssembler: bad import func desc";
						}
					}
					funcIndex.set(name, imports.length);
					imports.push({ name: WatAssembler.strVal(it[2]), typeIdx: typeIdx(params, results) });
				default:
			}
		}
		for (i in 1...mod.length) {
			var it = mod[i];
			switch (WatAssembler.atomAt(it, 0)) {
				case "memory":
					// (memory (export "name") min) — inline export form
					var arr:Array<Dynamic> = cast it;
					for (j in 1...arr.length) {
						if (WatAssembler.isList(arr[j]) && WatAssembler.atomAt(arr[j], 0) == "export")
							exports.push({ name: WatAssembler.strVal((cast arr[j] : Array<Dynamic>)[1]), kind: 2, idx: 0 });
						else if (!WatAssembler.isList(arr[j]))
							memMin = Std.parseInt(cast arr[j]);
					}
				case "global":
					var arr:Array<Dynamic> = cast it;
					var name:String = cast arr[1];
					var tyExpr = arr[2];
					var mut = false;
					var ty:Int;
					if (WatAssembler.isList(tyExpr) && WatAssembler.atomAt(tyExpr, 0) == "mut") {
						mut = true;
						ty = valType(cast (cast tyExpr : Array<Dynamic>)[1]);
					} else
						ty = valType(cast tyExpr);
					globalIndex.set(name, globals.length);
					globals.push({ name: name, ty: ty, mut: mut, init: arr[3] });
				case "func":
					var f = parseFunc(cast it);
					funcIndex.set(f.name, imports.length + funcs.length);
					funcs.push(f);
					// Register (or dedup into) this func's type NOW, while the type
					// section is still being built — encodeFuncSection later only
					// READS funcTypeIdx, never mutates `types`, so nothing can be
					// discovered after encodeTypes() has already serialized.
					funcTypeIdx.push(typeIdx([for (p in f.params) p.ty], f.results));
				case "export":
					var arr:Array<Dynamic> = cast it;
					var desc:Array<Dynamic> = cast arr[2];
					var kind = switch (WatAssembler.atomAt(desc, 0)) {
						case "func": 0;
						case "memory": 2;
						case k: throw 'WatAssembler: unsupported export kind $k';
					};
					// func index resolved after all funcs are collected
					exports.push({
						name: WatAssembler.strVal(arr[1]),
						kind: kind,
						idx: kind == 0 ? -1 : 0,
						funcName: kind == 0 ? (cast desc[1] : String) : null
					});
				case "import": // handled above
				default:
					throw 'WatAssembler: unsupported module field ${WatAssembler.atomAt(it, 0)}';
			}
		}
		for (e in exports)
			if (e.idx == -1) {
				if (!funcIndex.exists(e.funcName)) throw 'WatAssembler: export of unknown func ${e.funcName}';
				e.idx = funcIndex.get(e.funcName);
			}
	}

	function parseFunc(arr:Array<Dynamic>):FuncDecl {
		var name:String = cast arr[1];
		var params:Array<{name:Null<String>, ty:Int}> = [];
		var results:Array<Int> = [];
		var locals:Array<{name:Null<String>, ty:Int}> = [];
		var body:Array<Dynamic> = [];
		var inBody = false;
		for (i in 2...arr.length) {
			var it = arr[i];
			var head = WatAssembler.atomAt(it, 0);
			if (!inBody && head == "param") {
				var l:Array<Dynamic> = cast it;
				if (l.length == 3 && !WatAssembler.isList(l[1]) && (cast l[1] : String).charCodeAt(0) == "$".code)
					params.push({ name: cast l[1], ty: valType(cast l[2]) });
				else
					for (k in 1...l.length) params.push({ name: null, ty: valType(cast l[k]) });
			} else if (!inBody && head == "result") {
				var l:Array<Dynamic> = cast it;
				for (k in 1...l.length) results.push(valType(cast l[k]));
			} else if (!inBody && head == "local") {
				var l:Array<Dynamic> = cast it;
				if (l.length == 3 && !WatAssembler.isList(l[1]) && (cast l[1] : String).charCodeAt(0) == "$".code)
					locals.push({ name: cast l[1], ty: valType(cast l[2]) });
				else
					for (k in 1...l.length) locals.push({ name: null, ty: valType(cast l[k]) });
			} else {
				inBody = true;
				body.push(it);
			}
		}
		return { name: name, params: params, results: results, locals: locals, body: body };
	}

	function typeIdx(params:Array<Int>, results:Array<Int>):Int {
		for (i in 0...types.length) {
			var t = types[i];
			if (t.params.length == params.length && t.results.length == results.length) {
				var same = true;
				for (j in 0...params.length) if (t.params[j] != params[j]) { same = false; break; }
				if (same) for (j in 0...results.length) if (t.results[j] != results[j]) { same = false; break; }
				if (same) return i;
			}
		}
		types.push({ params: params.copy(), results: results.copy() });
		return types.length - 1;
	}

	static function valType(s:String):Int {
		return switch (s) {
			case "i32": I32;
			case "i64": I64;
			case "f64": F64;
			case t: throw 'WatAssembler: unsupported value type $t';
		};
	}

	// ── section encoders ────────────────────────────────────────────────────

	function section(out:BytesBuffer, id:Int, payload:Bytes):Void {
		out.addByte(id);
		uleb(out, payload.length);
		out.add(payload);
	}

	function encodeTypes():Bytes {
		var b = new BytesBuffer();
		uleb(b, types.length);
		for (t in types) {
			b.addByte(0x60);
			uleb(b, t.params.length);
			for (p in t.params) b.addByte(p);
			uleb(b, t.results.length);
			for (r in t.results) b.addByte(r);
		}
		return b.getBytes();
	}

	function encodeImports():Bytes {
		var b = new BytesBuffer();
		uleb(b, imports.length);
		for (im in imports) {
			name(b, "env");
			name(b, im.name);
			b.addByte(0x00);
			uleb(b, im.typeIdx);
		}
		return b.getBytes();
	}

	function encodeFuncSection():Bytes {
		var b = new BytesBuffer();
		uleb(b, funcs.length);
		for (idx in funcTypeIdx) uleb(b, idx);
		return b.getBytes();
	}

	function encodeMemory():Bytes {
		var b = new BytesBuffer();
		uleb(b, 1);
		b.addByte(0x00); // no max
		uleb(b, memMin);
		return b.getBytes();
	}

	function encodeGlobals():Bytes {
		var b = new BytesBuffer();
		uleb(b, globals.length);
		for (g in globals) {
			b.addByte(g.ty);
			b.addByte(g.mut ? 0x01 : 0x00);
			// init: (i32.const N) | (f64.const X)
			var init:Array<Dynamic> = cast g.init;
			switch (WatAssembler.atomAt(init, 0)) {
				case "i32.const":
					b.addByte(0x41);
					sleb(b, Std.parseInt(cast init[1]));
				case "f64.const":
					b.addByte(0x44);
					f64(b, Std.parseFloat(cast init[1]));
				case op:
					throw 'WatAssembler: unsupported global init $op';
			}
			b.addByte(0x0B);
		}
		return b.getBytes();
	}

	function encodeExports():Bytes {
		var b = new BytesBuffer();
		uleb(b, exports.length);
		for (e in exports) {
			name(b, e.name);
			b.addByte(e.kind);
			uleb(b, e.idx);
		}
		return b.getBytes();
	}

	function encodeCode():Bytes {
		var b = new BytesBuffer();
		uleb(b, funcs.length);
		for (f in funcs) {
			var fb = new BytesBuffer();
			// locals: run-length by type, in declaration order
			var runs:Array<{n:Int, ty:Int}> = [];
			for (l in f.locals) {
				if (runs.length > 0 && runs[runs.length - 1].ty == l.ty)
					runs[runs.length - 1].n++;
				else
					runs.push({ n: 1, ty: l.ty });
			}
			uleb(fb, runs.length);
			for (r in runs) {
				uleb(fb, r.n);
				fb.addByte(r.ty);
			}
			var enc = new FuncBodyEncoder(this, f);
			enc.emitSeq(fb, f.body);
			fb.addByte(0x0B);
			var body = fb.getBytes();
			uleb(b, body.length);
			b.add(body);
		}
		return b.getBytes();
	}

	// ── shared lookups for FuncBodyEncoder ──────────────────────────────────

	public function funcIdx(nm:String):Int {
		if (!funcIndex.exists(nm)) throw 'WatAssembler: call to unknown func $nm';
		return funcIndex.get(nm);
	}

	public function globalIdx(nm:String):Int {
		if (!globalIndex.exists(nm)) throw 'WatAssembler: unknown global $nm';
		return globalIndex.get(nm);
	}

	// ── primitive encoders ──────────────────────────────────────────────────

	public static function uleb(b:BytesBuffer, v:Int):Void {
		while (true) {
			var byte = v & 0x7F;
			v >>>= 7;
			if (v != 0) b.addByte(byte | 0x80) else { b.addByte(byte); break; }
		}
	}

	public static function sleb(b:BytesBuffer, v:Int):Void {
		while (true) {
			var byte = v & 0x7F;
			v >>= 7;
			if ((v == 0 && (byte & 0x40) == 0) || (v == -1 && (byte & 0x40) != 0)) {
				b.addByte(byte);
				break;
			}
			b.addByte(byte | 0x80);
		}
	}

	/** Signed LEB128 for i64.const (DetMath bit reinterpret needs values past i32). */
	public static function sleb64(b:BytesBuffer, v:haxe.Int64):Void {
		while (true) {
			var byte = haxe.Int64.toInt(v & 0x7F);
			v >>= 7;
			if ((v == 0 && (byte & 0x40) == 0) || (v == -1 && (byte & 0x40) != 0)) {
				b.addByte(byte);
				break;
			}
			b.addByte(byte | 0x80);
		}
	}

	public static function f64(b:BytesBuffer, v:Float):Void {
		b.addDouble(v);
	}

	static function name(b:BytesBuffer, s:String):Void {
		var bytes = Bytes.ofString(s);
		uleb(b, bytes.length);
		b.add(bytes);
	}
}

/**
 * Per-function instruction encoder. Handles folded s-expressions (operands
 * emitted before the operator), flat instruction streams, structured
 * if/then/else and labeled block/loop with relative-depth br resolution.
 */
private class FuncBodyEncoder {
	var mod:ModuleEncoder;
	var localIdx:Map<String, Int>;
	var labels:Array<Null<String>>; // innermost last

	public function new(mod:ModuleEncoder, f:FuncDecl) {
		this.mod = mod;
		this.labels = [];
		localIdx = new Map();
		var i = 0;
		for (p in f.params) {
			if (p.name != null) localIdx.set(p.name, i);
			i++;
		}
		for (l in f.locals) {
			if (l.name != null) localIdx.set(l.name, i);
			i++;
		}
	}

	public function emitSeq(b:BytesBuffer, items:Array<Dynamic>):Void {
		// A body is a mix of folded lists and flat atoms; flat atoms may take
		// immediates from the FOLLOWING atoms (e.g. `local.get $x`, `f64.const 3`).
		var i = 0;
		while (i < items.length) {
			var it = items[i];
			if (WatAssembler.isList(it)) {
				emitFolded(b, cast it);
				i++;
			} else {
				i = emitFlat(b, items, i);
			}
		}
	}

	function emitFolded(b:BytesBuffer, l:Array<Dynamic>):Void {
		var op = WatAssembler.atomAt(l, 0);
		switch (op) {
			case "if":
				// (if [(result T)] (cond...) (then ...) [(else ...)])
				var k = 1;
				var blockTy = 0x40;
				if (WatAssembler.isList(l[k]) && WatAssembler.atomAt(l[k], 0) == "result") {
					blockTy = tyByte(cast (cast l[k] : Array<Dynamic>)[1]);
					k++;
				}
				var thenIdx = -1;
				for (j in k...l.length)
					if (WatAssembler.isList(l[j]) && WatAssembler.atomAt(l[j], 0) == "then") {
						thenIdx = j;
						break;
					}
				if (thenIdx < 0) throw "WatAssembler: folded if without (then ...)";
				for (j in k...thenIdx) emitOperand(b, l[j]);
				b.addByte(0x04);
				b.addByte(blockTy);
				labels.push(null);
				emitSeq(b, (cast l[thenIdx] : Array<Dynamic>).slice(1));
				if (thenIdx + 1 < l.length) {
					var el = l[thenIdx + 1];
					if (!WatAssembler.isList(el) || WatAssembler.atomAt(el, 0) != "else")
						throw "WatAssembler: expected (else ...) after (then ...)";
					b.addByte(0x05);
					emitSeq(b, (cast el : Array<Dynamic>).slice(1));
				}
				labels.pop();
				b.addByte(0x0B);
			case "block", "loop":
				var k = 1;
				var label:Null<String> = null;
				if (k < l.length && !WatAssembler.isList(l[k]) && (cast l[k] : String).charCodeAt(0) == "$".code) {
					label = cast l[k];
					k++;
				}
				var blockTy = 0x40;
				if (k < l.length && WatAssembler.isList(l[k]) && WatAssembler.atomAt(l[k], 0) == "result") {
					blockTy = tyByte(cast (cast l[k] : Array<Dynamic>)[1]);
					k++;
				}
				b.addByte(op == "block" ? 0x02 : 0x03);
				b.addByte(blockTy);
				labels.push(label);
				emitSeq(b, l.slice(k));
				labels.pop();
				b.addByte(0x0B);
			case "then", "else":
				throw "WatAssembler: stray (then)/(else)";
			default:
				// generic folded instruction: (op imm* operand*) — immediates are
				// atoms right after the op; operand lists come after.
				var k = 1;
				var imms:Array<String> = [];
				while (k < l.length && !WatAssembler.isList(l[k])) {
					imms.push(cast l[k]);
					k++;
				}
				for (j in k...l.length) emitOperand(b, l[j]);
				emitOp(b, op, imms);
		}
	}

	function emitOperand(b:BytesBuffer, x:Dynamic):Void {
		if (!WatAssembler.isList(x)) throw 'WatAssembler: expected folded operand, got atom $x';
		emitFolded(b, cast x);
	}

	/** Emit a flat instruction starting at items[i]; returns the next index. */
	function emitFlat(b:BytesBuffer, items:Array<Dynamic>, i:Int):Int {
		var op:String = cast items[i];
		switch (op) {
			case "if":
				// flat if: condition already on stack; optional (result T) follows
				var blockTy = 0x40;
				var j = i + 1;
				if (j < items.length && WatAssembler.isList(items[j]) && WatAssembler.atomAt(items[j], 0) == "result") {
					blockTy = tyByte(cast (cast items[j] : Array<Dynamic>)[1]);
					j++;
				}
				b.addByte(0x04);
				b.addByte(blockTy);
				labels.push(null);
				// consume until matching flat `else`/`end`
				var depth = 0;
				var seg:Array<Dynamic> = [];
				while (j < items.length) {
					var it = items[j];
					if (!WatAssembler.isList(it)) {
						var a:String = cast it;
						if ((a == "if" || a == "block" || a == "loop")) depth++;
						if (a == "end") {
							if (depth == 0) break;
							depth--;
						}
						if (a == "else" && depth == 0) break;
					}
					seg.push(it);
					j++;
				}
				emitSeq(b, seg);
				if (j < items.length && !WatAssembler.isList(items[j]) && (cast items[j] : String) == "else") {
					b.addByte(0x05);
					j++;
					var seg2:Array<Dynamic> = [];
					var depth2 = 0;
					while (j < items.length) {
						var it = items[j];
						if (!WatAssembler.isList(it)) {
							var a:String = cast it;
							if (a == "if" || a == "block" || a == "loop") depth2++;
							if (a == "end") {
								if (depth2 == 0) break;
								depth2--;
							}
						}
						seg2.push(it);
						j++;
					}
					emitSeq(b, seg2);
				}
				if (j >= items.length || (cast items[j] : String) != "end")
					throw "WatAssembler: flat if without end";
				labels.pop();
				b.addByte(0x0B);
				return j + 1;
			case "end", "else":
				throw 'WatAssembler: unexpected flat $op';
			default:
				// ops taking one immediate atom
				var immCount = switch (op) {
					case "local.get", "local.set", "local.tee", "global.get", "global.set",
						"i32.const", "f64.const", "call", "br", "br_if": 1;
					default: 0;
				};
				var imms:Array<String> = [];
				for (k in 0...immCount) {
					var nx = items[i + 1 + k];
					if (WatAssembler.isList(nx)) throw 'WatAssembler: $op expects immediate';
					imms.push(cast nx);
				}
				emitOp(b, op, imms);
				return i + 1 + immCount;
		}
	}

	static function tyByte(s:String):Int {
		return switch (s) {
			case "i32": 0x7F;
			case "f64": 0x7C;
			case t: throw 'WatAssembler: unsupported block result type $t';
		};
	}

	function labelDepth(nm:String):Int {
		var i = labels.length - 1;
		var depth = 0;
		while (i >= 0) {
			if (labels[i] == nm) return depth;
			depth++;
			i--;
		}
		throw 'WatAssembler: unknown label $nm';
	}

	function local(nm:String):Int {
		if (!localIdx.exists(nm)) throw 'WatAssembler: unknown local $nm';
		return localIdx.get(nm);
	}

	function emitOp(b:BytesBuffer, op:String, imms:Array<String>):Void {
		inline function u(v:Int) ModuleEncoder.uleb(b, v);
		switch (op) {
			case "unreachable": b.addByte(0x00);
			case "nop": b.addByte(0x01);
			case "return": b.addByte(0x0F);
			case "br": b.addByte(0x0C); u(labelDepth(imms[0]));
			case "br_if": b.addByte(0x0D); u(labelDepth(imms[0]));
			case "call": b.addByte(0x10); u(mod.funcIdx(imms[0]));
			case "drop": b.addByte(0x1A);
			case "select": b.addByte(0x1B);
			case "local.get": b.addByte(0x20); u(local(imms[0]));
			case "local.set": b.addByte(0x21); u(local(imms[0]));
			case "local.tee": b.addByte(0x22); u(local(imms[0]));
			case "global.get": b.addByte(0x23); u(mod.globalIdx(imms[0]));
			case "global.set": b.addByte(0x24); u(mod.globalIdx(imms[0]));
			case "i32.load": b.addByte(0x28); b.addByte(2); b.addByte(0);
			case "f64.load": b.addByte(0x2B); b.addByte(3); b.addByte(0);
			case "i32.store": b.addByte(0x36); b.addByte(2); b.addByte(0);
			case "f64.store": b.addByte(0x39); b.addByte(3); b.addByte(0);
			case "i32.store8": b.addByte(0x3A); b.addByte(0); b.addByte(0);
			case "memory.size": b.addByte(0x3F); b.addByte(0x00);
			case "memory.grow": b.addByte(0x40); b.addByte(0x00);
			case "i32.const": b.addByte(0x41); ModuleEncoder.sleb(b, parseI32(imms[0]));
			case "i64.const": b.addByte(0x42); ModuleEncoder.sleb64(b, parseI64(imms[0]));
			case "f64.const": b.addByte(0x44); ModuleEncoder.f64(b, parseF64(imms[0]));
			case "i32.eqz": b.addByte(0x45);
			case "i32.eq": b.addByte(0x46);
			case "i32.ne": b.addByte(0x47);
			case "i32.lt_s": b.addByte(0x48);
			case "i32.lt_u": b.addByte(0x49);
			case "i32.gt_s": b.addByte(0x4A);
			case "i32.gt_u": b.addByte(0x4B);
			case "i32.le_s": b.addByte(0x4C);
			case "i32.le_u": b.addByte(0x4D);
			case "i32.ge_s": b.addByte(0x4E);
			case "i32.ge_u": b.addByte(0x4F);
			case "f64.eq": b.addByte(0x61);
			case "f64.ne": b.addByte(0x62);
			case "f64.lt": b.addByte(0x63);
			case "f64.gt": b.addByte(0x64);
			case "f64.le": b.addByte(0x65);
			case "f64.ge": b.addByte(0x66);
			case "i32.add": b.addByte(0x6A);
			case "i32.sub": b.addByte(0x6B);
			case "i32.mul": b.addByte(0x6C);
			case "i32.div_s": b.addByte(0x6D);
			case "i32.rem_s": b.addByte(0x6F);
			case "i32.and": b.addByte(0x71);
			case "i32.or": b.addByte(0x72);
			case "i32.xor": b.addByte(0x73);
			case "i32.shl": b.addByte(0x74);
			case "i32.shr_s": b.addByte(0x75);
			case "i32.shr_u": b.addByte(0x76);
			case "f64.abs": b.addByte(0x99);
			case "f64.neg": b.addByte(0x9A);
			case "f64.ceil": b.addByte(0x9B);
			case "f64.floor": b.addByte(0x9C);
			case "f64.trunc": b.addByte(0x9D);
			case "f64.nearest": b.addByte(0x9E);
			case "f64.sqrt": b.addByte(0x9F);
			case "f64.add": b.addByte(0xA0);
			case "f64.sub": b.addByte(0xA1);
			case "f64.mul": b.addByte(0xA2);
			case "f64.div": b.addByte(0xA3);
			case "f64.min": b.addByte(0xA4);
			case "f64.max": b.addByte(0xA5);
			case "i32.trunc_f64_s": b.addByte(0xAA);
			case "f64.convert_i32_s": b.addByte(0xB7);
			// i64 subset for DetMath.exp/log bit reinterpret (StrategyWasmRuntimeWat)
			case "i64.and": b.addByte(0x83);
			case "i64.or": b.addByte(0x84);
			case "i64.xor": b.addByte(0x85);
			case "i64.shl": b.addByte(0x86);
			case "i64.shr_s": b.addByte(0x87);
			case "i64.shr_u": b.addByte(0x88);
			case "i32.wrap_i64": b.addByte(0xA7);
			case "i64.extend_i32_s": b.addByte(0xAC);
			case "i64.extend_i32_u": b.addByte(0xAD);
			case "i64.reinterpret_f64": b.addByte(0xBD);
			case "f64.reinterpret_i64": b.addByte(0xBF);
			default:
				throw 'WatAssembler: unsupported instruction $op';
		}
	}

	static function parseI32(s:String):Int {
		var v = Std.parseInt(s);
		if (v == null) throw 'WatAssembler: bad i32 literal $s';
		return v;
	}

	static function parseI64(s:String):haxe.Int64 {
		var neg = false;
		var t = s;
		if (StringTools.startsWith(t, "-")) {
			neg = true;
			t = t.substr(1);
		}
		if (t.length == 0) throw 'WatAssembler: bad i64 literal $s';
		var v = haxe.Int64.ofInt(0);
		for (i in 0...t.length) {
			var d = t.charCodeAt(i) - "0".code;
			if (d < 0 || d > 9) throw 'WatAssembler: bad i64 literal $s';
			v = v * 10 + d;
		}
		return neg ? -v : v;
	}

	static function parseF64(s:String):Float {
		if (s == "nan") return Math.NaN;
		if (s == "inf") return Math.POSITIVE_INFINITY;
		if (s == "-inf") return Math.NEGATIVE_INFINITY;
		var v = Std.parseFloat(s);
		if (Math.isNaN(v) && s != "nan") throw 'WatAssembler: bad f64 literal $s';
		return v;
	}
}

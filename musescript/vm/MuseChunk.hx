package musescript.vm;

/**
 * Compiled stack-bytecode artifact (SPEC_BYTECODE_VM.md §1). Emitted by
 * `MuseBytecodeCompiler` for the P0 subset (strategy `onBar`/`when`/`order`),
 * executed by `MuseVm`.
 *
 * P0 is deliberately a flat `Int` instruction array + a `Dynamic` constant pool
 * + a local-slot layout — the "small VM, large parity harness" split the spec
 * calls for. The unboxed numeric operand path, superinstructions and inline
 * caches are P1; here the operand stack is `Dynamic` and every value op routes
 * through `MuseVmOps` so the VM is byte-identical to `MuseInterp` by construction
 * (§4). The compiled artifact is what an oracle memo can eventually cache (§6).
 */
@:structInit
class MuseChunk {
	/** Flat instruction stream: opcode Ints interleaved with inline operand Ints (see `Op`). */
	public var code:Array<Int> = [];
	/** Constant pool — `CONST k` pushes `consts[k]` (Int/Float/Bool/String/null). */
	public var consts:Array<Dynamic> = [];
	/** Local-slot names, indexed by slot (parity: series pushes key by name — §Assign). */
	public var localNames:Array<String> = [];

	public function new(?code:Array<Int>, ?consts:Array<Dynamic>, ?localNames:Array<String>) {
		this.code = code != null ? code : [];
		this.consts = consts != null ? consts : [];
		this.localNames = localNames != null ? localNames : [];
	}

	public inline function localCount():Int return localNames.length;
}

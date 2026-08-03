package musescript.vm;

/**
 * Compiled stack-bytecode artifact (SPEC_BYTECODE_VM.md §1). Emitted by
 * `MuseBytecodeCompiler` for the P0 subset (strategy `onBar`/`when`/`order`),
 * executed by `MuseVm`.
 *
 * P1.1: tagged unboxed numeric operand path (`tags`/`nums`/`objs` in `MuseVm`).
 * P1a/P1b: builtin IC + `CMP_JZ`. Observable values stay byte-identical to `MuseInterp`
 * via `MuseVmOps` at Dynamic boundaries (§4). The compiled artifact is what the oracle
 * memo caches (`Fitness.vmChunkCache`, §6).
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

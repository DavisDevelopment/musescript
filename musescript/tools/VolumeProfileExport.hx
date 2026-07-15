package musescript.tools;

import haxe.Json;
import musescript.compile.MathCompiler;
import musescript.compile.MathOnly;
import musescript.parse.MuseParser;
import sys.FileSystem;
import sys.io.File;

/**
 * Deterministically exports the versioned browser VPVR kernel.
 *
 * ABI (all arrays are mutable f64 regions in exported memory):
 * volume_profile_v1(highsBase, highsLen, lowsBase, lowsLen, volumesBase,
 * volumesLen, outputBase, outputLen, n, binsLen, minPrice, maxPrice) -> f64
 */
class VolumeProfileExport {
	static final KERNEL = "volume_profile_v1";
	static final VERSION = 1;

	static function main():Void {
		var args = Sys.args();
		var outputDir = args.length > 0
			? args[0]
			: "../../mobile/src/charting/indicators/musekernels";
		outputDir = FileSystem.absolutePath(outputDir);
		if (!FileSystem.exists(outputDir)) FileSystem.createDirectory(outputDir);

		var sourcePath = FileSystem.absolutePath("kernels/volume_profile_v1.ms");
		var source = File.getContent(sourcePath);
		var program = new MuseParser().parse(source, sourcePath);
		if (MathOnly.find(program, KERNEL) == null) {
			throw "Volume Profile source failed MathOnly validation: " + Std.string(program.decls);
		}
		var wat = MathCompiler.emit(program, KERNEL, { target: "wasm" });
		var jsSource = MathCompiler.emit(program, KERNEL, { target: "js" });
		if (wat == null) throw "Volume Profile kernel is outside the WASM math emitter subset";
		if (jsSource == null) throw "Volume Profile kernel is outside the JS math emitter subset";

		var stem = outputDir + "/volume-profile-v1";
		var watPath = stem + ".wat";
		var wasmPath = stem + ".wasm";
		File.saveContent(watPath, wat);
		File.saveContent(stem + ".generated.js", jsSource + "\n");

		var python = FileSystem.exists(".venv/Scripts/python.exe")
			? ".venv/Scripts/python.exe"
			: ".venv/bin/python";
		var exitCode = Sys.command(python, ["tools/wat2wasm_cli.py", watPath, wasmPath]);
		if (exitCode != 0) throw 'wat2wasm failed with exit code $exitCode';

		var bytes = File.getBytes(wasmPath);
		var crypto:Dynamic = js.Syntax.code("require('crypto')");
		var hash:String = crypto.createHash("sha256").update(bytes.getData()).digest("hex");
		var manifest:Dynamic = {
			kernel: KERNEL,
			version: VERSION,
			sha256: hash,
			source: "kernels/volume_profile_v1.ms",
			semantics: "uniform candle-range overlap; final-bin remainder conserves volume",
			abi: {
				memory: "exported",
				elementType: "f64",
				mutableOutput: true,
				parameters: [
					"highsBase:i32", "highsLen:i32",
					"lowsBase:i32", "lowsLen:i32",
					"volumesBase:i32", "volumesLen:i32",
					"outputBase:i32", "outputLen:i32",
					"n:i32", "binsLen:i32", "minPrice:f64", "maxPrice:f64"
				],
				result: "acceptedVolume:f64"
			}
		};
		File.saveContent(stem + ".manifest.json", Json.stringify(manifest, null, "  ") + "\n");
		Sys.println('exported $wasmPath sha256=$hash');
	}
}

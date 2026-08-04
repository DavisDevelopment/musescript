package musescript.builtins;

import musescript.io.FsGrant;
import musescript.io.IoDenied;
import musescript.io.IoGrant;

/**
 * Sandboxed `muse.fs` / `fs_*` — grant-gated sync filesystem ops.
 *
 * Default (null grants): every call throws {@link IoDenied}.
 * Reads require a root with `read:true`; writes require `write:true`.
 */
class FsBuiltins {
	public static function install(vars:Map<String, Dynamic>, ?grantsOf:Void->Null<IoGrant>):Void {
		var g = grantsOf == null ? function() return null : grantsOf;
		vars.set("fs_read_text", function(path:Dynamic) return readText(g(), path));
		vars.set("fs_write_text", function(path:Dynamic, body:Dynamic) return writeText(g(), path, body));
		vars.set("fs_append_text", function(path:Dynamic, body:Dynamic) return appendText(g(), path, body));
		vars.set("fs_exists", function(path:Dynamic) return exists(g(), path));
		vars.set("fs_is_dir", function(path:Dynamic) return isDir(g(), path));
		vars.set("fs_is_file", function(path:Dynamic) return isFile(g(), path));
		vars.set("fs_list", function(path:Dynamic) return list(g(), path));
		vars.set("fs_mkdir", function(path:Dynamic, ?recursive:Dynamic) return mkdir(g(), path, recursive));
		vars.set("fs_read_bytes", function(path:Dynamic) {
			return throwUnavailable("fs_read_bytes", "use M2+; prefer fs_read_text");
		});
	}

	public static function build(?grantsOf:Void->Null<IoGrant>):Dynamic {
		var g = grantsOf == null ? function() return null : grantsOf;
		var f:Dynamic = {};
		Reflect.setField(f, "read_text", function(path:Dynamic) return readText(g(), path));
		Reflect.setField(f, "write_text", function(path:Dynamic, body:Dynamic) return writeText(g(), path, body));
		Reflect.setField(f, "append_text", function(path:Dynamic, body:Dynamic) return appendText(g(), path, body));
		Reflect.setField(f, "exists", function(path:Dynamic) return exists(g(), path));
		Reflect.setField(f, "is_dir", function(path:Dynamic) return isDir(g(), path));
		Reflect.setField(f, "is_file", function(path:Dynamic) return isFile(g(), path));
		Reflect.setField(f, "list", function(path:Dynamic) return list(g(), path));
		Reflect.setField(f, "mkdir", function(path:Dynamic, ?recursive:Dynamic) return mkdir(g(), path, recursive));
		Reflect.setField(f, "read_bytes", function(path:Dynamic) {
			return throwUnavailable("fs_read_bytes", "use M2+; prefer fs_read_text");
		});
		return f;
	}

	public static function readText(?grants:Null<IoGrant>, path:Dynamic):String {
		ensureFsHost("fs_read_text");
		var r = FsGrant.resolve("fs_read_text", grants, text(path), false);
		#if (sys || nodejs)
		if (!sys.FileSystem.exists(r.nativeAbs) || sys.FileSystem.isDirectory(r.nativeAbs))
			throw new IoDenied("fs_read_text", 'not a file: ${r.museAbs}');
		return sys.io.File.getContent(r.nativeAbs);
		#else
		return throwUnavailable("fs_read_text", "filesystem unavailable on this host");
		#end
	}

	public static function writeText(?grants:Null<IoGrant>, path:Dynamic, body:Dynamic):Bool {
		ensureFsHost("fs_write_text");
		var r = FsGrant.resolve("fs_write_text", grants, text(path), true);
		#if (sys || nodejs)
		sys.io.File.saveContent(r.nativeAbs, text(body));
		return true;
		#else
		return throwUnavailable("fs_write_text", "filesystem unavailable on this host");
		#end
	}

	public static function appendText(?grants:Null<IoGrant>, path:Dynamic, body:Dynamic):Bool {
		ensureFsHost("fs_append_text");
		var r = FsGrant.resolve("fs_append_text", grants, text(path), true);
		#if (sys || nodejs)
		var prev = sys.FileSystem.exists(r.nativeAbs) ? sys.io.File.getContent(r.nativeAbs) : "";
		sys.io.File.saveContent(r.nativeAbs, prev + text(body));
		return true;
		#else
		return throwUnavailable("fs_append_text", "filesystem unavailable on this host");
		#end
	}

	public static function exists(?grants:Null<IoGrant>, path:Dynamic):Bool {
		ensureFsHost("fs_exists");
		var r = FsGrant.resolve("fs_exists", grants, text(path), false);
		#if (sys || nodejs)
		return sys.FileSystem.exists(r.nativeAbs);
		#else
		return throwUnavailable("fs_exists", "filesystem unavailable on this host");
		#end
	}

	public static function isDir(?grants:Null<IoGrant>, path:Dynamic):Bool {
		ensureFsHost("fs_is_dir");
		var r = FsGrant.resolve("fs_is_dir", grants, text(path), false);
		#if (sys || nodejs)
		return sys.FileSystem.exists(r.nativeAbs) && sys.FileSystem.isDirectory(r.nativeAbs);
		#else
		return throwUnavailable("fs_is_dir", "filesystem unavailable on this host");
		#end
	}

	public static function isFile(?grants:Null<IoGrant>, path:Dynamic):Bool {
		ensureFsHost("fs_is_file");
		var r = FsGrant.resolve("fs_is_file", grants, text(path), false);
		#if (sys || nodejs)
		return sys.FileSystem.exists(r.nativeAbs) && !sys.FileSystem.isDirectory(r.nativeAbs);
		#else
		return throwUnavailable("fs_is_file", "filesystem unavailable on this host");
		#end
	}

	public static function list(?grants:Null<IoGrant>, path:Dynamic):Array<String> {
		ensureFsHost("fs_list");
		var r = FsGrant.resolve("fs_list", grants, text(path), false);
		#if (sys || nodejs)
		if (!sys.FileSystem.exists(r.nativeAbs) || !sys.FileSystem.isDirectory(r.nativeAbs))
			throw new IoDenied("fs_list", 'not a directory: ${r.museAbs}');
		var names = sys.FileSystem.readDirectory(r.nativeAbs);
		names.sort(Reflect.compare);
		return names;
		#else
		return throwUnavailable("fs_list", "filesystem unavailable on this host");
		#end
	}

	public static function mkdir(?grants:Null<IoGrant>, path:Dynamic, ?recursive:Dynamic):Bool {
		ensureFsHost("fs_mkdir");
		var r = FsGrant.resolve("fs_mkdir", grants, text(path), true);
		#if (sys || nodejs)
		var rec = recursive == true || recursive == 1 || recursive == "true";
		if (sys.FileSystem.exists(r.nativeAbs)) {
			if (sys.FileSystem.isDirectory(r.nativeAbs)) return true;
			throw new IoDenied("fs_mkdir", 'exists and is not a directory: ${r.museAbs}');
		}
		if (rec) {
			createDirectoryRecursive(r.nativeAbs);
		} else {
			sys.FileSystem.createDirectory(r.nativeAbs);
		}
		return true;
		#else
		return throwUnavailable("fs_mkdir", "filesystem unavailable on this host");
		#end
	}

	static function ensureFsHost(op:String):Void {
		#if !(sys || nodejs)
		throw new IoDenied(op, "filesystem unavailable on this host");
		#end
	}

	static function throwUnavailable(op:String, detail:String):Dynamic {
		throw new IoDenied(op, detail);
	}

	#if (sys || nodejs)
	static function createDirectoryRecursive(nativeAbs:String):Void {
		var muse = StringTools.replace(nativeAbs, "\\", "/");
		var parts = muse.split("/");
		var cur = "";
		for (i in 0...parts.length) {
			var seg = parts[i];
			if (seg.length == 0) {
				if (i == 0) cur = "/";
				continue;
			}
			// Windows drive letter chunk `C:`
			if (i == 0 && seg.length == 2 && seg.charAt(1) == ":") {
				cur = seg;
				continue;
			}
			cur = cur.length == 0 || cur == "/" ? (cur == "/" ? "/" + seg : seg) : cur + "/" + seg;
			var native = Sys.systemName() == "Windows" ? StringTools.replace(cur, "/", "\\") : cur;
			if (!sys.FileSystem.exists(native))
				sys.FileSystem.createDirectory(native);
		}
	}
	#end

	static inline function text(v:Dynamic):String {
		return v == null ? "" : Std.string(v);
	}
}

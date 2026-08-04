package musescript.io;

import haxe.Json;
import haxe.crypto.Sha1;

/**
 * On-disk HTTP fixture store keyed by `(method, url, body_hash)`.
 *
 * Replay miss → hard error (never silent live). Record writes JSON under
 * `fixture_dir` for bit-identical replay later.
 */
class FixtureStore {
	public var dir:String;

	public function new(fixtureDir:String) {
		if (fixtureDir == null || StringTools.trim(fixtureDir).length == 0)
			throw new IoDenied("http_request", "net grant missing fixture_dir");
		this.dir = normalizeDir(fixtureDir);
	}

	public static function bodyHash(body:Null<String>):String {
		var b = body == null ? "" : body;
		return Sha1.encode(b);
	}

	public function key(method:String, url:String, body:Null<String>):String {
		var m = method == null ? "GET" : method.toUpperCase();
		var u = url == null ? "" : url;
		return Sha1.encode(m + "\n" + u + "\n" + bodyHash(body));
	}

	public function pathFor(method:String, url:String, body:Null<String>):String {
		var k = key(method, url, body);
		return join(dir, "http_" + k.substr(0, 40) + ".json");
	}

	/**
	 * Load a fixture or throw {@link IoDenied} on miss.
	 */
	public function load(op:String, method:String, url:String, body:Null<String>):Dynamic {
		#if (sys || nodejs)
		var path = pathFor(method, url, body);
		if (!sys.FileSystem.exists(path) || sys.FileSystem.isDirectory(path))
			throw new IoDenied(op, 'HTTP fixture miss (replay): ${method.toUpperCase()} $url — expected $path');
		var raw = sys.io.File.getContent(path);
		var obj:Dynamic = Json.parse(raw);
		return normalizeResp(obj);
		#else
		return throw new IoDenied(op, "HTTP fixtures unavailable on this host");
		#end
	}

	public function save(method:String, url:String, body:Null<String>, resp:Dynamic):Void {
		#if (sys || nodejs)
		ensureDir(dir);
		var path = pathFor(method, url, body);
		var payload = {
			method: method == null ? "GET" : method.toUpperCase(),
			url: url,
			body_hash: bodyHash(body),
			status: Reflect.field(resp, "status"),
			headers: Reflect.field(resp, "headers"),
			body_text: Reflect.field(resp, "body_text"),
			url_final: Reflect.field(resp, "url_final")
		};
		sys.io.File.saveContent(path, Json.stringify(payload));
		#else
		throw new IoDenied("http_request", "HTTP fixtures unavailable on this host");
		#end
	}

	static function normalizeResp(obj:Dynamic):Dynamic {
		var headers:Dynamic = Reflect.field(obj, "headers");
		if (headers == null) headers = {};
		var status = Reflect.field(obj, "status");
		var body = Reflect.field(obj, "body_text");
		var urlFinal = Reflect.field(obj, "url_final");
		return {
			status: status == null ? 0 : Std.int(status),
			headers: headers,
			body_text: body == null ? "" : Std.string(body),
			url_final: urlFinal == null ? "" : Std.string(urlFinal)
		};
	}

	static function normalizeDir(d:String):String {
		var s = StringTools.replace(StringTools.trim(d), "\\", "/");
		while (s.length > 1 && StringTools.endsWith(s, "/")) s = s.substr(0, s.length - 1);
		return s;
	}

	static function join(a:String, b:String):String {
		var left = normalizeDir(a);
		return left + "/" + b;
	}

	#if (sys || nodejs)
	static function ensureDir(museDir:String):Void {
		var native = toNative(museDir);
		if (sys.FileSystem.exists(native)) {
			if (!sys.FileSystem.isDirectory(native))
				throw new IoDenied("http_request", 'fixture_dir is not a directory: $museDir');
			return;
		}
		createDirectoryRecursive(native);
	}

	static function toNative(museAbs:String):String {
		if (Sys.systemName() == "Windows")
			return StringTools.replace(museAbs, "/", "\\");
		return museAbs;
	}

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
}

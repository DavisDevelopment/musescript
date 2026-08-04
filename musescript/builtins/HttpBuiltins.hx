package musescript.builtins;

import musescript.harness.HarnessContext;
import musescript.io.FixtureStore;
import musescript.io.HttpTransport;
import musescript.io.IoDenied;
import musescript.io.IoGrant;
import musescript.io.NetGrant;
import musescript.io.NetGrants;

/**
 * Grant-gated `muse.http` / `http_*` — sync API with fixture replay/record.
 *
 * Default grant mode is **replay** (backtest must never silent-live).
 * Fitness / `isBacktest` refuse `strict` live; `record` requires CLI flag.
 */
class HttpBuiltins {
	public static function install(
		vars:Map<String, Dynamic>,
		?grantsOf:Void->Null<IoGrant>,
		?harnessOf:Void->Null<HarnessContext>
	):Void {
		var g = grantsOf == null ? function() return null : grantsOf;
		var h = harnessOf == null ? function() return null : harnessOf;
		vars.set("http_request", function(opts:Dynamic) return request(g(), h(), opts));
		vars.set("http_get", function(url:Dynamic, ?opts:Dynamic) return get(g(), h(), url, opts));
		vars.set("http_post", function(url:Dynamic, ?bodyOrOpts:Dynamic, ?opts:Dynamic) {
			return post(g(), h(), url, bodyOrOpts, opts);
		});
	}

	public static function build(
		?grantsOf:Void->Null<IoGrant>,
		?harnessOf:Void->Null<HarnessContext>
	):Dynamic {
		var g = grantsOf == null ? function() return null : grantsOf;
		var h = harnessOf == null ? function() return null : harnessOf;
		var o:Dynamic = {};
		Reflect.setField(o, "request", function(opts:Dynamic) return request(g(), h(), opts));
		Reflect.setField(o, "get", function(url:Dynamic, ?opts:Dynamic) return get(g(), h(), url, opts));
		Reflect.setField(o, "post", function(url:Dynamic, ?bodyOrOpts:Dynamic, ?opts:Dynamic) {
			return post(g(), h(), url, bodyOrOpts, opts);
		});
		return o;
	}

	public static function get(
		?grants:Null<IoGrant>,
		?harness:Null<HarnessContext>,
		url:Dynamic,
		?opts:Dynamic
	):Dynamic {
		var o:Dynamic = opts == null ? {} : copyOpts(opts);
		Reflect.setField(o, "method", "GET");
		Reflect.setField(o, "url", text(url));
		return request(grants, harness, o);
	}

	public static function post(
		?grants:Null<IoGrant>,
		?harness:Null<HarnessContext>,
		url:Dynamic,
		?bodyOrOpts:Dynamic,
		?opts:Dynamic
	):Dynamic {
		var o:Dynamic;
		var body:Null<String> = null;
		if (opts != null) {
			o = copyOpts(opts);
			body = bodyOrOpts == null ? null : text(bodyOrOpts);
		} else if (bodyOrOpts != null && Std.isOfType(bodyOrOpts, String)) {
			o = {};
			body = text(bodyOrOpts);
		} else if (bodyOrOpts != null && isPlainObject(bodyOrOpts)) {
			o = copyOpts(bodyOrOpts);
			if (Reflect.hasField(o, "body")) body = text(Reflect.field(o, "body"));
		} else {
			o = {};
			body = bodyOrOpts == null ? null : text(bodyOrOpts);
		}
		Reflect.setField(o, "method", "POST");
		Reflect.setField(o, "url", text(url));
		if (body != null) Reflect.setField(o, "body", body);
		return request(grants, harness, o);
	}

	public static function request(
		?grants:Null<IoGrant>,
		?harness:Null<HarnessContext>,
		opts:Dynamic
	):Dynamic {
		var op = "http_request";
		var net = NetGrants.require(op, grants);
		if (opts == null) throw new IoDenied(op, "request opts required");

		var method = fieldStr(opts, "method", "GET").toUpperCase();
		var url = fieldStr(opts, "url", "");
		if (url.length == 0) throw new IoDenied(op, "url required");
		var headers:Dynamic = Reflect.hasField(opts, "headers") ? Reflect.field(opts, "headers") : {};
		var body:Null<String> = Reflect.hasField(opts, "body") ? text(Reflect.field(opts, "body")) : null;
		var redirect = fieldStr(opts, "redirect", "error").toLowerCase();
		var follow = redirect == "follow";
		if (redirect != "error" && redirect != "follow")
			throw new IoDenied(op, 'redirect must be "error" or "follow"');

		var parsed = parseUrl(op, url);
		NetGrants.assertSchemeAllowed(op, net, parsed.scheme);
		NetGrants.assertHostAllowed(op, net, parsed.host);

		var timeout = NetGrants.timeoutMs(net, fieldInt(opts, "timeout_ms"));
		var maxBytes = NetGrants.maxBytes(net);
		var mode = NetGrants.modeOf(net);

		bumpRequestCount(op, net, harness);

		var isFitness = harness != null && harness.isFitness;
		var isBacktest = harness == null || harness.isBacktest;

		if (mode == NetGrants.MODE_STRICT) {
			if (isFitness || isBacktest)
				throw new IoDenied(op, "refuse live HTTP in backtest/fitness (use fixture replay; never silent-live)");
			return HttpTransport.live(op, method, url, headers, body, timeout, maxBytes, follow);
		}

		if (mode == NetGrants.MODE_RECORD) {
			if (isFitness)
				throw new IoDenied(op, "refuse HTTP record in fitness path");
			var store = new FixtureStore(net.fixture_dir);
			var resp = HttpTransport.live(op, method, url, headers, body, timeout, maxBytes, follow);
			store.save(method, url, body, resp);
			return resp;
		}

		// replay (default)
		if (net.fixture_dir == null || StringTools.trim(net.fixture_dir).length == 0)
			throw new IoDenied(op, "net grant missing fixture_dir for replay");
		return new FixtureStore(net.fixture_dir).load(op, method, url, body);
	}

	static function bumpRequestCount(op:String, net:NetGrant, harness:Null<HarnessContext>):Void {
		if (harness != null) {
			harness.httpRequests++;
			if (net.max_requests_per_run != null && harness.httpRequests > net.max_requests_per_run)
				throw new IoDenied(op, 'max_requests_per_run exceeded (${net.max_requests_per_run})');
		}
	}

	static function parseUrl(op:String, url:String):{ scheme:String, host:String } {
		var s = StringTools.trim(url);
		var schemeSep = s.indexOf("://");
		if (schemeSep <= 0) throw new IoDenied(op, 'invalid url (need scheme): $url');
		var scheme = s.substr(0, schemeSep).toLowerCase();
		var rest = s.substr(schemeSep + 3);
		var slash = rest.indexOf("/");
		var authority = slash < 0 ? rest : rest.substr(0, slash);
		var at = authority.lastIndexOf("@");
		if (at >= 0) authority = authority.substr(at + 1);
		var colon = authority.indexOf(":");
		var host = colon < 0 ? authority : authority.substr(0, colon);
		if (host.length == 0) throw new IoDenied(op, 'invalid url host: $url');
		return { scheme: scheme, host: host };
	}

	static function copyOpts(opts:Dynamic):Dynamic {
		var o:Dynamic = {};
		for (k in Reflect.fields(opts)) Reflect.setField(o, k, Reflect.field(opts, k));
		return o;
	}

	static function isPlainObject(v:Dynamic):Bool {
		if (v == null) return false;
		if (Std.isOfType(v, String) || Std.isOfType(v, Array)) return false;
		#if js
		return js.Syntax.typeof(v) == "object";
		#else
		return Reflect.isObject(v);
		#end
	}

	static function fieldStr(opts:Dynamic, name:String, def:String):String {
		if (!Reflect.hasField(opts, name)) return def;
		var v = Reflect.field(opts, name);
		return v == null ? def : Std.string(v);
	}

	static function fieldInt(opts:Dynamic, name:String):Null<Int> {
		if (!Reflect.hasField(opts, name)) return null;
		var v = Reflect.field(opts, name);
		if (v == null) return null;
		return Std.int(v);
	}

	static inline function text(v:Dynamic):String {
		return v == null ? "" : Std.string(v);
	}
}

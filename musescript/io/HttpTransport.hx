package musescript.io;

/**
 * Target-native HTTP transport under one Muse signature.
 *
 * - JVM: `java.net.HttpURLConnection`
 * - Node (hxnodejs): sync Worker + `fetch`
 * - Tests: {@link HttpTransport.testLive} override (no network)
 *
 * No cookies / WebSocket. Redirects default to error (determinism).
 */
class HttpTransport {
	/**
	 * Optional inject for unit tests / record→replay without network.
	 * Signature: (method, url, headers, body, timeoutMs, maxBytes, followRedirect) → resp
	 */
	public static var testLive:Null<(String, String, Dynamic, Null<String>, Int, Int, Bool) -> Dynamic> = null;

	public static function live(
		op:String,
		method:String,
		url:String,
		headers:Dynamic,
		body:Null<String>,
		timeoutMs:Int,
		maxBytes:Int,
		followRedirect:Bool
	):Dynamic {
		if (testLive != null)
			return testLive(method, url, headers, body, timeoutMs, maxBytes, followRedirect);
		#if java
		return liveJava(op, method, url, headers, body, timeoutMs, maxBytes, followRedirect);
		#elseif (js && nodejs)
		return liveNode(op, method, url, headers, body, timeoutMs, maxBytes, followRedirect);
		#else
		throw new IoDenied(op, "HTTP live transport unavailable on this host (use fixture replay)");
		#end
	}

	#if java
	static function liveJava(
		op:String,
		method:String,
		url:String,
		headers:Dynamic,
		body:Null<String>,
		timeoutMs:Int,
		maxBytes:Int,
		followRedirect:Bool
	):Dynamic {
		// Haxe 5 preview: no try/finally — explicit disconnect mirrors former finally.
		var conn:java.net.HttpURLConnection = null;
		var resp:Dynamic = null;
		var denied:IoDenied = null;
		var fail:Dynamic = null;
		try {
			var u = new java.net.URL(url);
			conn = cast u.openConnection();
			conn.setConnectTimeout(timeoutMs);
			conn.setReadTimeout(timeoutMs);
			conn.setInstanceFollowRedirects(followRedirect);
			var m = method == null ? "GET" : method.toUpperCase();
			conn.setRequestMethod(m);
			if (headers != null) {
				for (k in Reflect.fields(headers)) {
					var v = Reflect.field(headers, k);
					if (v != null) conn.setRequestProperty(k, Std.string(v));
				}
			}
			if (body != null && m != "GET" && m != "HEAD") {
				conn.setDoOutput(true);
				var os = conn.getOutputStream();
				var bytes = haxe.io.Bytes.ofString(body);
				os.write(bytes.getData(), 0, bytes.length);
				os.close();
			}
			var code = conn.getResponseCode();
			if (!followRedirect && code >= 300 && code < 400)
				throw new IoDenied(op, 'HTTP redirect refused (status $code)');
			var stream = code >= 400 ? conn.getErrorStream() : conn.getInputStream();
			var text = stream == null ? "" : readStreamLimited(stream, maxBytes, op);
			var hdrs:Dynamic = {};
			var map = conn.getHeaderFields();
			if (map != null) {
				for (key in map.keySet()) {
					if (key == null) continue;
					var vals = map.get(key);
					if (vals != null && vals.size() > 0)
						Reflect.setField(hdrs, Std.string(key).toLowerCase(), Std.string(vals.get(0)));
				}
			}
			resp = { status: code, headers: hdrs, body_text: text, url_final: url };
		} catch (e:IoDenied) {
			denied = e;
		} catch (e:Dynamic) {
			fail = e;
		}
		if (conn != null) conn.disconnect();
		if (denied != null) throw denied;
		if (fail != null) throw new IoDenied(op, "HTTP live failed: " + Std.string(fail));
		return resp;
	}

	static function readStreamLimited(stream:java.io.InputStream, maxBytes:Int, op:String):String {
		var buf = new haxe.io.BytesBuffer();
		var tmp = haxe.io.Bytes.alloc(8192);
		var total = 0;
		while (true) {
			var n = stream.read(tmp.getData());
			if (n < 0) break;
			if (n == 0) continue;
			total += n;
			if (total > maxBytes)
				throw new IoDenied(op, 'HTTP response exceeds max_bytes ($maxBytes)');
			buf.addBytes(tmp, 0, n);
		}
		stream.close();
		return buf.getBytes().toString();
	}
	#end

	#if (js && nodejs)
	static function liveNode(
		op:String,
		method:String,
		url:String,
		headers:Dynamic,
		body:Null<String>,
		timeoutMs:Int,
		maxBytes:Int,
		followRedirect:Bool
	):Dynamic {
		try {
			var hdrObj:Dynamic = headers == null ? {} : headers;
			var payload = haxe.Json.stringify({
				method: method == null ? "GET" : method.toUpperCase(),
				url: url,
				headers: hdrObj,
				body: body,
				timeoutMs: timeoutMs,
				maxBytes: maxBytes,
				followRedirect: followRedirect
			});
			// Sync bridge: worker_threads + Atomics.wait (no extra npm deps).
			var result:Dynamic = untyped js.Syntax.code("
				(function(payloadJson) {
					var wt = require('worker_threads');
					var sab = new SharedArrayBuffer(8);
					var ia = new Int32Array(sab);
					ia[0] = 0;
					var workerSrc = `
						const { workerData, parentPort } = require('worker_threads');
						const { sab, payload } = workerData;
						const ia = new Int32Array(sab);
						(async () => {
							try {
								const ac = new AbortController();
								const t = setTimeout(() => ac.abort(), payload.timeoutMs);
								const init = {
									method: payload.method,
									headers: payload.headers || {},
									redirect: payload.followRedirect ? 'follow' : 'manual',
									signal: ac.signal
								};
								if (payload.body != null && payload.method !== 'GET' && payload.method !== 'HEAD')
									init.body = payload.body;
								const res = await fetch(payload.url, init);
								clearTimeout(t);
								if (!payload.followRedirect && res.status >= 300 && res.status < 400) {
									parentPort.postMessage({ ok: false, error: 'HTTP redirect refused (status ' + res.status + ')' });
									Atomics.store(ia, 0, 2); Atomics.notify(ia, 0); return;
								}
								const text = await res.text();
								if (text.length > payload.maxBytes) {
									parentPort.postMessage({ ok: false, error: 'HTTP response exceeds max_bytes (' + payload.maxBytes + ')' });
									Atomics.store(ia, 0, 2); Atomics.notify(ia, 0); return;
								}
								const headers = {};
								res.headers.forEach((v, k) => { headers[k.toLowerCase()] = v; });
								parentPort.postMessage({
									ok: true,
									status: res.status,
									headers: headers,
									body_text: text,
									url_final: res.url || payload.url
								});
								Atomics.store(ia, 0, 1); Atomics.notify(ia, 0);
							} catch (e) {
								parentPort.postMessage({ ok: false, error: String(e && e.message ? e.message : e) });
								Atomics.store(ia, 0, 2); Atomics.notify(ia, 0);
							}
						})();
					`;
					var w = new wt.Worker(workerSrc, { eval: true, workerData: { sab: sab, payload: JSON.parse(payloadJson) } });
					var msg = null;
					w.on('message', function(m) { msg = m; });
					var parsed = JSON.parse(payloadJson);
					var wait = Atomics.wait(ia, 0, 0, Math.max(1000, (parsed.timeoutMs || 10000) + 2000));
					try { w.terminate(); } catch (_) {}
					if (msg == null)
						return JSON.stringify({ ok: false, error: 'HTTP live timeout/sync wait failed (' + wait + ')' });
					return JSON.stringify(msg);
				})({0})
			", payload);
			var parsed:Dynamic = haxe.Json.parse(Std.string(result));
			if (parsed.ok != true)
				throw new IoDenied(op, "HTTP live failed: " + Std.string(Reflect.field(parsed, "error")));
			return {
				status: Std.int(parsed.status),
				headers: parsed.headers,
				body_text: parsed.body_text == null ? "" : Std.string(parsed.body_text),
				url_final: parsed.url_final == null ? url : Std.string(parsed.url_final)
			};
		} catch (e:IoDenied) {
			throw e;
		} catch (e:Dynamic) {
			throw new IoDenied(op, "HTTP live failed: " + Std.string(e));
		}
	}
	#end
}

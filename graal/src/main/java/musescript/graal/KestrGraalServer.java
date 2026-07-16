package musescript.graal;

import io.grpc.Server;
import io.grpc.netty.shaded.io.grpc.netty.NettyServerBuilder;
import io.grpc.stub.StreamObserver;

import java.net.InetSocketAddress;
import org.graalvm.polyglot.Context;
import org.graalvm.polyglot.Engine;
import org.graalvm.polyglot.Source;
import org.graalvm.polyglot.Value;
import org.graalvm.polyglot.io.ByteSequence;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.logging.Logger;

import musescript.graal.MuseBacktestCore.Bar;
import musescript.graal.MuseBacktestCore.BacktestResult;
import musescript.graal.proto.BacktestReply;
import musescript.graal.proto.BacktestRequest;
import musescript.graal.proto.KestrGraalGrpc;
import musescript.graal.proto.PingReply;
import musescript.graal.proto.PingRequest;

/**
 * KestrGraal — the bound GraalVM polyglot process (MUSE_APP_INTEGRATION_PLAN.md / the merged
 * execution plan, Phase 1 addendum). Grows MuseGraalStress.java's one-shot stress harness into a
 * persistent gRPC server: one Engine for the process lifetime (shares warmed ASTs/compiled code
 * across every call, per GraalVM's own Engine-sharing guidance), one Context per worker thread
 * (WASM Values are Context-bound — can't share across threads even with a shared Engine), and a
 * per-Context module cache keyed by wasm_path so repeat calls against the same artifact skip
 * re-eval entirely.
 *
 * Bound to loopback only (127.0.0.1) — this is a desktop-local process, never exposed on the
 * network.
 */
public final class KestrGraalServer extends KestrGraalGrpc.KestrGraalImplBase {
    private static final Logger LOG = Logger.getLogger(KestrGraalServer.class.getName());
    private static final long START_NANOS = System.nanoTime();

    private final Engine engine;
    private final Path root;

    // Per-thread Context + per-Context module cache (Value/Context are not thread-safe or
    // shareable across threads; the shared Engine is what actually carries the warmup benefit).
    private final ThreadLocal<Context> contexts;
    private final ThreadLocal<Map<String, Value>> moduleCacheTL = ThreadLocal.withInitial(ConcurrentHashMap::new);
    private final ThreadLocal<Map<String, List<String>>> stringsCacheTL = ThreadLocal.withInitial(ConcurrentHashMap::new);
    private final ThreadLocal<Map<String, List<Bar>>> csvCacheTL = ThreadLocal.withInitial(ConcurrentHashMap::new);

    public KestrGraalServer(Engine engine, Path root) {
        this.engine = engine;
        this.root = root;
        this.contexts = ThreadLocal.withInitial(() -> Context.newBuilder("wasm").engine(engine).build());
    }

    @Override
    public void ping(PingRequest request, StreamObserver<PingReply> responseObserver) {
        long uptimeMs = (System.nanoTime() - START_NANOS) / 1_000_000L;
        responseObserver.onNext(PingReply.newBuilder()
            .setJvmName(System.getProperty("java.vm.name"))
            .setJvmVersion(System.getProperty("java.vm.version"))
            .setUptimeMs(uptimeMs)
            .build());
        responseObserver.onCompleted();
    }

    @Override
    public void backtest(BacktestRequest request, StreamObserver<BacktestReply> responseObserver) {
        try {
            long t0 = System.nanoTime();
            Context ctx = contexts.get();
            Map<String, Value> moduleCache = moduleCacheTL.get();
            Map<String, List<String>> stringsCache = stringsCacheTL.get();
            Map<String, List<Bar>> csvCache = csvCacheTL.get();

            String wasmPath = request.getWasmPath();
            Value module = moduleCache.computeIfAbsent(wasmPath, p -> {
                try {
                    byte[] bytes = Files.readAllBytes(resolve(p));
                    return ctx.eval(Source.newBuilder("wasm", ByteSequence.create(bytes), "on_bar").build());
                } catch (Exception e) {
                    throw new RuntimeException("failed to load wasm module " + p, e);
                }
            });

            List<String> strings = stringsCache.computeIfAbsent(request.getStringsPath(), p -> {
                try {
                    return MuseBacktestCore.loadStrings(resolve(p));
                } catch (Exception e) {
                    throw new RuntimeException("failed to load strings " + p, e);
                }
            });

            List<Bar> bars = csvCache.computeIfAbsent(request.getCsvPath(), p -> {
                try {
                    return MuseBacktestCore.loadCsv(resolve(p));
                } catch (Exception e) {
                    throw new RuntimeException("failed to load csv " + p, e);
                }
            });

            BacktestResult result = request.getPreloaded()
                ? MuseBacktestCore.runPreloaded(module, strings, bars, request.getParamsMap())
                : MuseBacktestCore.runStreaming(module, strings, bars, request.getParamsMap());

            double elapsedMs = (System.nanoTime() - t0) / 1_000_000.0;
            responseObserver.onNext(BacktestReply.newBuilder()
                .setTrades(result.trades())
                .setFinalEquity(result.finalEquity())
                .setSharpe(result.sharpe())
                .setElapsedMs(elapsedMs)
                .build());
            responseObserver.onCompleted();
        } catch (Exception e) {
            responseObserver.onError(io.grpc.Status.INTERNAL
                .withDescription(e.toString())
                .asRuntimeException());
        }
    }

    private Path resolve(String p) {
        Path candidate = Path.of(p);
        return candidate.isAbsolute() ? candidate : root.resolve(candidate);
    }

    public static void main(String[] argv) throws Exception {
        int port = argv.length > 0 ? Integer.parseInt(argv[0]) : 51117;
        Path root = Path.of(argv.length > 1 ? argv[1] : "..").toAbsolutePath().normalize();

        Engine engine = Engine.newBuilder("wasm").build();
        ExecutorService pool = Executors.newFixedThreadPool(
            Math.max(2, Runtime.getRuntime().availableProcessors()));

        // Loopback only — see class javadoc. ServerBuilder.forPort(port) binds all interfaces
        // (0.0.0.0); NettyServerBuilder.forAddress with an explicit InetSocketAddress is what
        // actually restricts the listen socket to 127.0.0.1.
        Server server = NettyServerBuilder.forAddress(new InetSocketAddress("127.0.0.1", port))
            .addService(new KestrGraalServer(engine, root))
            .executor(pool)
            .build();

        LOG.info("KestrGraal starting on 127.0.0.1:" + port + "  root=" + root);
        server.start();
        LOG.info("KestrGraal ready.");

        Runtime.getRuntime().addShutdownHook(new Thread(() -> {
            LOG.info("KestrGraal shutting down...");
            server.shutdown();
            engine.close();
        }));

        server.awaitTermination();
    }
}

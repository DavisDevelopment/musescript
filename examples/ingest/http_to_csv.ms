# Muse ingest — HTTP → sandbox CSV → offline run
#
# Record (dev):
#   node build/js/gene-runner.js --ingest --source examples/ingest/http_to_csv.ms \
#     --fs-root ./build/tmp/ingest-sandbox --fixture-dir ./build/tmp/ingest-fixtures \
#     --http record --allow-hosts api.example.com
#
# Replay (CI / PIT):
#   node build/js/gene-runner.js --ingest --source examples/ingest/http_to_csv.ms \
#     --fs-root ./build/tmp/ingest-sandbox --fixture-dir ./build/tmp/ingest-fixtures \
#     --http replay --allow-hosts api.example.com
#
# Then offline fitness (grants null):
#   node build/js/gene-runner.js --source examples/ingest/smoke_strategy.ms \
#     --tape ./build/tmp/ingest-sandbox/tapes/DEMO.csv
#
# Docs: docs/MUSE_IO.md § Ingest program kind
# Note: no @on(bar) — ingest refuses bar handlers; prelude/body runs once.

{
  @strategy("http_to_csv")
  {
    var resp = muse.http.get("https://api.example.com/ohlcv.csv");
    muse.fs.mkdir("tapes", true);
    muse.fs.write_text("tapes/DEMO.csv", resp.body_text);
    var df = muse.pd.read_csv("tapes/DEMO.csv");
    log("ingest_ok");
  }
}

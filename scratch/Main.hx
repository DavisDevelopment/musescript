class Main {
  static function main() {
    tryMatch(T.A(1));
    tryMatch(T.A(1, null));
    tryMatch(T.A(1, 2));
  }
  static function tryMatch(v:T) {
    switch (v) {
      case A(x): trace("1arg " + x);
      // only 1-arg case - does 2-arg crash?
    }
  }
}
enum T { A(x:Int, ?y:Int); }

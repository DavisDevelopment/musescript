package musescript.scratch;
class FlagDump {
  static function main() {
    #if jvm Sys.println("jvm=1"); #else Sys.println("jvm=0"); #end
    #if java Sys.println("java=1"); #else Sys.println("java=0"); #end
  }
}

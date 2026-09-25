/// POSIX-ish argument splitting / quoting — used by the CLI tool and for
/// showing copyable commands. Execution never goes through a shell.
abstract final class ShellWords {
  /// Splits `-i "my file.mp4" -vf 'scale=1280:-2'` into argv.
  /// Throws [FormatException] on an unterminated quote.
  static List<String> split(String input) {
    final args = <String>[];
    final current = StringBuffer();
    var inArg = false;
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final c = input[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        } else if (c == r'\' && quote == '"' && i + 1 < input.length && (input[i + 1] == '"' || input[i + 1] == r'\')) {
          current.write(input[++i]);
        } else {
          current.write(c);
        }
      } else if (c == '"' || c == "'") {
        quote = c;
        inArg = true;
      } else if (c == r'\' && i + 1 < input.length) {
        current.write(input[++i]);
        inArg = true;
      } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        if (inArg) {
          args.add(current.toString());
          current.clear();
          inArg = false;
        }
      } else {
        current.write(c);
        inArg = true;
      }
    }
    if (quote != null) throw FormatException('Unterminated $quote quote');
    if (inArg) args.add(current.toString());
    return args;
  }

  static final _safe = RegExp(r'^[A-Za-z0-9_\-+=:,./@%]+$');

  static String quote(String arg) {
    if (arg.isEmpty) return "''";
    if (_safe.hasMatch(arg)) return arg;
    return "'${arg.replaceAll("'", r"'\''")}'";
  }

  static String join(Iterable<String> args) => args.map(quote).join(' ');
}

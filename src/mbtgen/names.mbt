// Translation of ATD names into valid, non-conflicting MoonBit names.

///|
/// MoonBit keywords and reserved words, which can't be used as identifiers
/// (or trigger warnings).
let mbt_keywords : Array[String] = [
  "and", "as", "async", "await", "break", "catch", "const", "continue", "declare",
  "defer", "derive", "else", "enum", "enumview", "extend", "extern", "false", "fn",
  "fnalias", "for", "guard", "if", "impl", "import", "in", "init", "is", "let", "letrec",
  "lexmatch", "loop", "main", "match", "mut", "noraise", "nobreak", "priv", "pub",
  "raise", "readonly", "return", "struct", "suberror", "test", "throw", "trait",
  "traitalias", "true", "try", "type", "typealias", "using", "where", "while", "with",
  "abstract", "alias", "assert", "do", "dyn", "final", "macro", "method", "module",
  "move", "override", "package", "private", "protected", "recur", "ref", "self",
  "static", "super", "typeof", "unsafe", "use", "virtual", "yield", "local", "sealed",
  "open", "object", "include", "exception", "mutable", "val", "var",
]

///|
/// Names of builtin MoonBit types and traits, which shouldn't be used as
/// names of generated types.
let mbt_reserved_type_names : Array[String] = [
  "Array", "ArrayView", "BigInt", "Bool", "Buffer", "Byte", "Bytes", "BytesView",
  "Char", "Compare", "Debug", "Default", "Double", "Eq", "Error", "Failure", "FixedArray",
  "Float", "FromJson", "Hash", "Hasher", "Int", "Int16", "Int64", "Iter", "Iter2",
  "Json", "JsonError", "Lazy", "Logger", "Map", "Option", "Path", "ReadOnlyArray",
  "Ref", "Result", "Self", "Set", "Show", "SourceLoc", "String", "StringBuilder",
  "StringView", "ToJson", "UInt", "UInt16", "UInt64", "Unit", "ArgsLoc", "InspectError",
  "SnapshotError",
]

///|
/// Constructors of builtin types that user-defined constructors shouldn't
/// shadow.
let mbt_reserved_constructors : Array[String] = [
  "Some", "None", "Ok", "Err", "Null", "True", "False", "Number", "Object",
]

///|
/// Replace characters that can't occur in MoonBit identifiers.
fn sanitize(s : String) -> String {
  let buf = StringBuilder()
  for c in s {
    if c == '\'' {
      buf.write_char('_')
    } else {
      buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
/// Convert an identifier to CamelCase, getting rid of underscores.
fn to_camel_case(s : String) -> String {
  let buf = StringBuilder()
  let mut start_word = true
  for c in s {
    if c == '_' || c == '\'' {
      start_word = true
    } else if start_word && c >= 'a' && c <= 'z' {
      buf.write_char((c.to_int() - 32).unsafe_to_char())
      start_word = false
    } else {
      buf.write_char(c)
      start_word = false
    }
  }
  let res = buf.to_string()
  if res == "" {
    "X"
  } else if res[0] >= '0' && res[0] <= '9' {
    "X" + res
  } else {
    res
  }
}

///|
/// Escape a string as a MoonBit string literal.
fn mbt_string_literal(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\b' => buf.write_string("\\b")
      c if c.to_int() < 0x20 => {
        let hex = "0123456789abcdef"
        buf.write_string("\\u{")
        buf.write_char(hex[c.to_int() >> 4].unsafe_to_char())
        buf.write_char(hex[c.to_int() & 0xF].unsafe_to_char())
        buf.write_string("}")
      }
      c => buf.write_char(c)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// A fresh registry for names of fields or constructors.
fn member_names(reserved : Array[String]) -> @atd.UniqueNames {
  @atd.UniqueNames::new(
    reserved_identifiers=reserved,
    reserved_prefixes=[],
    safe_prefix="",
  )
}

///|
fn is_ident_char(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') ||
  (c >= 'A' && c <= 'Z') ||
  (c >= '0' && c <= '9') ||
  c == '_'
}

///|
/// A valid name for a value or a field: `[a-z_][A-Za-z0-9_]*`.
fn is_lowercase_ident(s : String) -> Bool {
  s != "" &&
  s.iter().all(is_ident_char) &&
  ((s[0] >= 'a' && s[0] <= 'z') || s[0] == '_')
}

///|
/// A valid name for a type or a constructor: `[A-Z][A-Za-z0-9_]*`.
fn is_uppercase_ident(s : String) -> Bool {
  s != "" && s.iter().all(is_ident_char) && s[0] >= 'A' && s[0] <= 'Z'
}

///|
fn check_type_name(loc : @atd.Loc, n : String) -> String raise @atd.AtdError {
  if !is_uppercase_ident(n) {
    @atd.error_at(loc, "invalid MoonBit type name \{mbt_string_literal(n)}")
  }
  n
}

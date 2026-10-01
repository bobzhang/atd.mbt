///|
fn format_error(fmt : String) -> String {
  let p : FormatParser = { str: fmt, }
  try {
    ignore(p.parse(0, fmt.length()))
    "no error"
  } catch {
    FormatError(msg) => msg
  }
}

///|
test "errors in format strings" {
  // the messages are OCaml's
  inspect(
    format_error("%5.3"),
    content=(
      #|invalid format "%5.3": at character number 4, unexpected end of format
    ),
  )
  inspect(
    format_error("%z"),
    content=(
      #|invalid format "%z": at character number 1, invalid conversion "%z"
    ),
  )
  inspect(
    format_error("%-+ #*c"),
    content=(
      #|invalid format "%-+ #*c": at character number 0, '*' is incompatible with 'c' in sub-format "%-+ #*c"
    ),
  )
  inspect(
    format_error("%{%d%)"),
    content=(
      #|invalid format "%{%d%)": at character number 5, character '}' expected, read ')'
    ),
  )
  // like in OCaml, positions count the bytes of the UTF-8 encoding
  inspect(
    format_error("%{é%d"),
    content=(
      #|invalid format "%{\195\169%d": unclosed sub-format, expected "%}" at character number 6
    ),
  )
  inspect(format_error("@[<hov 2>%d@]"), content="no error")
}

///|
/// Error raised by the functions of the ATD library.
/// It corresponds to both `Ast.Atd_error` and `Failure` in the OCaml
/// implementation; the payload is the complete error message.
pub(all) suberror AtdError {
  AtdError(String)
} derive(Debug, Eq)

///|
/// Return the error message.
pub fn AtdError::message(self : AtdError) -> String {
  match self {
    AtdError(msg) => msg
  }
}

///|
pub impl Show for AtdError with fn output(self, logger) {
  logger.write_string(self.message())
}

///|
/// `error(s)` raises `AtdError(s)`.
pub fn[T] error(msg : String) -> T raise AtdError {
  raise AtdError(msg)
}

///|
/// `error_at(loc, s)` raises an error whose message is the location
/// followed by `s`.
pub fn[T] error_at(loc : Loc, msg : String) -> T raise AtdError {
  raise AtdError(string_of_loc(loc) + ":\n" + msg)
}

///|
extern "c" fn read_all_stdin_ffi() -> Bytes = "atd_read_all_stdin"

///|
/// Read all of standard input.
pub fn read_all() -> Bytes {
  read_all_stdin_ffi()
}

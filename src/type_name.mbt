///|
/// A possibly qualified type name.
///
/// The simple ATD type name `a` is represented as `TN(["a"])`.
/// The composite ATD type name `a.b.c` is represented as `TN(["a", "b", "c"])`.
/// The list of path components may not be empty. Two components indicate a
/// type provided by an external module.
pub(all) struct TypeName {
  path : Array[String]
} derive(Eq, Hash, Debug)

///|
/// Build a type name from its path components.
pub fn TypeName::new(path : Array[String]) -> TypeName {
  { path, }
}

///|
/// Build an unqualified type name.
pub fn TypeName::simple(name : String) -> TypeName {
  { path: [name], }
}

///|
/// Total order on type names, same as OCaml's polymorphic comparison.
pub impl Compare for TypeName with fn compare(a, b) {
  compare_string_lists(a.path, b.path)
}

///|
/// Format to a string in ATD syntax. For example, `TN(["a", "b"])` gives
/// `a.b`.
pub fn TypeName::to_string(self : TypeName) -> String {
  self.path.join(".")
}

///|
pub impl Show for TypeName with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Return the base name, i.e. the last component in the path.
pub fn TypeName::basename(self : TypeName) -> String {
  match self.path.last() {
    Some(x) => x
    None => abort("TypeName::basename: empty name")
  }
}

///|
/// Test whether the type name is the unqualified name `name`.
pub fn TypeName::is_simple(self : TypeName, name : String) -> Bool {
  self.path is [n] && n == name
}

///|
/// Return the module name if any, and the base name.
pub fn TypeName::split(self : TypeName) -> (String?, String) raise AtdError {
  match self.path {
    [base_name] => (None, base_name)
    [local_module_name, base_name] => (Some(local_module_name), base_name)
    [] => error("Type_name.split: empty name")
    _ =>
      error("Type_name.split: more than two components in " + self.to_string())
  }
}

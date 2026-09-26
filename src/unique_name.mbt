// Ensure unique identifiers that don't conflict with predefined
// identifiers or reserved prefixes.

///|
/// A registry of unique names.
pub struct UniqueNames {
  reserved_identifiers : Map[String, Unit]
  reserved_prefixes : Array[String]
  safe_prefix : String
  translations : Map[String, String]
  reverse_translations : Map[String, String]
}

///|
/// Create a registry.
pub fn UniqueNames::new(
  reserved_identifiers~ : Array[String],
  reserved_prefixes~ : Array[String],
  safe_prefix~ : String,
) -> UniqueNames {
  let tbl : Map[String, Unit] = Map([])
  for id in reserved_identifiers {
    tbl[id] = ()
  }
  for prefix in reserved_prefixes {
    if safe_prefix.has_prefix(prefix) {
      abort(
        "Unique_name.init: safe_prefix \{ocaml_quote(safe_prefix)} is not safe as it conflicts with reserved prefix \{ocaml_quote(prefix)}",
      )
    }
  }
  {
    reserved_identifiers: tbl,
    reserved_prefixes,
    safe_prefix,
    translations: Map([]),
    reverse_translations: Map([]),
  }
}

///|
fn UniqueNames::is_reserved(self : UniqueNames, s : String) -> Bool {
  self.reserved_identifiers.contains(s)
}

///|
fn UniqueNames::has_reserved_prefix(self : UniqueNames, s : String) -> Bool {
  self.reserved_prefixes.iter().any(p => s.has_prefix(p))
}

///|
fn suffix_of_int(n : Int) -> String {
  match n {
    0 => ""
    1 => "_"
    n => n.to_string()
  }
}

///|
fn UniqueNames::register(
  self : UniqueNames,
  src : String,
  preferred_translation? : String,
) -> String {
  let pref_dst = preferred_translation.unwrap_or(src)
  let mut counter = 0
  let dst = for ;; {
    let suffix = suffix_of_int(counter)
    counter += 1
    let dst = pref_dst + suffix
    let dst = if self.has_reserved_prefix(dst) {
      self.safe_prefix + dst
    } else {
      dst
    }
    if !(self.is_reserved(dst) || self.reverse_translations.contains(dst)) {
      break dst
    }
  }
  self.translations[src] = dst
  self.reverse_translations[dst] = src
  dst
}

///|
/// Look up the translation of a registered identifier.
pub fn UniqueNames::translate_only(self : UniqueNames, src : String) -> String? {
  self.translations.get(src)
}

///|
/// Translate an identifier, registering it if needed.
pub fn UniqueNames::translate(
  self : UniqueNames,
  src : String,
  preferred_translation? : String,
) -> String {
  match self.translate_only(src) {
    Some(dst) => dst
    None => self.register(src, preferred_translation?)
  }
}

///|
/// Look up the source identifier of a translation.
pub fn UniqueNames::reverse_translate(
  self : UniqueNames,
  dst : String,
) -> String? {
  self.reverse_translations.get(dst)
}

///|
/// Create a new unique source identifier based on `src` and register it.
pub fn UniqueNames::create(self : UniqueNames, src : String) -> String {
  let mut counter = 0
  let src = for ;; {
    let s = src + suffix_of_int(counter)
    counter += 1
    if !self.translations.contains(s) {
      break s
    }
  }
  ignore(self.register(src))
  src
}

///|
/// All the translations, sorted by source identifier.
pub fn UniqueNames::all(self : UniqueNames) -> Array[(String, String)] {
  let l = self.translations.iter().collect()
  l.sort_by((a, b) => compare_strings(a.0, b.0))
  l
}

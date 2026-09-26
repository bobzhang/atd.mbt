///|
/// A user-defined type used through `<mbt t="Celsius" ...>`.
pub(all) struct Celsius(Double) derive(Eq, Debug)

///|
pub fn Celsius::from_double(x : Double) -> Celsius {
  Celsius(x)
}

///|
pub fn Celsius::to_double(self : Celsius) -> Double {
  self.0
}

///|
pub extend Celsius with Eq::{equal, not_equal}

///|
pub extend Celsius with Debug::{to_repr}

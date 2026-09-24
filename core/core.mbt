///|
/// HTTP methods supported by the static engine.
pub(all) enum Method {
  Get
  Head
  Other(String)
} derive(Eq, Debug)

///|
/// A parsed HTTP request used by the static engine.
pub(all) struct Request {
  meth : Method
  target : String
  headers : Map[String, String]
}

///|
/// Representation of an HTTP response body.
pub(all) enum ResponseBody {
  Empty
  Bytes(Bytes)
  FileRegion(String, Int64, Int64)
} derive(Eq, Debug)

///|
/// Return the total byte length of the response body.
pub fn ResponseBody::length(self : ResponseBody) -> Int {
  match self {
    Empty => 0
    Bytes(b) => b.length()
    FileRegion(_, _, length) => length.to_int()
  }
}


///|
pub extend Method with Eq::{not_equal, equal}

///|
pub extend Method with Debug::{to_repr}

///|
pub extend ResponseBody with Eq::{not_equal, equal}

///|
pub extend ResponseBody with Debug::{to_repr}

///|
#external
priv type Operation

///|
#external
priv type NativeResponse

///|
pub extern "C" fn register(entry : FuncRef[() -> Unit]) = "hs_bridge_register"

///|
extern "C" fn attach(fd : @types.Fd) = "hs_bridge_attach"

///|
extern "C" fn ack() = "hs_bridge_ack"

///|
extern "C" fn pop() -> Operation = "hs_bridge_pop"

///|
extern "C" fn is_null(op : Operation) -> Bool = "hs_bridge_null"

///|
extern "C" fn response_null(r : NativeResponse) -> Bool = "hs_bridge_null"

///|
extern "C" fn idle() -> Bool = "hs_bridge_idle"

///|
extern "C" fn kind(op : Operation) -> Int = "hs_bridge_kind"

///|
extern "C" fn id(op : Operation) -> Int = "hs_bridge_id"

///|
extern "C" fn instance(op : Operation) -> Int = "hs_bridge_instance"

///|
extern "C" fn response_id(op : Operation) -> Int = "hs_bridge_response_id"

///|
extern "C" fn max_bytes(op : Operation) -> Int = "hs_bridge_max_bytes"

///|
extern "C" fn read_ready(op : Operation) -> Bool = "hs_bridge_read_ready"

///|
extern "C" fn cancelled(op : Operation) -> Bool = "hs_bridge_cancelled"

///|
extern "C" fn active(op : Operation) -> Int = "hs_bridge_active"

///|
extern "C" fn input(op : Operation, field : Int, index : Int) -> Bytes = "hs_bridge_input"

///|
extern "C" fn header_count(op : Operation) -> Int = "hs_bridge_header_count"

///|
extern "C" fn limits(
  op : Operation,
  capacity : Int,
  block : Int,
  budget : Int,
  responses : Int,
) = "hs_bridge_limits"

///|
extern "C" fn make_response(
  op : Operation,
  id : Int,
  status : Int,
  length : Int64,
  count : Int,
) -> NativeResponse = "hs_bridge_response"

///|
#borrow(key, value)
extern "C" fn set_header(
  r : NativeResponse,
  index : Int,
  key : Bytes,
  value : Bytes,
) -> Bool = "hs_bridge_set_header"

///|
#borrow(bytes)
extern "C" fn chunk(op : Operation, bytes : Bytes) -> Int = "hs_bridge_chunk"

///|
extern "C" fn complete(op : Operation, code : Int, result_kind : Int) = "hs_bridge_complete"

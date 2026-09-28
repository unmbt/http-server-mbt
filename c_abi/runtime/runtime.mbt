///|
priv suberror Closed

///|
priv struct ServerScope {
  wake : @async.CondVar
  mut stopping : Bool
  mut done : Bool
}

///|
priv struct Context {
  engines : Map[Int, @engine.StaticEngine]
  responses : Map[Int, (Int, @engine.Response)]
  servers : Map[Int, ServerScope]
  tasks : Map[Int, (Operation, @async.Task[Unit])]
  changed : @async.CondVar
  mut response_serial : Int
}

///|
fn error_code(e : Error, creating : Bool) -> Int {
  if @async.is_cancellation_error(e) {
    return 8
  }
  match e {
    Unsupported => 5
    Closed => 4
    @engine.ServerError::FileChanged(_) => 9
    @engine.ServerError::Closed => 4
    @engine.ServerError::Busy => 11
    @engine.ServerError::Overloaded => 10
    @engine.ServerError::InvalidRequest(_) => 2
    _ => if creating { 1 } else { 3 }
  }
}

///|
async fn Context::execute(
  self : Context,
  op : Operation,
  thin : Bool,
  serve : async (@core.Config, async (Int) -> Unit) -> Unit,
) -> Unit {
  let key = id(op)
  let owner = instance(op)
  let command = kind(op)
  let mut finished = false
  defer {
    self.tasks.remove(key)
    self.changed.broadcast()
  }
  try {
    if command <= 4 && cancelled(op) {
      complete(op, 8, 0)
      finished = true
      return
    }
    match command {
      1 => {
        let config = decode_config(op, thin, false)
        let engine = @engine.StaticEngine::open(config)
        if cancelled(op) {
          engine.close()
          complete(op, 8, 0)
        } else {
          self.engines[owner] = engine
          complete(op, 0, 1)
        }
        finished = true
      }
      2 => {
        let config = decode_config(op, thin, true)
        let scope = {
          wake: @async.CondVar::Cond(),
          stopping: false,
          done: false,
        }
        self.servers[owner] = scope
        defer {
          scope.done = true
          scope.wake.broadcast()
          self.servers.remove(owner)
        }
        serve(config, async fn(_port) {
          self.tasks.remove(key)
          finished = true
          complete(op, 0, 2)
          while !scope.stopping {
            scope.wake.wait()
          }
        })
      }
      3 => {
        let request = decode_request(op)
        guard self.engines.get(owner) is Some(engine) else { raise Closed }
        match engine.handle(request) {
          Next => complete(op, 0, 4)
          Error(e) => complete(op, error_code(e, false), 0)
          Handled(response) => {
            let serial = self.response_serial
            self.response_serial += 1
            self.responses[serial] = (owner, response)
            let raw = make_response(
              op,
              serial,
              response.status,
              response.body_length(),
              response.headers.length(),
            )
            if response_null(raw) {
              response.close()
              self.responses.remove(serial)
              complete(op, 10, 0)
            } else {
              let mut n = 0
              let mut valid = true
              for name, value in response.headers {
                if !set_header(raw, n, @utf8.encode(name), @utf8.encode(value)) {
                  valid = false
                }
                n += 1
              }
              if !valid {
                response.close()
                self.responses.remove(serial)
                complete(op, 10, 0)
              } else {
                complete(op, 0, -1)
              }
            }
          }
        }
        finished = true
      }
      4 => {
        guard self.responses.get(response_id(op)) is Some((_, response)) else {
          raise Closed
        }
        while !read_ready(op) {
          self.changed.wait()
        }
        let bytes = response.read(max_len=max_bytes(op))
        if bytes.is_empty() {
          complete(op, 0, 6)
        } else {
          let code = chunk(op, bytes)
          complete(op, code, if code == 0 { -1 } else { 0 })
        }
        finished = true
      }
      5 | 6 => {
        for _, (other, task) in self.tasks {
          if instance(other) == owner && id(other) != key {
            task.cancel()
          }
        }
        if self.servers.get(owner) is Some(scope) {
          scope.stopping = true
          scope.wake.broadcast()
          while !scope.done {
            scope.wake.wait()
          }
        }
        if self.engines.get(owner) is Some(engine) {
          engine.close()
          self.engines.remove(owner)
        }
        while active(op) > 1 {
          self.changed.wait()
        }
        for (serial, (belongs, response)) in self.responses.to_array() {
          if belongs == owner {
            response.close()
            self.responses.remove(serial)
          }
        }
        complete(op, 0, 0)
        finished = true
      }
      7 => {
        let serial = response_id(op)
        if self.responses.get(serial) is Some((_, response)) {
          response.close()
          self.responses.remove(serial)
        }
        complete(op, 0, 0)
        finished = true
      }
      _ => {
        complete(op, 2, 0)
        finished = true
      }
    }
  } catch {
    e => if !finished { complete(op, error_code(e, command <= 2), 0) }
  }
}

///|
pub fn run(
  thin : Bool,
  serve : async (@core.Config, async (Int) -> Unit) -> Unit,
) -> Unit {
  @async.run_async_main(async fn() {
    try {
      let (reader, writer) = @pipe.pipe()
      defer reader.close()
      defer writer.close()
      attach(writer.fd())
      let context : Context = {
        engines: Map([]),
        responses: Map([]),
        servers: Map([]),
        tasks: Map([]),
        changed: @async.CondVar::Cond(),
        response_serial: 1,
      }
      @async.with_task_group(async fn(group) {
        while true {
          ignore(reader.read_exactly(1))
          ack()
          context.changed.broadcast()
          while true {
            let op = pop()
            if is_null(op) {
              break
            }
            let key = id(op)
            let task = group.spawn(async fn() {
              context.execute(op, thin, serve)
            })
            context.tasks[key] = (op, task)
          }
          for _, (op, task) in context.tasks {
            if kind(op) <= 4 && cancelled(op) {
              task.cancel()
            }
          }
          if idle() {
            break
          }
        }
      })
    } catch {
      _ => ()
    }
  })
}

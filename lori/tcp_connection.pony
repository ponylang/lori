interface tag TCPConnectionActor
  fun ref self(): TCPConnection
  
  fun ref on_connected()

  be open() =>
    // would like to make this a `fun` be then, how does a listener trigger it?
    let event = PonyASIO.create_event(this, self().fd)
    self().event = event
    // should set connected state
    // should set writable state
    // should set readable state
    PonyASIO.set_writeable(self().event)
    on_connected()   

  fun ref send(data: ByteSeq) =>
    // check connection is open
    PonyTCP.send(self().event, data, data.size())
 
  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    None


class TCPConnection
  let fd: U32
  var event: AsioEventID = AsioEvent.none()

  new create(fd': U32) =>
    fd = fd'

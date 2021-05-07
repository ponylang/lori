use @fprintf[I32](stream: Pointer[U8] tag, fmt: Pointer[U8] tag, ...)
use @pony_os_stderr[Pointer[U8]]()
use @exit[None](status: U8)

primitive FatalUserError
  """
  An error was encountered due to bad input from the user in terms of startup
  options or configuration. Exit and inform them of the problem.
  """
  fun apply(msg: String) =>
    @fprintf(@pony_os_stderr(), "Error: %s\n".cstring(), msg.cstring())
    @exit(1)


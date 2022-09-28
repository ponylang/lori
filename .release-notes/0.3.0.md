## Update object capabilities to match Pony standard library pattern

In [Pony version 0.49.0](https://github.com/ponylang/ponyc/releases/tag/0.49.0), the pattern for how object capabilities were implemented was changed. Lori's usage of object capabilities has been updated to match the pattern used in the standard library.

Note, this is a breaking changes and might require you to change your code that involves object capability authorization usage. Only a single "most specific" authorization is now allowed at call sites so previously where you could have been using `AmbientAuth` directly to authorization an action like creating a `TCPListener`:

```pony
TCPListener(env.root, host, port, enclosing_actor)
```

You'll now have to use the most specific authorization for the object:

```pony
TCPListener(TCPListenAuth(env.root), host, port, enclosing_actor)
```


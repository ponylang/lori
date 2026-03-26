## Fix crash when dispose() arrives before connection initialization

Calling `dispose()` on a connection actor before its internal initialization completed would crash with an unreachable state error. This could happen because `_finish_initialization` is a self-to-self message queued during the actor's constructor, while `dispose()` arrives from an external actor — and Pony's causal messaging provides no ordering guarantee between different senders. The race is unlikely but was observed on macOS arm64 CI.

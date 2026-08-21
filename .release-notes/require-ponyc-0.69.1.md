## Require ponyc 0.69.1 or later

lori now requires ponyc 0.69.1 or later, up from 0.67.0. lori's TCP connection and listener types are generic with a default backend type argument, and ponyc before 0.69.1 cannot resolve that default when lori is imported under an alias — `use lori = "lori"` — so a program that imports lori that way fails to compile. ponyc 0.69.1 resolves it.

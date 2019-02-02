# Lori

Pony TCP classes reimagined.

## Status

[![CircleCI](https://circleci.com/gh/SeanTAllen/lori.svg?style=svg)](https://circleci.com/gh/seantallen/lori)

This is an experimental project and shouldn't be used in a production environment.

## Installation

* Install [pony-stable](https://github.com/ponylang/pony-stable)
* Update your `bundle.json`

```json
{ 
  "type": "github",
  "repo": "seantallen/lori"
}
```

* `stable fetch` to fetch your dependencies
* `use "lori"` to include this package
* `stable env ponyc` to compile your application

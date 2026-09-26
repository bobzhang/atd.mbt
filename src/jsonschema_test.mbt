///|
test "jsonschema: inheritance is expanded" {
  let m = @atd.load_string(
    "type base = { x : int }\ntype t = { inherit base; y : string }",
  )
  inspect(
    @atd.print_jsonschema(m, src_name="t.atd", root_type="t"),
    content=(
      #|{
      #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
      #|  "title": "t",
      #|  "description": "Translated by atdcat from t.atd.",
      #|  "type": "object",
      #|  "required": [ "x", "y" ],
      #|  "properties": { "x": { "type": "integer" }, "y": { "type": "string" } },
      #|  "definitions": {
      #|    "base": {
      #|      "type": "object",
      #|      "required": [ "x" ],
      #|      "properties": { "x": { "type": "integer" } }
      #|    }
      #|  }
      #|}
      #|
    ),
  )
}

///|
test "jsonschema: duplicate JSON names are preserved, like upstream" {
  let m = @atd.load_string(
    "type root = { a <json name=\"x\"> : int; b <json name=\"x\"> : string }",
  )
  inspect(
    @atd.print_jsonschema(m, src_name="t.atd", root_type="root"),
    content=(
      #|{
      #|  "$schema": "https://json-schema.org/draft/2020-12/schema",
      #|  "title": "root",
      #|  "description": "Translated by atdcat from t.atd.",
      #|  "type": "object",
      #|  "required": [ "x", "x" ],
      #|  "properties": { "x": { "type": "integer" }, "x": { "type": "string" } },
      #|  "definitions": {}
      #|}
      #|
    ),
  )
}

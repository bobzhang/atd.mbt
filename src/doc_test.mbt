// Port of atd/test/doc.ml

///|
fn normalize(s : String) -> String raise {
  @atd.print_doc_text(@atd.parse_doc_text(@atd.dummy_loc, s))
}

///|
test "doc: parser and printer" {
  let cases = [
    ("", ""),
    ("a", "a"),
    ("a b", "a b"),
    ("a\nb", "a b"),
    ("a  b", "a b"),
    ("a \n b", "a b"),
    ("a \n\n b", "a\n\nb"),
    ("  a  ", "a"),
    ("\n\na\n\n", "a"),
    ("{{}}", ""),
    ("{{a}}", "{{a}}"),
    ("{{  a  b\n\nc\n }}", "{{a b c}}"),
    ("{{ {a} }}", "{{ {a} }}"),
    ("{{{}}}", ""),
    ("{{{a}}}", "{{{\na\n}}}"),
    ("{{{ }}}", ""),
    ("{{{ {{a}} }}}", "{{{\n{{a}} \n}}}"),
    ("{{{ a\n\n  b }}}", "{{{\na\n\n b \n}}}"),
  ]
  for case in cases {
    let (input, expected) = case
    assert_eq(normalize(input), expected, msg="normalize \{input.escape()}")
  }
}

///|
test "doc: errors" {
  try normalize("{{ a") catch {
    e =>
      inspect(
        e,
        content=(
          #|File "", line 0, characters -1--1:
          #|Invalid format for doc.text "{{ a":
          #|Failure("Missing `}}'")
        ),
      )
  } noraise {
    _ => fail("expected an error")
  }
}

///|
test "doc: html" {
  let doc = @atd.parse_doc_text(
    @atd.dummy_loc, "Some <b>text</b> and {{code}}.\n\n{{{\n  pre\n}}}",
  )
  inspect(
    @atd.html_of_doc(doc),
    content=(
      #|
      #|<div class="atd-doc">
      #|<p>
      #|Some &lt;b&gt;text&lt;/b&gt; and <code>code</code>.
      #|</p>
      #|<pre>
      #|pre
      #|</pre>
      #|
      #|</div>
      #|
    ),
  )
}

///|
test "doc: rewrap" {
  debug_inspect(
    @atd.rewrap_paragraph(
      "  aaa bbb ccc\n ddd eeeeeeeeeeeeeeee f  ",
      max_length=8,
    ),
    content=(
      #|["aaa bbb", "ccc ddd", "eeeeeeeeeeeeeeee", "f"]
    ),
  )
}

// Tests ported from OCaml's testsuite/tests/lib-format/tformat.ml.

///|
test "tformat: d/i negative" {
  // line 31
  assert_eq(@format.sprintf("%d/%i", [Int(-42), Int(-43)]), "-42/-43")
  // line 32
  assert_eq(@format.sprintf("%-4d/%-5i", [Int(-42), Int(-43)]), "-42 /-43  ")
  // line 33
  assert_eq(@format.sprintf("%04d/%05i", [Int(-42), Int(-43)]), "-042/-0043")
  // line 34
  assert_eq(@format.sprintf("%+d/%+i", [Int(-42), Int(-43)]), "-42/-43")
  // line 35
  assert_eq(@format.sprintf("% d/% i", [Int(-42), Int(-43)]), "-42/-43")
  // line 36
  assert_eq(@format.sprintf("%#d/%#i", [Int(-42), Int(-43)]), "-42/-43")
  // line 37
  assert_eq(@format.sprintf("%4d/%5i", [Int(-42), Int(-43)]), " -42/  -43")
  // line 38
  assert_eq(@format.sprintf("%*d", [Int(-4), Int(-42)]), "-42 ")
  // line 39
  assert_eq(
    @format.sprintf("%*d/%*i", [Int(4), Int(-42), Int(5), Int(-43)]),
    " -42/  -43",
  )
  // line 40
  assert_eq(
    @format.sprintf("%-0+ #4d/%-0+ #5i", [Int(-42), Int(-43)]),
    "-42 /-43  ",
  )
}

///|
test "tformat: u positive" {
  // line 43
  assert_eq(@format.sprintf("%u", [Int(42)]), "42")
  // line 44
  assert_eq(@format.sprintf("%-4u", [Int(42)]), "42  ")
  // line 45
  assert_eq(@format.sprintf("%04u", [Int(42)]), "0042")
  // line 46
  assert_eq(@format.sprintf("%+u", [Int(42)]), "42")
  // line 47
  assert_eq(@format.sprintf("% u", [Int(42)]), "42")
  // line 48
  assert_eq(@format.sprintf("%#u", [Int(42)]), "42")
  // line 49
  assert_eq(@format.sprintf("%4u", [Int(42)]), "  42")
  // line 50
  assert_eq(@format.sprintf("%*u", [Int(4), Int(42)]), "  42")
  // line 51
  assert_eq(@format.sprintf("%*u", [Int(-4), Int(42)]), "42  ")
}

///|
test "tformat: u negative" {
  // line 58
  assert_eq(@format.sprintf("%u", [Int(-1)]), "9223372036854775807")
}

///|
test "tformat: x positive" {
  // line 63
  assert_eq(@format.sprintf("%x", [Int(42)]), "2a")
  // line 64
  assert_eq(@format.sprintf("%-4x", [Int(42)]), "2a  ")
  // line 65
  assert_eq(@format.sprintf("%04x", [Int(42)]), "002a")
  // line 66
  assert_eq(@format.sprintf("%+x", [Int(42)]), "2a")
  // line 67
  assert_eq(@format.sprintf("% x", [Int(42)]), "2a")
  // line 68
  assert_eq(@format.sprintf("%#x", [Int(42)]), "0x2a")
  // line 69
  assert_eq(@format.sprintf("%4x", [Int(42)]), "  2a")
  // line 70
  assert_eq(@format.sprintf("%*x", [Int(5), Int(42)]), "   2a")
  // line 71
  assert_eq(@format.sprintf("%*x", [Int(-5), Int(42)]), "2a   ")
  // line 72
  assert_eq(@format.sprintf("%#*x", [Int(5), Int(42)]), " 0x2a")
  // line 73
  assert_eq(@format.sprintf("%#*x", [Int(-5), Int(42)]), "0x2a ")
  // line 74
  assert_eq(@format.sprintf("%#-*x", [Int(5), Int(42)]), "0x2a ")
  // line 75
  assert_eq(@format.sprintf("%-0+ #*x", [Int(5), Int(42)]), "0x2a ")
}

///|
test "tformat: x negative" {
  // line 82
  assert_eq(@format.sprintf("%x", [Int(-42)]), "7fffffffffffffd6")
}

///|
test "tformat: X positive" {
  // line 87
  assert_eq(@format.sprintf("%X", [Int(42)]), "2A")
  // line 88
  assert_eq(@format.sprintf("%-4X", [Int(42)]), "2A  ")
  // line 89
  assert_eq(@format.sprintf("%04X", [Int(42)]), "002A")
  // line 90
  assert_eq(@format.sprintf("%+X", [Int(42)]), "2A")
  // line 91
  assert_eq(@format.sprintf("% X", [Int(42)]), "2A")
  // line 92
  assert_eq(@format.sprintf("%#X", [Int(42)]), "0X2A")
  // line 93
  assert_eq(@format.sprintf("%4X", [Int(42)]), "  2A")
  // line 94
  assert_eq(@format.sprintf("%*X", [Int(5), Int(42)]), "   2A")
  // line 95
  assert_eq(@format.sprintf("%-0+ #*X", [Int(5), Int(42)]), "0X2A ")
}

///|
test "tformat: x negative (2)" {
  // line 102
  assert_eq(@format.sprintf("%X", [Int(-42)]), "7FFFFFFFFFFFFFD6")
}

///|
test "tformat: o positive" {
  // line 107
  assert_eq(@format.sprintf("%o", [Int(42)]), "52")
  // line 108
  assert_eq(@format.sprintf("%-4o", [Int(42)]), "52  ")
  // line 109
  assert_eq(@format.sprintf("%04o", [Int(42)]), "0052")
  // line 110
  assert_eq(@format.sprintf("%+o", [Int(42)]), "52")
  // line 111
  assert_eq(@format.sprintf("% o", [Int(42)]), "52")
  // line 112
  assert_eq(@format.sprintf("%#o", [Int(42)]), "052")
  // line 113
  assert_eq(@format.sprintf("%4o", [Int(42)]), "  52")
  // line 114
  assert_eq(@format.sprintf("%*o", [Int(5), Int(42)]), "   52")
  // line 115
  assert_eq(@format.sprintf("%-0+ #*o", [Int(5), Int(42)]), "052  ")
}

///|
test "tformat: o negative" {
  // line 122
  assert_eq(@format.sprintf("%o", [Int(-42)]), "777777777777777777726")
}

///|
test "tformat: s" {
  // line 127
  assert_eq(@format.sprintf("%s", [String("foo")]), "foo")
  // line 128
  assert_eq(@format.sprintf("%-5s", [String("foo")]), "foo  ")
  // line 129
  assert_eq(@format.sprintf("%05s", [String("foo")]), "  foo")
  // line 130
  assert_eq(@format.sprintf("%+s", [String("foo")]), "foo")
  // line 131
  assert_eq(@format.sprintf("% s", [String("foo")]), "foo")
  // line 132
  assert_eq(@format.sprintf("%#s", [String("foo")]), "foo")
  // line 133
  assert_eq(@format.sprintf("%5s", [String("foo")]), "  foo")
  // line 134
  assert_eq(@format.sprintf("%1s", [String("foo")]), "foo")
  // line 135
  assert_eq(@format.sprintf("%*s", [Int(6), String("foo")]), "   foo")
  // line 136
  assert_eq(@format.sprintf("%*s", [Int(-6), String("foo")]), "foo   ")
  // line 137
  assert_eq(@format.sprintf("%*s", [Int(2), String("foo")]), "foo")
  // line 138
  assert_eq(@format.sprintf("%-0+ #5s", [String("foo")]), "foo  ")
  // line 139
  assert_eq(@format.sprintf("%s@@", [String("foo")]), "foo@")
  // line 140
  assert_eq(@format.sprintf("%s@@inria.fr", [String("foo")]), "foo@inria.fr")
  // line 141
  assert_eq(
    @format.sprintf("%s@@%s", [String("foo"), String("inria.fr")]),
    "foo@inria.fr",
  )
}

///|
test "tformat: S" {
  // line 144
  assert_eq(@format.sprintf("%S", [String("fo\"o")]), "\"fo\\\"o\"")
  // line 145
  assert_eq(@format.sprintf("%-7S", [String("foo")]), "\"foo\"  ")
  // line 148
  assert_eq(@format.sprintf("%+S", [String("foo")]), "\"foo\"")
  // line 149
  assert_eq(@format.sprintf("% S", [String("foo")]), "\"foo\"")
  // line 150
  assert_eq(@format.sprintf("%#S", [String("foo")]), "\"foo\"")
  // line 151
  assert_eq(@format.sprintf("%7S", [String("foo")]), "  \"foo\"")
  // line 152
  assert_eq(@format.sprintf("%1S", [String("foo")]), "\"foo\"")
  // line 153
  assert_eq(@format.sprintf("%*S", [Int(8), String("foo")]), "   \"foo\"")
  // line 154
  assert_eq(@format.sprintf("%*S", [Int(-8), String("foo")]), "\"foo\"   ")
  // line 155
  assert_eq(@format.sprintf("%*S", [Int(2), String("foo")]), "\"foo\"")
  // line 158
  assert_eq(@format.sprintf("%S@@", [String("foo")]), "\"foo\"@")
  // line 159
  assert_eq(
    @format.sprintf("%S@@inria.fr", [String("foo")]),
    "\"foo\"@inria.fr",
  )
  // line 160
  assert_eq(
    @format.sprintf("%S@@%S", [String("foo"), String("inria.fr")]),
    "\"foo\"@\"inria.fr\"",
  )
}

///|
test "tformat: c" {
  // line 163
  assert_eq(@format.sprintf("%c", [Char('c')]), "c")
  // line 166
  assert_eq(@format.sprintf("%+c", [Char('c')]), "c")
  // line 167
  assert_eq(@format.sprintf("% c", [Char('c')]), "c")
  // line 168
  assert_eq(@format.sprintf("%#c", [Char('c')]), "c")
}

///|
test "tformat: C" {
  // line 174
  assert_eq(@format.sprintf("%C", [Char('c')]), "'c'")
  // line 175
  assert_eq(@format.sprintf("%C", [Char('\'')]), "'\\''")
  // line 178
  assert_eq(@format.sprintf("%+C", [Char('c')]), "'c'")
  // line 179
  assert_eq(@format.sprintf("% C", [Char('c')]), "'c'")
  // line 180
  assert_eq(@format.sprintf("%#C", [Char('c')]), "'c'")
}

///|
test "tformat: f" {
  // line 186
  assert_eq(@format.sprintf("%f", [Float(-42.42)]), "-42.420000")
  // line 187
  assert_eq(@format.sprintf("%-13f", [Float(-42.42)]), "-42.420000   ")
  // line 188
  assert_eq(@format.sprintf("%013f", [Float(-42.42)]), "-00042.420000")
  // line 189
  assert_eq(@format.sprintf("%+f", [Float(42.42)]), "+42.420000")
  // line 190
  assert_eq(@format.sprintf("% f", [Float(42.42)]), " 42.420000")
  // line 191
  assert_eq(@format.sprintf("%#f", [Float(42.42)]), "42.420000")
  // line 192
  assert_eq(@format.sprintf("%13f", [Float(42.42)]), "    42.420000")
  // line 193
  assert_eq(@format.sprintf("%*f", [Int(12), Float(42.42)]), "   42.420000")
  // line 194
  assert_eq(@format.sprintf("%-0+ #12f", [Float(42.42)]), "+42.420000  ")
  // line 195
  assert_eq(@format.sprintf("%.3f", [Float(-42.42)]), "-42.420")
  // line 196
  assert_eq(@format.sprintf("%-13.3f", [Float(-42.42)]), "-42.420      ")
  // line 197
  assert_eq(@format.sprintf("%013.3f", [Float(-42.42)]), "-00000042.420")
  // line 198
  assert_eq(@format.sprintf("%+.3f", [Float(42.42)]), "+42.420")
  // line 199
  assert_eq(@format.sprintf("% .3f", [Float(42.42)]), " 42.420")
  // line 200
  assert_eq(@format.sprintf("%#.3f", [Float(42.42)]), "42.420")
  // line 201
  assert_eq(@format.sprintf("%13.3f", [Float(42.42)]), "       42.420")
  // line 202
  assert_eq(
    @format.sprintf("%*.*f", [Int(12), Int(3), Float(42.42)]),
    "      42.420",
  )
  // line 203
  assert_eq(@format.sprintf("%-0+ #12.3f", [Float(42.42)]), "+42.420     ")
}

///|
test "tformat: F" {
  // line 230
  assert_eq(@format.sprintf("%F", [Float(42.42)]), "42.42")
  // line 231
  assert_eq(@format.sprintf("%F", [Float(4.242e+43)]), "4.242e+43")
  // line 232
  assert_eq(@format.sprintf("%F", [Float(42.0)]), "42.")
  // line 233
  assert_eq(@format.sprintf("%F", [Float(0.042)]), "0.042")
  // line 234
  assert_eq(@format.sprintf("%4F", [Float(3.0)]), "  3.")
  // line 235
  assert_eq(@format.sprintf("%-4F", [Float(3.0)]), "3.  ")
  // line 236
  assert_eq(@format.sprintf("%04F", [Float(3.0)]), "003.")
}

///|
test "tformat: h" {
  // line 248
  assert_eq(@format.sprintf("%+h", [Float(0.0)]), "+0x0p+0")
  // line 249
  assert_eq(@format.sprintf("%+h", [Float(-0.0)]), "-0x0p+0")
  // line 250
  assert_eq(@format.sprintf("%+h", [Float(1.0)]), "+0x1p+0")
  // line 251
  assert_eq(@format.sprintf("%+h", [Float(-1.0)]), "-0x1p+0")
  // line 252
  assert_eq(@format.sprintf("%+h", [Float(1024.0)]), "+0x1p+10")
  // line 253
  assert_eq(@format.sprintf("%+h", [Float(-1024.0)]), "-0x1p+10")
  // line 254
  assert_eq(@format.sprintf("%h", [Float(291.27099609375)]), "0x1.23456p+8")
  // line 255
  assert_eq(
    @format.sprintf("%h", [Float(5124095576030430.0)]),
    "0x1.23456789abcdep+52",
  )
  // line 257
  assert_eq(@format.sprintf("%h", [Float(@double.not_a_number)]), "nan")
  // line 258
  assert_eq(@format.sprintf("%h", [Float(@double.infinity)]), "infinity")
  // line 259
  assert_eq(@format.sprintf("%h", [Float(@double.neg_infinity)]), "-infinity")
  // line 260
  assert_eq(
    @format.sprintf("%h", [Float(3.141592653589793)]),
    "0x1.921fb54442d18p+1",
  )
}

///|
test "tformat: H" {
  // line 263
  assert_eq(@format.sprintf("%+H", [Float(0.0)]), "+0X0P+0")
  // line 264
  assert_eq(@format.sprintf("%+H", [Float(-0.0)]), "-0X0P+0")
  // line 265
  assert_eq(@format.sprintf("%+H", [Float(1.0)]), "+0X1P+0")
  // line 266
  assert_eq(@format.sprintf("%+H", [Float(-1.0)]), "-0X1P+0")
  // line 267
  assert_eq(@format.sprintf("%+H", [Float(1024.0)]), "+0X1P+10")
  // line 268
  assert_eq(@format.sprintf("%+H", [Float(-1024.0)]), "-0X1P+10")
  // line 269
  assert_eq(@format.sprintf("%H", [Float(291.27099609375)]), "0X1.23456P+8")
  // line 270
  assert_eq(
    @format.sprintf("%H", [Float(5124095576030430.0)]),
    "0X1.23456789ABCDEP+52",
  )
  // line 272
  assert_eq(@format.sprintf("%H", [Float(@double.not_a_number)]), "NAN")
  // line 273
  assert_eq(@format.sprintf("%H", [Float(@double.infinity)]), "INFINITY")
  // line 274
  assert_eq(@format.sprintf("%H", [Float(@double.neg_infinity)]), "-INFINITY")
  // line 275
  assert_eq(
    @format.sprintf("%H", [Float(3.141592653589793)]),
    "0X1.921FB54442D18P+1",
  )
}

///|
test "tformat: e" {
  // line 278
  assert_eq(@format.sprintf("%e", [Float(-42.42)]), "-4.242000e+01")
  // line 279
  assert_eq(@format.sprintf("%-15e", [Float(-42.42)]), "-4.242000e+01  ")
  // line 280
  assert_eq(@format.sprintf("%015e", [Float(-42.42)]), "-004.242000e+01")
  // line 281
  assert_eq(@format.sprintf("%+e", [Float(42.42)]), "+4.242000e+01")
  // line 282
  assert_eq(@format.sprintf("% e", [Float(42.42)]), " 4.242000e+01")
  // line 283
  assert_eq(@format.sprintf("%#e", [Float(42.42)]), "4.242000e+01")
  // line 284
  assert_eq(@format.sprintf("%15e", [Float(42.42)]), "   4.242000e+01")
  // line 285
  assert_eq(@format.sprintf("%*e", [Int(14), Float(42.42)]), "  4.242000e+01")
  // line 286
  assert_eq(@format.sprintf("%-0+ #14e", [Float(42.42)]), "+4.242000e+01 ")
  // line 287
  assert_eq(@format.sprintf("%.3e", [Float(-42.42)]), "-4.242e+01")
  // line 288
  assert_eq(@format.sprintf("%-15.3e", [Float(-42.42)]), "-4.242e+01     ")
  // line 289
  assert_eq(@format.sprintf("%015.3e", [Float(-42.42)]), "-000004.242e+01")
  // line 290
  assert_eq(@format.sprintf("%+.3e", [Float(42.42)]), "+4.242e+01")
  // line 291
  assert_eq(@format.sprintf("% .3e", [Float(42.42)]), " 4.242e+01")
  // line 292
  assert_eq(@format.sprintf("%#.3e", [Float(42.42)]), "4.242e+01")
  // line 293
  assert_eq(@format.sprintf("%15.3e", [Float(42.42)]), "      4.242e+01")
  // line 294
  assert_eq(
    @format.sprintf("%*.*e", [Int(11), Int(3), Float(42.42)]),
    "  4.242e+01",
  )
  // line 295
  assert_eq(@format.sprintf("%-0+ #14.3e", [Float(42.42)]), "+4.242e+01    ")
}

///|
test "tformat: E" {
  // line 298
  assert_eq(@format.sprintf("%E", [Float(-42.42)]), "-4.242000E+01")
  // line 299
  assert_eq(@format.sprintf("%-15E", [Float(-42.42)]), "-4.242000E+01  ")
  // line 300
  assert_eq(@format.sprintf("%015E", [Float(-42.42)]), "-004.242000E+01")
  // line 301
  assert_eq(@format.sprintf("%+E", [Float(42.42)]), "+4.242000E+01")
  // line 302
  assert_eq(@format.sprintf("% E", [Float(42.42)]), " 4.242000E+01")
  // line 303
  assert_eq(@format.sprintf("%#E", [Float(42.42)]), "4.242000E+01")
  // line 304
  assert_eq(@format.sprintf("%15E", [Float(42.42)]), "   4.242000E+01")
  // line 305
  assert_eq(@format.sprintf("%*E", [Int(14), Float(42.42)]), "  4.242000E+01")
  // line 306
  assert_eq(@format.sprintf("%-0+ #14E", [Float(42.42)]), "+4.242000E+01 ")
  // line 307
  assert_eq(@format.sprintf("%.3E", [Float(-42.42)]), "-4.242E+01")
  // line 308
  assert_eq(@format.sprintf("%-15.3E", [Float(-42.42)]), "-4.242E+01     ")
  // line 309
  assert_eq(@format.sprintf("%015.3E", [Float(-42.42)]), "-000004.242E+01")
  // line 310
  assert_eq(@format.sprintf("%+.3E", [Float(42.42)]), "+4.242E+01")
  // line 311
  assert_eq(@format.sprintf("% .3E", [Float(42.42)]), " 4.242E+01")
  // line 312
  assert_eq(@format.sprintf("%#.3E", [Float(42.42)]), "4.242E+01")
  // line 313
  assert_eq(@format.sprintf("%15.3E", [Float(42.42)]), "      4.242E+01")
  // line 314
  assert_eq(
    @format.sprintf("%*.*E", [Int(11), Int(3), Float(42.42)]),
    "  4.242E+01",
  )
  // line 315
  assert_eq(@format.sprintf("%-0+ #14.3E", [Float(42.42)]), "+4.242E+01    ")
}

///|
test "tformat: B" {
  // line 336
  assert_eq(@format.sprintf("%B", [Bool(true)]), "true")
  // line 337
  assert_eq(@format.sprintf("%B", [Bool(false)]), "false")
}

///|
test "tformat: ld/li positive" {
  // line 342
  assert_eq(@format.sprintf("%ld/%li", [Int32(42), Int32(43)]), "42/43")
  // line 343
  assert_eq(
    @format.sprintf("%-4ld/%-5li", [Int32(42), Int32(43)]),
    "42  /43   ",
  )
  // line 344
  assert_eq(
    @format.sprintf("%04ld/%05li", [Int32(42), Int32(43)]),
    "0042/00043",
  )
  // line 345
  assert_eq(@format.sprintf("%+ld/%+li", [Int32(42), Int32(43)]), "+42/+43")
  // line 346
  assert_eq(@format.sprintf("% ld/% li", [Int32(42), Int32(43)]), " 42/ 43")
  // line 347
  assert_eq(@format.sprintf("%#ld/%#li", [Int32(42), Int32(43)]), "42/43")
  // line 348
  assert_eq(@format.sprintf("%4ld/%5li", [Int32(42), Int32(43)]), "  42/   43")
  // line 349
  assert_eq(
    @format.sprintf("%*ld/%*li", [Int(4), Int32(42), Int(5), Int32(43)]),
    "  42/   43",
  )
  // line 350
  assert_eq(
    @format.sprintf("%-0+#4ld/%-0 #5li", [Int32(42), Int32(43)]),
    "+42 / 43  ",
  )
}

///|
test "tformat: ld/li negative" {
  // line 353
  assert_eq(@format.sprintf("%ld/%li", [Int32(-42), Int32(-43)]), "-42/-43")
  // line 354
  assert_eq(
    @format.sprintf("%-4ld/%-5li", [Int32(-42), Int32(-43)]),
    "-42 /-43  ",
  )
  // line 355
  assert_eq(
    @format.sprintf("%04ld/%05li", [Int32(-42), Int32(-43)]),
    "-042/-0043",
  )
  // line 356
  assert_eq(@format.sprintf("%+ld/%+li", [Int32(-42), Int32(-43)]), "-42/-43")
  // line 357
  assert_eq(@format.sprintf("% ld/% li", [Int32(-42), Int32(-43)]), "-42/-43")
  // line 358
  assert_eq(@format.sprintf("%#ld/%#li", [Int32(-42), Int32(-43)]), "-42/-43")
  // line 359
  assert_eq(
    @format.sprintf("%4ld/%5li", [Int32(-42), Int32(-43)]),
    " -42/  -43",
  )
  // line 360
  assert_eq(
    @format.sprintf("%*ld/%*li", [Int(4), Int32(-42), Int(5), Int32(-43)]),
    " -42/  -43",
  )
  // line 361
  assert_eq(
    @format.sprintf("%-0+ #4ld/%-0+ #5li", [Int32(-42), Int32(-43)]),
    "-42 /-43  ",
  )
}

///|
test "tformat: lu positive" {
  // line 364
  assert_eq(@format.sprintf("%lu", [Int32(42)]), "42")
  // line 365
  assert_eq(@format.sprintf("%-4lu", [Int32(42)]), "42  ")
  // line 366
  assert_eq(@format.sprintf("%04lu", [Int32(42)]), "0042")
  // line 367
  assert_eq(@format.sprintf("%+lu", [Int32(42)]), "42")
  // line 368
  assert_eq(@format.sprintf("% lu", [Int32(42)]), "42")
  // line 369
  assert_eq(@format.sprintf("%#lu", [Int32(42)]), "42")
  // line 370
  assert_eq(@format.sprintf("%4lu", [Int32(42)]), "  42")
  // line 371
  assert_eq(@format.sprintf("%*lu", [Int(4), Int32(42)]), "  42")
  // line 372
  assert_eq(@format.sprintf("%-0+ #6ld", [Int32(42)]), "+42   ")
}

///|
test "tformat: lu negative" {
  // line 375
  assert_eq(@format.sprintf("%lu", [Int32(-1)]), "4294967295")
}

///|
test "tformat: lx positive" {
  // line 378
  assert_eq(@format.sprintf("%lx", [Int32(42)]), "2a")
  // line 379
  assert_eq(@format.sprintf("%-4lx", [Int32(42)]), "2a  ")
  // line 380
  assert_eq(@format.sprintf("%04lx", [Int32(42)]), "002a")
  // line 381
  assert_eq(@format.sprintf("%+lx", [Int32(42)]), "2a")
  // line 382
  assert_eq(@format.sprintf("% lx", [Int32(42)]), "2a")
  // line 383
  assert_eq(@format.sprintf("%#lx", [Int32(42)]), "0x2a")
  // line 384
  assert_eq(@format.sprintf("%4lx", [Int32(42)]), "  2a")
  // line 385
  assert_eq(@format.sprintf("%*lx", [Int(5), Int32(42)]), "   2a")
  // line 386
  assert_eq(@format.sprintf("%-0+ #*lx", [Int(5), Int32(42)]), "0x2a ")
}

///|
test "tformat: lx negative" {
  // line 389
  assert_eq(@format.sprintf("%lx", [Int32(-42)]), "ffffffd6")
}

///|
test "tformat: lX positive" {
  // line 392
  assert_eq(@format.sprintf("%lX", [Int32(42)]), "2A")
  // line 393
  assert_eq(@format.sprintf("%-4lX", [Int32(42)]), "2A  ")
  // line 394
  assert_eq(@format.sprintf("%04lX", [Int32(42)]), "002A")
  // line 395
  assert_eq(@format.sprintf("%+lX", [Int32(42)]), "2A")
  // line 396
  assert_eq(@format.sprintf("% lX", [Int32(42)]), "2A")
  // line 397
  assert_eq(@format.sprintf("%#lX", [Int32(42)]), "0X2A")
  // line 398
  assert_eq(@format.sprintf("%4lX", [Int32(42)]), "  2A")
  // line 399
  assert_eq(@format.sprintf("%*lX", [Int(5), Int32(42)]), "   2A")
  // line 400
  assert_eq(@format.sprintf("%-0+ #*lX", [Int(5), Int32(42)]), "0X2A ")
}

///|
test "tformat: lx negative (2)" {
  // line 403
  assert_eq(@format.sprintf("%lX", [Int32(-42)]), "FFFFFFD6")
}

///|
test "tformat: lo positive" {
  // line 406
  assert_eq(@format.sprintf("%lo", [Int32(42)]), "52")
  // line 407
  assert_eq(@format.sprintf("%-4lo", [Int32(42)]), "52  ")
  // line 408
  assert_eq(@format.sprintf("%04lo", [Int32(42)]), "0052")
  // line 409
  assert_eq(@format.sprintf("%+lo", [Int32(42)]), "52")
  // line 410
  assert_eq(@format.sprintf("% lo", [Int32(42)]), "52")
  // line 411
  assert_eq(@format.sprintf("%#lo", [Int32(42)]), "052")
  // line 412
  assert_eq(@format.sprintf("%4lo", [Int32(42)]), "  52")
  // line 413
  assert_eq(@format.sprintf("%*lo", [Int(5), Int32(42)]), "   52")
  // line 414
  assert_eq(@format.sprintf("%-0+ #*lo", [Int(5), Int32(42)]), "052  ")
}

///|
test "tformat: lo negative" {
  // line 417
  assert_eq(@format.sprintf("%lo", [Int32(-42)]), "37777777726")
}

///|
test "tformat: Ld/Li positive" {
  // line 423
  assert_eq(@format.sprintf("%Ld/%Li", [Int64(42L), Int64(43L)]), "42/43")
  // line 424
  assert_eq(
    @format.sprintf("%-4Ld/%-5Li", [Int64(42L), Int64(43L)]),
    "42  /43   ",
  )
  // line 425
  assert_eq(
    @format.sprintf("%04Ld/%05Li", [Int64(42L), Int64(43L)]),
    "0042/00043",
  )
  // line 426
  assert_eq(@format.sprintf("%+Ld/%+Li", [Int64(42L), Int64(43L)]), "+42/+43")
  // line 427
  assert_eq(@format.sprintf("% Ld/% Li", [Int64(42L), Int64(43L)]), " 42/ 43")
  // line 428
  assert_eq(@format.sprintf("%#Ld/%#Li", [Int64(42L), Int64(43L)]), "42/43")
  // line 429
  assert_eq(
    @format.sprintf("%4Ld/%5Li", [Int64(42L), Int64(43L)]),
    "  42/   43",
  )
  // line 430
  assert_eq(
    @format.sprintf("%*Ld/%*Li", [Int(4), Int64(42L), Int(5), Int64(43L)]),
    "  42/   43",
  )
  // line 431
  assert_eq(
    @format.sprintf("%-0+#4Ld/%-0 #5Li", [Int64(42L), Int64(43L)]),
    "+42 / 43  ",
  )
}

///|
test "tformat: Ld/Li negative" {
  // line 434
  assert_eq(@format.sprintf("%Ld/%Li", [Int64(-42L), Int64(-43L)]), "-42/-43")
  // line 435
  assert_eq(
    @format.sprintf("%-4Ld/%-5Li", [Int64(-42L), Int64(-43L)]),
    "-42 /-43  ",
  )
  // line 436
  assert_eq(
    @format.sprintf("%04Ld/%05Li", [Int64(-42L), Int64(-43L)]),
    "-042/-0043",
  )
  // line 437
  assert_eq(@format.sprintf("%+Ld/%+Li", [Int64(-42L), Int64(-43L)]), "-42/-43")
  // line 438
  assert_eq(@format.sprintf("% Ld/% Li", [Int64(-42L), Int64(-43L)]), "-42/-43")
  // line 439
  assert_eq(@format.sprintf("%#Ld/%#Li", [Int64(-42L), Int64(-43L)]), "-42/-43")
  // line 440
  assert_eq(
    @format.sprintf("%4Ld/%5Li", [Int64(-42L), Int64(-43L)]),
    " -42/  -43",
  )
  // line 441
  assert_eq(
    @format.sprintf("%*Ld/%*Li", [Int(4), Int64(-42L), Int(5), Int64(-43L)]),
    " -42/  -43",
  )
  // line 442
  assert_eq(
    @format.sprintf("%-0+ #4Ld/%-0+ #5Li", [Int64(-42L), Int64(-43L)]),
    "-42 /-43  ",
  )
}

///|
test "tformat: Lu positive" {
  // line 445
  assert_eq(@format.sprintf("%Lu", [Int64(42L)]), "42")
  // line 446
  assert_eq(@format.sprintf("%-4Lu", [Int64(42L)]), "42  ")
  // line 447
  assert_eq(@format.sprintf("%04Lu", [Int64(42L)]), "0042")
  // line 448
  assert_eq(@format.sprintf("%+Lu", [Int64(42L)]), "42")
  // line 449
  assert_eq(@format.sprintf("% Lu", [Int64(42L)]), "42")
  // line 450
  assert_eq(@format.sprintf("%#Lu", [Int64(42L)]), "42")
  // line 451
  assert_eq(@format.sprintf("%4Lu", [Int64(42L)]), "  42")
  // line 452
  assert_eq(@format.sprintf("%*Lu", [Int(4), Int64(42L)]), "  42")
  // line 453
  assert_eq(@format.sprintf("%-0+ #6Ld", [Int64(42L)]), "+42   ")
}

///|
test "tformat: Lu negative" {
  // line 456
  assert_eq(@format.sprintf("%Lu", [Int64(-1L)]), "18446744073709551615")
}

///|
test "tformat: Lx positive" {
  // line 459
  assert_eq(@format.sprintf("%Lx", [Int64(42L)]), "2a")
  // line 460
  assert_eq(@format.sprintf("%-4Lx", [Int64(42L)]), "2a  ")
  // line 461
  assert_eq(@format.sprintf("%04Lx", [Int64(42L)]), "002a")
  // line 462
  assert_eq(@format.sprintf("%+Lx", [Int64(42L)]), "2a")
  // line 463
  assert_eq(@format.sprintf("% Lx", [Int64(42L)]), "2a")
  // line 464
  assert_eq(@format.sprintf("%#Lx", [Int64(42L)]), "0x2a")
  // line 465
  assert_eq(@format.sprintf("%4Lx", [Int64(42L)]), "  2a")
  // line 466
  assert_eq(@format.sprintf("%*Lx", [Int(5), Int64(42L)]), "   2a")
  // line 467
  assert_eq(@format.sprintf("%-0+ #*Lx", [Int(5), Int64(42L)]), "0x2a ")
}

///|
test "tformat: Lx negative" {
  // line 470
  assert_eq(@format.sprintf("%Lx", [Int64(-42L)]), "ffffffffffffffd6")
}

///|
test "tformat: LX positive" {
  // line 473
  assert_eq(@format.sprintf("%LX", [Int64(42L)]), "2A")
  // line 474
  assert_eq(@format.sprintf("%-4LX", [Int64(42L)]), "2A  ")
  // line 475
  assert_eq(@format.sprintf("%04LX", [Int64(42L)]), "002A")
  // line 476
  assert_eq(@format.sprintf("%+LX", [Int64(42L)]), "2A")
  // line 477
  assert_eq(@format.sprintf("% LX", [Int64(42L)]), "2A")
  // line 478
  assert_eq(@format.sprintf("%#LX", [Int64(42L)]), "0X2A")
  // line 479
  assert_eq(@format.sprintf("%4LX", [Int64(42L)]), "  2A")
  // line 480
  assert_eq(@format.sprintf("%*LX", [Int(5), Int64(42L)]), "   2A")
  // line 481
  assert_eq(@format.sprintf("%-0+ #*LX", [Int(5), Int64(42L)]), "0X2A ")
}

///|
test "tformat: Lx negative (2)" {
  // line 484
  assert_eq(@format.sprintf("%LX", [Int64(-42L)]), "FFFFFFFFFFFFFFD6")
}

///|
test "tformat: Lo positive" {
  // line 487
  assert_eq(@format.sprintf("%Lo", [Int64(42L)]), "52")
  // line 488
  assert_eq(@format.sprintf("%-4Lo", [Int64(42L)]), "52  ")
  // line 489
  assert_eq(@format.sprintf("%04Lo", [Int64(42L)]), "0052")
  // line 490
  assert_eq(@format.sprintf("%+Lo", [Int64(42L)]), "52")
  // line 491
  assert_eq(@format.sprintf("% Lo", [Int64(42L)]), "52")
  // line 492
  assert_eq(@format.sprintf("%#Lo", [Int64(42L)]), "052")
  // line 493
  assert_eq(@format.sprintf("%4Lo", [Int64(42L)]), "  52")
  // line 494
  assert_eq(@format.sprintf("%*Lo", [Int(5), Int64(42L)]), "   52")
  // line 495
  assert_eq(@format.sprintf("%-0+ #*Lo", [Int(5), Int64(42L)]), "052  ")
}

///|
test "tformat: Lo negative" {
  // line 498
  assert_eq(@format.sprintf("%Lo", [Int64(-42L)]), "1777777777777777777726")
}

///|
test "tformat: ! % @ , and constants" {
  // line 521
  assert_eq(@format.sprintf("%!", []), "")
  // line 522
  assert_eq(@format.sprintf("%%", []), "%")
  // line 523
  assert_eq(@format.sprintf("%@", []), "@")
  // line 524
  assert_eq(@format.sprintf("%,", []), "")
  // line 525
  assert_eq(@format.sprintf("@@", []), "@")
  // line 526
  assert_eq(@format.sprintf("@@@@", []), "@@")
  // line 527
  assert_eq(@format.sprintf("@@%%", []), "@%")
}

///|
test "tformat: special values" {
  // line 256
  assert_eq(@format.sprintf("%h", [Float(2.220446049250313e-16)]), "0x1p-52")
  // line 271
  assert_eq(@format.sprintf("%H", [Float(2.220446049250313e-16)]), "0X1P-52")
}

///|
test "tformat: a" {
  // line 503: OCaml's `%a` takes a printer and a value; here the printer
  // is already applied to its value
  let x = Ref::{ val: (), }
  let f = (ppf : @format.Formatter, y : Ref[Unit]) => {
    ppf.print_string(if physical_equal(y, x) { "ok" } else { "wrong" })
  }
  assert_eq(@format.sprintf("%a", [Print(ppf => f(ppf, x))]), "ok")
}

///|
test "tformat: t" {
  // line 507
  assert_eq(@format.sprintf("%t", [Print(ppf => ppf.print_string("ok"))]), "ok")
}

///|
test "tformat: {...%}" {
  // line 514
  assert_eq(@format.sprintf("%{%f%s%}", [Format("%f/%s")]), "%f%s")
}

///|
test "tformat: (...%)" {
  // line 518
  assert_eq(
    @format.sprintf("%(%d%s%)", [Format("%d/foo/%s"), Int(42), String("bar")]),
    "42/foo/bar",
  )
}

///|
test "tformat: Delayed printf" {
  // lines 530-534
  let t1 = @format.dprintf("%i - %s", [Int(1), String("bar")])
  assert_eq(@format.asprintf("foo %t", [Print(t1)]), "foo 1 - bar")
  let t2 = @format.dprintf("%a@]", [
    Print(ppf => {
      ppf.print_list(@format.Formatter::print_int, @list.List([1, 2, 3]))
    }),
  ])
  assert_eq(
    @format.asprintf("foo @[<v>%t@,%s", [Print(t2), String("bar")]),
    "foo 1\n    2\n    3\nbar",
  )
  assert_eq(
    @format.asprintf("%t @[<h>%t", [Print(t1), Print(t2)]),
    "1 - bar 123",
  )
}

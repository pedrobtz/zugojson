// zugojson's JSON parser and printer, written in Goose
// (https://github.com/aardappel/goose) and compiled to C by
// tools/regenerate.sh. The generated C is what the package builds; this
// file is its source. Never edit src/zugojson_goose.c by hand.
//
// Derived from the Goose repository's samples/18_json.goose (Apache-2.0,
// Wouter van Oortmerssen). Changes from the sample: no main; a nesting
// limit; JSON's number grammar, with C's strtod for the conversion; the
// \b and \f escapes; control bytes escaped on output; a range check
// before a number is printed as an integer; and the exported API at the
// end.
//
// The document becomes a tree of variable-mode enum values in one
// grow-only pool: a number is a tag and an f64, a string is a tag and its
// bytes, an array is a tag, a count and a link to its first child. Every
// link is a 4-byte self-relative offset within the pool, so the parsed
// document is one contiguous block. Children are parsed (and pushed)
// before their parent, and siblings are chained by patching the previous
// child's link. Any syntax error, however deep, is one `return ... from
// parse` carrying the message and position back to the top.

import std;

// A node is a sibling link, a key (empty for array elements) and the
// value; the value's payload is exactly as large as its variant needs.
struct Node { next: Node&<u32>?, key: u8[varint], val: Json.. }

enum Json {
    Null,
    Bool { v: bool },
    Num { v: f64 },
    Str { s: u8[varint] },
    Arr { first: Node&<u32>?, count: varint },
    Obj { first: Node&<u32>?, count: varint },
}

var pool: Node[>..] = [];

// src/zugojson_number.c: a correctly rounded conversion of text the parser
// has already checked against JSON's number grammar.
extern fn zugojson_strtod(s: const u8[:]) -> f64 = "zugojson_strtod";

// --- parsing -----------------------------------------------------------

// The root node, or null and a message. A function in the recursive cycle
// cannot own a growable value, but the cycle lives inside this function,
// whose locals outlive every activation of it: the key buffer is one.
fn parse(text: u8[:]) -> Node?, u8[>..] {
    var pos = 0;
    var keys: u8[>..] = [];              // object keys, decoded before their values
    var depth = 0;                       // open containers; bounds the native stack

    fn skip_space() {
        while pos < text.len && (text[pos] == ' ' || text[pos] == '\n' || text[pos] == '\r' || text[pos] == '\t') { pos++; }
    }

    fn fail(what: u8[:]) -> u8[>..] { str(what, " at byte ", pos) }

    fn expect(c: u8) {
        skip_space();
        if pos < text.len && text[pos] == c { pos++; return; }
        var msg: u8[>..] = [];
        format(msg, "expected '");
        msg.push(c);                     // the byte itself: str(c) would print its number
        msg.push('\'');
        return null, fail(msg) from parse;
    }

    fn hex_digit(c: u8) -> i64 {
        if c >= '0' && c <= '9' { return c - '0'; }
        if c >= 'a' && c <= 'f' { return c - 'a' + 10; }
        if c >= 'A' && c <= 'F' { return c - 'A' + 10; }
        return null, fail("bad hex digit") from parse;
    }

    // A string's decoded bytes, built straight into the field that receives
    // them. Not part of the recursive cycle, so it may own a builder.
    fn parse_string() -> u8[>..] {
        expect('"');
        var s: u8[>..] = [];
        loop {
            guard pos < text.len else { return null, fail("unterminated string") from parse; }
            let c = text[pos];
            pos++;
            if c == '"' { break; }
            if c != '\\' { s.push(c); continue; }
            guard pos < text.len else { return null, fail("bad escape") from parse; }
            let e = text[pos];
            pos++;
            if e == 'n' { s.push('\n'); }
            else if e == 't' { s.push('\t'); }
            else if e == 'r' { s.push('\r'); }
            else if e == 'b' { s.push(8); }
            else if e == 'f' { s.push(12); }
            else if e == 'u' {
                guard pos + 4 <= text.len else { return null, fail("bad \\u escape") from parse; }
                var cp = 0;
                for i in 4 { cp = cp * 16 + hex_digit(text[pos + i]); }
                pos += 4;
                push_utf8(s, cp);
            }
            else { s.push(e); }          // \" \\ \/ and the rest
        }
        return s;
    }

    // JSON's number grammar, checked here, then converted by C's strtod:
    // std's parse_flt can be an ulp off for long mantissas and large
    // exponents, and a formatter that changes numbers is no formatter.
    fn digits() -> i64 {
        let start = pos;
        while pos < text.len && text[pos] >= '0' && text[pos] <= '9' { pos++; }
        return pos - start;
    }

    fn parse_number() -> f64 {
        let start = pos;
        if pos < text.len && text[pos] == '-' { pos++; }
        guard pos < text.len else { return null, fail("bad number") from parse; }
        if text[pos] == '0' { pos++; }
        else { guard digits() > 0 else { return null, fail("bad number") from parse; } }
        if pos < text.len && text[pos] == '.' {
            pos++;
            guard digits() > 0 else { return null, fail("bad number") from parse; }
        }
        if pos < text.len && (text[pos] == 'e' || text[pos] == 'E') {
            pos++;
            if pos < text.len && (text[pos] == '+' || text[pos] == '-') { pos++; }
            guard digits() > 0 else { return null, fail("bad number") from parse; }
        }
        let v = zugojson_strtod(text[start..pos]);
        // Too large for a double: infinity has no JSON spelling.
        guard v - v == 0.0 else { return null, fail("number out of range") from parse; }
        return v;
    }

    fn parse_word(w: u8[:]) {
        guard pos + w.len <= text.len && text[pos..pos + w.len] == w else { return null, fail("unexpected token") from parse; }
        pos += w.len;
    }

    // One child of a container: an object member (key, colon, value) or an
    // array element. The key is decoded into `keys` and handed down as a
    // slice of it; the node copies its bytes.
    recursive fn parse_child(is_obj: bool) -> Node& {
        if is_obj {
            let start = keys.len;
            keys.append(parse_string());
            expect(':');
            return parse_value(keys[start..]);
        }
        return parse_value("");
    }

    // One value, pushed onto the pool as a node with the given key; the
    // node it returns is what the caller links into its own chain.
    recursive fn parse_value(key: u8[:]) -> Node& {
        skip_space();
        guard pos < text.len else { return null, fail("unexpected end of input") from parse; }
        let c = text[pos];
        if c == '{' || c == '[' {
            let is_obj = c == '{';
            let close = if is_obj { '}' } else { ']' };
            depth++;
            guard depth <= 512 else { return null, fail("nesting deeper than 512") from parse; }
            pos++;
            skip_space();
            guard pos < text.len else { return null, fail("unclosed container") from parse; }
            var first: Node? = null;
            var count = 0;
            if text[pos] != close {
                // The first child, then the rest, each linked from the
                // previous one: the link is a fixed-width relative
                // reference, so it can be stored after the node was pushed.
                let head .= parse_child(is_obj);
                first .= head;
                var last .= head;
                count = 1;
                loop {
                    skip_space();
                    guard pos < text.len else { return null, fail("unclosed container") from parse; }
                    if text[pos] == close { break; }
                    expect(',');
                    let child .= parse_child(is_obj);
                    last.next .= child;
                    last .= child;
                    count++;
                }
            }
            pos++;
            depth--;
            if is_obj { return pool.push(Node { next: null, key: key, val: Json.Obj { first: first, count: count } }); }
            return pool.push(Node { next: null, key: key, val: Json.Arr { first: first, count: count } });
        }
        // A leaf is one push: the node is built at the end of the pool, the
        // decoded string straight into its payload, the key's bytes copied
        // in -- no intermediate node value anywhere.
        if c == '"' { return pool.push(Node { next: null, key: key, val: Json.Str { s: parse_string() } }); }
        if c == 't' { parse_word("true"); return pool.push(Node { next: null, key: key, val: Json.Bool { v: true } }); }
        if c == 'f' { parse_word("false"); return pool.push(Node { next: null, key: key, val: Json.Bool { v: false } }); }
        if c == 'n' { parse_word("null"); return pool.push(Node { next: null, key: key, val: Json.Null }); }
        return pool.push(Node { next: null, key: key, val: Json.Num { v: parse_number() } });
    }

    let root .= parse_value("");
    skip_space();
    guard pos == text.len else { return null, fail("trailing input") from parse; }
    return root, str("");
}

// --- printing ----------------------------------------------------------

fn quote(out: u8[>..]&, s: u8[:]) {
    out.push('"');
    for c in s {
        if c == '"' || c == '\\' { out.push('\\'); out.push(c); }
        else if c == '\n' { out.append("\\n"); }
        else if c == '\t' { out.append("\\t"); }
        else if c == '\r' { out.append("\\r"); }
        else if c < 32 {
            // Any other control byte, which JSON does not allow raw.
            out.append("\\u00");
            out.push(hex_char(c / 16));
            out.push(hex_char(c % 16));
        }
        else { out.push(c); }
    }
    out.push('"');
}

fn hex_char(d: u8) -> u8 { if d < 10 { '0' + d } else { 'a' + d - 10 } }

fn newline(out: u8[>..]&, indent: i64) {
    out.push('\n');
    for i in indent * 2 { out.push(' '); }
}

// Renders a node; `indent` < 0 means compact, no whitespace at all.
recursive fn render(n: Node&, out: u8[>..]&, indent: i64) {
    match n.val {
        Null => out.append("null"),
        Bool b => out.append(if b.v { "true" } else { "false" }),
        Num x => {
            // JSON has one number type; a whole one is written as an integer.
            // Only within 2^53, where every whole f64 is exact and the cast
            // cannot overflow.
            if x.v > -9007199254740992.0 && x.v < 9007199254740992.0 && (x.v as! i64) == x.v {
                format(out, x.v as! i64);
            } else { format(out, x.v); }
        },
        Str &s => quote(out, s.s),
        Arr &a => render_children(a.first, false, out, indent, '[', ']'),
        Obj &o => render_children(o.first, true, out, indent, '{', '}'),
    }
}

recursive fn render_children(first: Node?, keyed: bool, out: u8[>..]&, indent: i64, open: u8, close: u8) {
    out.push(open);
    var c = first;
    var i = 0;
    while c {                            // a plain reference inside the loop
        if i > 0 { out.push(','); }
        if indent >= 0 { newline(out, indent + 1); }
        if keyed { quote(out, c.key); out.push(':'); if indent >= 0 { out.push(' '); } }
        render(c, out, if indent >= 0 { indent + 1 } else { -1 });
        c .= c.next;
        i++;
    }
    if i > 0 && indent >= 0 { newline(out, indent); }
    out.push(close);
}

// --- querying ------------------------------------------------------------

// The member of an object named `key`, or null.
fn member(n: Node&, key: u8[:]) -> Node? {
    match n.val {
        Obj &o => {
            var c = o.first;
            while c {
                if c.key == key { return c; }
                c .= c.next;
            }
            null
        },
        _ => null,
    }
}

// Element i of an array, or null.
fn element(n: Node&, i: i64) -> Node? {
    match n.val {
        Arr &a => {
            var c = a.first;
            var k = 0;
            while c {
                if k == i { return c; }
                c .= c.next;
                k++;
            }
            null
        },
        _ => null,
    }
}

// --- the exported API ----------------------------------------------------
//
// Every export clears the globals it uses before anything else. After a
// runtime failure the R glue rewinds the data stacks but not the globals,
// so an export must never rely on what an earlier call left in them.

var out: u8[>..] = [];

// Re-renders the document, pretty (indent >= 0) or compact (indent < 0).
// On a syntax error the result is the message prefixed with "!": rendered
// JSON never starts with that byte.
export fn zugojson_format(text: u8[:], indent: i64) -> const u8[:] {
    pool.clear();
    out.clear();
    let root, err = parse(text);
    guard root else { out.push('!'); out.append(err); return out; }
    render(root, out, indent);
    return out;
}

// The syntax error as text, or an empty result for a valid document.
export fn zugojson_check(text: u8[:]) -> const u8[:] {
    pool.clear();
    out.clear();
    let root, err = parse(text);
    guard root else { out.append(err); return out; }
    return out;
}

// Test hook: a bounds-check failure on demand, so the tests can exercise
// the runtime's error path.
export fn zugojson_index_probe(i: i64) -> i64 {
    var a: i64[3] = [10, 20, 30];
    return a[i];
}
